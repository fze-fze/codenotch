import Combine
import Foundation
import os

/// One skill, and where each agent stands on it.
struct SkillRow: Identifiable, Equatable, Sendable {
    let skill: LibrarySkill
    let states: [SkillAgent: MountState]

    var id: String { skill.id }
    var name: String { skill.name }

    /// Agents that could have this and do not — what "Distribute to all" would
    /// act on. A broken link counts: it points at a folder that is gone, so
    /// replacing it loses nothing and repairs a skill the agent currently sees
    /// as broken.
    var missing: [SkillAgent] {
        SkillAgent.allCases.filter {
            states[$0] == .notMounted || states[$0]?.isBrokenLink == true
        }
    }

    /// Agents where something real is in the way. Broken links are excluded —
    /// they are debris rather than an obstruction, and the warning triangle is
    /// for things Codenotch will not touch.
    var conflicted: [SkillAgent] {
        SkillAgent.allCases.filter {
            switch states[$0] {
            case .conflict(.realItem), .conflict(.foreignLink): return true
            default: return false
            }
        }
    }

    /// How many installed agents can currently see it, out of how many there are.
    var reach: (reached: Int, total: Int) {
        let relevant = SkillAgent.allCases.filter { states[$0] != .notInstalled }
        return (relevant.filter { states[$0]?.isReachable == true }.count, relevant.count)
    }

    var isEverywhere: Bool {
        let (reached, total) = reach
        return total > 0 && reached == total
    }
}

/// What the Skill Manager window is looking at.
///
/// Every filesystem read and write happens off the main actor and the results
/// are republished here, because the scans walk five directories and stat every
/// entry in them — cheap, but not cheap enough to do on the run loop while a
/// switch is animating.
@MainActor
final class SkillManagerModel: ObservableObject {
    @Published private(set) var rows: [SkillRow] = []
    /// Only the agents actually installed. A row for a tool you do not use is
    /// noise, and there is nothing it could ever be asked to do.
    @Published private(set) var agents: [SkillAgent] = []
    /// Skills that live in one agent's own folder. Grouped for the sidebar,
    /// which is the whole point of listing them — "what does Codex have that
    /// nothing else does" is the question they answer.
    @Published private(set) var agentSkills: [SkillAgent: [AgentSkill]] = [:]
    /// Projects that keep skills of their own, and what each currently holds.
    /// Empty until a project is added — this half of the window is opt-in.
    @Published private(set) var projects: [SkillProject] = []
    @Published private(set) var projectSkills: [String: [ProjectSkill]] = [:]
    @Published private(set) var projectBridges: [String: ClaudeBridgeState] = [:]
    /// Whether each project's four agents read the same `AGENTS.md`.
    @Published private(set) var projectInstructions: [String: ProjectInstructionsState] = [:]
    /// Everything that can be put *into* a project: the quiet store, the
    /// global library, and any registered origin repository.
    @Published private(set) var storeSkills: [StoredSkill] = []
    @Published private(set) var origins: [URL] = []
    /// Every tag in use, in the order they should be offered: the ones most
    /// skills carry first.
    @Published private(set) var allTags: [String] = []
    @Published private(set) var isRefreshing = false
    /// Set when something went wrong in a way the user has to see — almost
    /// always a conflict, which is a thing to be told about rather than a
    /// failure to retry.
    @Published var problem: String?

    let home: URL
    private let library: SkillLibrary
    private let mount: SkillMount
    private let scan: SkillScan
    private let registry: SkillProjectRegistry
    private let fileManager: FileManager
    private let defaults: UserDefaults

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         defaults: UserDefaults = .standard,
         fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
        self.defaults = defaults
        self.library = SkillLibrary(home: home, fileManager: fileManager)
        self.mount = SkillMount(home: home, fileManager: fileManager)
        self.scan = SkillScan(home: home, fileManager: fileManager)
        self.registry = SkillProjectRegistry(defaults: defaults, fileManager: fileManager)
        self.tagStore = SkillTags(defaults: defaults)
    }

    private let tagStore: SkillTags

    // MARK: - Tags

    /// Everything this skill is tagged with — the author's tags and yours.
    func tags(for name: String, declared: [String]) -> [String] {
        tagStore.all(for: name, declared: declared)
    }

    /// Just yours, which are the only ones that can be taken off here.
    func ownTags(for name: String) -> [String] { tagStore.own(name) }

    func addTag(_ tag: String, to name: String) {
        tagStore.add(tag, to: name)
        refresh()
    }

    func removeTag(_ tag: String, from name: String) {
        tagStore.remove(tag, from: name)
        refresh()
    }

    var libraryRoot: URL { library.root }

    /// Built fresh each time rather than held: its roots include the
    /// registered origins, and those change while the window is open.
    private var store: SkillStore {
        SkillStore(home: home, origins: registry.origins, fileManager: fileManager)
    }

    /// What a project's agents can actually see of one skill.
    ///
    /// One answer in one place, because the two pages that ask were drifting:
    /// the project page showed a global skill's switch *off* — the page saying
    /// a project did not have something it plainly had — while the skill page
    /// counted the same skill as reaching everything.
    enum ProjectReach: Equatable, Sendable {
        /// Loaded in every session. The project has it whatever it links.
        case everywhere
        /// This project links it.
        case linked
        /// Not here.
        case absent
        /// Something real is in the way, which outranks everything above: the
        /// project has its own folder of that name and *that* is what its
        /// agents read.
        case blocked(MountState)

        var isReachable: Bool { self == .everywhere || self == .linked }
        /// Whether the project's own switch decides anything.
        var isChoosable: Bool { self == .linked || self == .absent }
    }

    func reach(of skill: StoredSkill, in project: SkillProject) -> ProjectReach {
        let state = (projectSkills[project.id] ?? [])
            .first { $0.name == skill.name }?.state ?? .notMounted
        switch state {
        case .conflict(.realItem), .conflict(.foreignLink):
            return .blocked(state)
        default:
            break
        }
        if skill.isGlobal { return .everywhere }
        return state == .mounted ? .linked : .absent
    }

    /// Which projects currently link a skill, by project id. Read straight
    /// off the scan rather than kept as a second index, because the links are
    /// the truth and an index would be one more thing to get out of step.
    func projectsUsing(_ name: String) -> [String] {
        projects.compactMap { project in
            (projectSkills[project.id] ?? []).contains {
                $0.name == name && $0.state == .mounted
            } ? project.id : nil
        }
    }

    private func projectMount(_ project: SkillProject) -> SkillProjectMount {
        SkillProjectMount(project: project.url, store: store, fileManager: fileManager)
    }

    // MARK: - Reading

    func refresh() {
        isRefreshing = true
        // Not a `guard !isRefreshing` — every write asks for a refresh the
        // moment it finishes, and skipping the one that follows the write is
        // exactly how a toggle ends up showing the state from before it was
        // flipped. Overlapping scans are allowed; a generation counter is what
        // stops the slower one landing on top of the newer answer.
        generation += 1
        let generation = self.generation
        let library = self.library
        let mount = self.mount
        let scan = self.scan
        let home = self.home
        let store = self.store
        let registry = self.registry
        let fileManager = self.fileManager
        let defaults = self.defaults

        Task.detached(priority: .userInitiated) {
            let rows = library.list().map {
                SkillRow(skill: $0, states: mount.states(name: $0.name))
            }
            let agents = SkillAgent.installed(home: home)
            let grouped = Dictionary(grouping: scan.agentSkills(), by: \.agent)

            let projects = registry.projects
            var projectSkills: [String: [ProjectSkill]] = [:]
            var bridges: [String: ClaudeBridgeState] = [:]
            var instructions: [String: ProjectInstructionsState] = [:]
            for project in projects {
                let projectMount = SkillProjectMount(project: project.url, store: store,
                                                     fileManager: fileManager)
                projectSkills[project.id] = projectMount.installed()
                bridges[project.id] = projectMount.claudeBridge
                instructions[project.id] = projectMount.instructions
            }
            let available = store.available()
            let origins = registry.origins

            // Counted across everything on the page, library and agent-only
            // alike, so the filter row offers what is actually there.
            let tagStore = SkillTags(defaults: defaults)
            var counts: [String: Int] = [:]
            for skill in available {
                for tag in tagStore.all(for: skill.name, declared: skill.frontmatter.tags) {
                    counts[tag, default: 0] += 1
                }
            }
            for skill in grouped.values.flatMap({ $0 }) {
                for tag in tagStore.all(for: skill.name, declared: skill.frontmatter.tags) {
                    counts[tag, default: 0] += 1
                }
            }
            let tags = counts.sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }.map(\.key)
            // Copied to `let` before the hop: the loop above builds them with
            // `var`, and a mutable capture in a concurrent closure is an error
            // under Swift 6.
            let builtSkills = projectSkills
            let builtBridges = bridges
            let builtInstructions = instructions

            await MainActor.run { [weak self] in
                guard let self, generation == self.generation else { return }
                self.rows = rows
                self.agents = agents
                self.agentSkills = grouped
                self.projects = projects
                self.projectSkills = builtSkills
                self.projectBridges = builtBridges
                self.projectInstructions = builtInstructions
                self.storeSkills = available
                self.origins = origins
                self.allTags = tags
                self.isRefreshing = false
            }
        }
    }

    private var generation = 0

    /// Drop everything the pages were showing, for when the window closes.
    ///
    /// This is not a small saving. `rows` and `storeSkills` carry every skill
    /// on the machine with its parsed frontmatter — name, description and tags
    /// per skill, and a description is prose — and `projectSkills` carries the
    /// same again per registered project. Held after the window went away it
    /// was memory serving a page nobody could see. Every page re-reads on
    /// `onAppear`, and `show` refreshes on the way in, so there is nothing here
    /// that is not rebuilt before it is next looked at.
    ///
    /// The generation counter is bumped so a scan already in flight cannot land
    /// its results into the model we have just emptied.
    func releaseCaches() {
        generation += 1
        rows = []
        agents = []
        agentSkills = [:]
        projects = []
        projectSkills = [:]
        projectBridges = [:]
        projectInstructions = [:]
        storeSkills = []
        origins = []
        allTags = []
        isRefreshing = false
    }

    // MARK: - Writing

    /// Put a skill in front of every agent that can take it.
    func distribute(_ name: String) {
        perform { mount in mount.mountEverywhere(name: name) }
    }

    /// Take it back out of every agent's directory. The library keeps it.
    func withdraw(_ name: String) {
        perform { mount in mount.unmountEverywhere(name: name) }
    }

    func setMounted(_ wanted: Bool, skill name: String, for agent: SkillAgent) {
        perform { mount in
            do {
                if wanted {
                    try mount.mount(name: name, into: agent)
                } else {
                    try mount.unmount(name: name, from: agent)
                }
                return [:]
            } catch {
                return [agent: error]
            }
        }
    }

    /// Move an agent's private skill into the library, then put it in front of
    /// every agent — including the one it came from, which now reaches it
    /// through a link rather than by owning it.
    ///
    /// This is the one path by which a skill becomes global. There is no
    /// marketplace and no import-from-URL; the premise is that you already have
    /// skills, scattered across whichever agent you set up first.
    func promote(_ candidates: [AgentSkill]) {
        let store = self.store
        run { () -> String? in
            var failures: [String] = []
            for candidate in candidates {
                do {
                    // Into the store and *not* switched on. Taking a skill in
                    // makes it available to everything; making it global is a
                    // separate decision with a separate cost, and doing both at
                    // once was the old behaviour back when global was the only
                    // place a skill could live.
                    try store.takeIn(candidate.url, name: candidate.name)
                } catch {
                    failures.append("\(candidate.name): \(error.localizedDescription)")
                }
            }
            return failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }

    /// Unmount everywhere, then move the library copy to the Trash.
    ///
    /// That order and not the other: removing the library entry first would
    /// leave every agent holding a link to nothing, which reads to them as a
    /// broken skill rather than as an absent one.
    func delete(_ name: String) {
        let library = self.library
        let mount = self.mount
        run { () -> String? in
            var failures = Self.describe(mount.unmountEverywhere(name: name))
            // A conflict is not a reason to leave the library entry behind —
            // the folder in the way was never ours, and it stays either way.
            do { try library.remove(name: name) } catch {
                failures.append(error.localizedDescription)
            }
            return failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }

    // MARK: - Projects

    /// Show Codenotch a project, and set it up.
    ///
    /// Adding writes the two links Claude Code needs — `.claude/skills` and,
    /// where there is an `AGENTS.md` to point at, `CLAUDE.md`. The other three
    /// agents need nothing. Doing it here rather than at the first skill is
    /// what stops a project appearing with a warning about a step the user has
    /// not been offered yet.
    func addProject(_ url: URL) {
        registry.add(project: url)
        let store = self.store
        let fileManager = self.fileManager
        run { () -> String? in
            SkillProjectMount(project: url, store: store, fileManager: fileManager).prepare()
            return nil
        }
    }

    /// Forget a project. Its links stay exactly where they are: the folder is
    /// the user's, and a row disappearing from this window is not a reason to
    /// reach into it.
    func forgetProject(_ project: SkillProject) {
        registry.remove(project: project.url)
        refresh()
    }

    /// Hold a project at the top of the list.
    func setPinned(_ wanted: Bool, project: SkillProject) {
        registry.setPinned(wanted, project: project.url)
        refresh()
    }

    /// Give a project an icon and a colour.
    func setMark(_ mark: ProjectMark, project: SkillProject) {
        registry.setMark(mark, project: project.url)
        refresh()
    }

    func addOrigin(_ url: URL) {
        registry.add(origin: url)
        refresh()
    }

    func removeOrigin(_ url: URL) {
        registry.remove(origin: url)
        refresh()
    }

    /// Put a skill into a project, or take it back out.
    ///
    /// The Claude bridge is made on the way in, not at some earlier setup step:
    /// three of the four agents need nothing, and the fourth needs one link
    /// that costs nothing to have and is useless before there is a skill behind
    /// it. Doing it here means a project is never half-prepared.
    func setLinked(_ wanted: Bool, skill name: String, in project: SkillProject) {
        let projectMount = self.projectMount(project)
        let skill = storeSkills.first { $0.name == name }
        run { () -> String? in
            do {
                if wanted {
                    guard let skill else {
                        throw SkillMountError.missingInLibrary(name: name)
                    }
                    try projectMount.link(skill)
                    try projectMount.mountClaudeBridge()
                } else {
                    try projectMount.unlink(name: name)
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    /// Make `.claude/skills -> ../.agents/skills` by itself, for a project that
    /// already has skills but was set up by hand.
    func bridgeClaude(in project: SkillProject) {
        let projectMount = self.projectMount(project)
        run { () -> String? in
            do { try projectMount.mountClaudeBridge(); return nil }
            catch { return error.localizedDescription }
        }
    }

    /// Point `CLAUDE.md` at `AGENTS.md`, so the one agent that does not read
    /// the shared instructions file starts each session with them anyway.
    func bridgeInstructions(in project: SkillProject) {
        let projectMount = self.projectMount(project)
        run { () -> String? in
            do { try projectMount.bridgeInstructions(); return nil }
            catch { return error.localizedDescription }
        }
    }

    /// Rename a Claude-only `CLAUDE.md` to `AGENTS.md` and link it back, so
    /// the other three read instructions that were never really Claude's.
    func adoptClaudeInstructions(in project: SkillProject) {
        let projectMount = self.projectMount(project)
        run { () -> String? in
            do { try projectMount.adoptClaudeInstructions(); return nil }
            catch { return error.localizedDescription }
        }
    }

    /// Load a skill in every session, or stop.
    ///
    /// One switch and two writes: the link in `~/.agents/skills` that Codex,
    /// Cursor and Grok follow, and the per-agent links for the two that do not
    /// read that folder. The skill itself never moves — the whole point of
    /// keeping its real folder in the store.
    ///
    /// Unmount before unlinking, and link before mounting. A link left
    /// pointing at something that has gone is a *broken* skill, which is worse
    /// than either end state.
    func setGlobal(_ wanted: Bool, skill name: String) {
        Log.usage.info("reach asked: \(name, privacy: .public) global=\(wanted, privacy: .public)")
        let mount = self.mount
        let store = self.store
        run { () -> String? in
            var failures: [String] = []
            if wanted {
                do { try store.setGlobal(true, name: name) } catch {
                    failures.append(error.localizedDescription)
                }
                failures += Self.describe(mount.mountEverywhere(name: name))
            } else {
                failures += Self.describe(mount.unmountEverywhere(name: name))
                do { try store.setGlobal(false, name: name) } catch {
                    failures.append(error.localizedDescription)
                }
            }
            return failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }

    // MARK: - Plumbing

    /// Run a mount operation off the main actor, then re-read everything.
    private func perform(_ work: @escaping @Sendable (SkillMount) -> [SkillAgent: Error]) {
        let mount = self.mount
        run {
            let failures = Self.describe(work(mount))
            return failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }

    private func run(_ work: @escaping @Sendable () -> String?) {
        Task.detached(priority: .userInitiated) {
            let problem = work()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let problem {
                    Log.usage.info("reported: \(problem, privacy: .public)")
                    self.problem = problem
                }
                self.refresh()
            }
        }
    }

    /// `nonisolated` because it is called from the detached tasks above, where
    /// the main actor is not in scope.
    nonisolated private static func describe(_ errors: [SkillAgent: Error]) -> [String] {
        SkillAgent.allCases.compactMap { agent in
            errors[agent].map { "\(agent.displayName): \($0.localizedDescription)" }
        }
    }
}
