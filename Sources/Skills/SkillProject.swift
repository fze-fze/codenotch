import Foundation
import os

/// A folder that keeps a set of skills of its own.
struct SkillProject: Identifiable, Equatable, Sendable, Codable {
    let url: URL
    /// Held at the top of the list. The one or two you are actually in today,
    /// separated from the ones you set up once and left.
    var isPinned: Bool = false
    /// The icon and colour it is recognised by.
    var mark: ProjectMark = .fallback

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }

    /// The path with `~` back in it, which is how anybody actually reads it.
    func displayPath(home: URL) -> String {
        let path = url.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        return path.hasPrefix(base + "/")
            ? "~" + path.dropFirst(base.count)
            : path
    }
}

/// Whether Claude Code can see this project's skills.
///
/// Its own bridge state rather than a `MountState`, because it is one link for
/// the whole directory instead of one per skill — and because the only thing
/// that can be done about it is make it, once.
enum ClaudeBridgeState: Equatable, Sendable {
    /// `.claude/skills` links to `.agents/skills`. Everything is visible.
    case linked
    /// Nothing there. Claude Code sees none of the project's skills.
    case absent
    /// A real `.claude/skills` directory with the project's own Claude-only
    /// skills in it. Left exactly where it is; per-skill links go inside it.
    case ownDirectory
    /// A link somewhere else entirely — somebody's arrangement, untouched.
    case foreignLink(destination: String)
}

/// Whether every agent in a project reads the same instructions.
///
/// `AGENTS.md` is the shared convention and three of the four read it by
/// themselves. Claude Code is the exception, and the probe that established
/// that is worth recording: with only `AGENTS.md` present and every tool
/// disabled, Claude Code could not answer a question the file answers — it
/// tried to `Read` the file instead, which says it can *see the name* but does
/// not get the *contents* in context. With `CLAUDE.md -> AGENTS.md` in place
/// and tools still disabled, it answered immediately. The link is the
/// difference between "it might go and look" and "it already knows".
enum ProjectInstructionsState: Equatable, Sendable {
    /// `CLAUDE.md` links to `AGENTS.md`. All four read the same file.
    case linked
    /// `AGENTS.md` is there and `CLAUDE.md` is not, so Claude Code is the one
    /// agent that starts each session without it.
    case absent
    /// A real `CLAUDE.md` and no `AGENTS.md` — instructions written for Claude
    /// Code alone, which the other three never see. Offered for adoption.
    case claudeOnly
    /// Both are real files. Two sets of instructions that may disagree; which
    /// one is right is not a thing to guess at, so this is reported and
    /// nothing is touched.
    case divergent
    /// Neither file. Nothing to bridge, and not Codenotch's business to write
    /// one — instructions are prose somebody has to mean.
    case none
    /// A `CLAUDE.md` link pointing at something else. Somebody's arrangement.
    case foreignLink(destination: String)

    /// Whether making the link would do anything.
    var canBridge: Bool { self == .absent }
}

/// Where a project keeps its skills, and what each agent makes of that.
///
/// **The layout is not a guess.** It was probed on this Mac with marker skills
/// planted in every candidate directory, and every claim below is what the
/// tools actually did:
///
/// - `<project>/.agents/skills/<name>` is read by **Codex**, **Cursor** and
///   **Antigravity** with no configuration. Codex was confirmed from its own
///   session log, which listed the marker among the skills it had loaded;
///   Cursor from its bundle, which classifies a path starting `.agents/skills/`
///   as `"workspace"`; Antigravity from its language server, which documents
///   `<workspace>/.agents/skills/<name>/`.
/// - **Claude Code** does *not* read it. It reads `<project>/.claude/skills`,
///   and it follows that directory through a symlink — with
///   `.claude/skills -> ../.agents/skills` in place it reported the marker that
///   it had missed a moment earlier. That one link is the whole difference.
///
/// So a project needs exactly two things written into it, and one of them only
/// once.
struct SkillProjectMount: Sendable {
    let project: URL
    let store: SkillStore
    let fileManager: FileManager

    init(project: URL, store: SkillStore, fileManager: FileManager = .default) {
        self.project = project
        self.store = store
        self.fileManager = fileManager
    }

    /// The directory three of the four agents read by themselves.
    var skillsDir: URL { project.appendingPathComponent(".agents/skills") }
    /// The directory the fourth one reads.
    var claudeDir: URL { project.appendingPathComponent(".claude/skills") }

    func destination(name: String) -> URL { skillsDir.appendingPathComponent(name) }

    // MARK: - Reading

    /// What this project makes of one skill.
    ///
    /// The same `MountState` the agent rows use, minus the two cases that
    /// cannot arise: a project is never `.notInstalled`, and nothing here
    /// reads a library by itself.
    func state(name: String) -> MountState {
        let target = destination(name: name)
        guard let attributes = try? fileManager.attributesOfItem(atPath: target.path) else {
            return .notMounted
        }
        guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
            // A real folder here is the project's *own* skill, committed to the
            // repo. Not a conflict in the sense of an accident — it is the
            // normal way a project-specific skill exists — but equally not
            // something to link over or delete.
            return .conflict(.realItem)
        }
        guard let resolved = linkDestination(target) else { return .notMounted }
        if store.contains(resolved) { return .mounted }
        return fileManager.fileExists(atPath: resolved.path)
            ? .conflict(.foreignLink(destination: resolved.path))
            : .conflict(.brokenLink(destination: resolved.path))
    }

    /// Every skill the project currently offers its agents, linked or its own.
    func installed() -> [ProjectSkill] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { SkillFrontmatter.isSkill(directory: $0, fileManager: fileManager) }
            .map { entry in
                let name = entry.lastPathComponent
                return ProjectSkill(
                    name: name,
                    url: entry,
                    frontmatter: SkillFrontmatter.read(skillDirectory: entry),
                    state: state(name: name)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Follows the chain where it resolves, and keeps the intent where it
    /// dangles — the same reasoning as the global mount's.
    func linkDestination(_ url: URL) -> URL? {
        guard let raw = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }
        let absolute = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : url.deletingLastPathComponent().appendingPathComponent(raw)
        return absolute.resolvingSymlinksInPath()
    }

    // MARK: - Writing

    /// Link one skill into the project.
    ///
    /// The link is **absolute**, unlike the Claude bridge below. It has to
    /// leave the project — into `~/.codenotch/skills` or into a cloned repo —
    /// and a relative path out of a project is a path that depends on where the
    /// project happens to sit. It is also why `.agents/skills/` belongs in
    /// `.gitignore`: git stores a symlink as its target string, so committing
    /// `/Users/you/...` hands everyone else a dead link. The links are a
    /// product of the project's skill list, not the record of it.
    func link(_ skill: StoredSkill) throws {
        let target = destination(name: skill.name)
        switch state(name: skill.name) {
        case .mounted:
            // Already linked, but possibly at a different root — repoint it
            // rather than reporting success on the wrong target.
            guard linkDestination(target)?.standardizedFileURL.path
                    != skill.url.resolvingSymlinksInPath().standardizedFileURL.path else { return }
            try fileManager.removeItem(at: target)
        case .conflict(.realItem), .conflict(.foreignLink):
            throw SkillMountError.notOurs(path: target.path)
        case .conflict(.brokenLink(let destination)):
            Log.usage.debug("replacing broken project link for \(skill.name, privacy: .public): it pointed at \(destination, privacy: .public)")
            try? fileManager.removeItem(at: target)
        case .notMounted, .notInstalled, .shared:
            if (try? fileManager.destinationOfSymbolicLink(atPath: target.path)) != nil {
                try? fileManager.removeItem(at: target)
            }
        }

        try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: target, withDestinationURL: skill.url)
        Log.usage.debug("linked skill \(skill.name, privacy: .public) into \(project.lastPathComponent, privacy: .public)")
    }

    /// Remove our link, and only our link. A real folder is the project's own
    /// skill and is never deleted from here.
    func unlink(name: String) throws {
        let target = destination(name: name)
        switch state(name: name) {
        case .notMounted, .notInstalled, .shared:
            return
        case .conflict(.realItem), .conflict(.foreignLink):
            throw SkillMountError.notOurs(path: target.path)
        case .mounted, .conflict(.brokenLink):
            try fileManager.removeItem(at: target)
            Log.usage.debug("unlinked skill \(name, privacy: .public) from \(project.lastPathComponent, privacy: .public)")
        }
    }

    // MARK: - The Claude bridge

    var claudeBridge: ClaudeBridgeState {
        guard let attributes = try? fileManager.attributesOfItem(atPath: claudeDir.path) else {
            return .absent
        }
        guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
            return .ownDirectory
        }
        guard let resolved = linkDestination(claudeDir) else { return .absent }
        return resolved.standardizedFileURL.path
            == skillsDir.resolvingSymlinksInPath().standardizedFileURL.path
            ? .linked
            : .foreignLink(destination: resolved.path)
    }

    /// Point `.claude/skills` at `.agents/skills`, so Claude Code sees what the
    /// other three already see.
    ///
    /// **Relative**, and deliberately: this link stays inside the project, so
    /// `../.agents/skills` is true wherever the project is moved, cloned or
    /// checked out — and unlike the per-skill links, this one is worth
    /// committing. One line in a repo and every teammate's Claude Code finds
    /// the skills the repo ships.
    func mountClaudeBridge() throws {
        switch claudeBridge {
        case .linked:
            return
        case .ownDirectory, .foreignLink:
            throw SkillMountError.notOurs(path: claudeDir.path)
        case .absent:
            break
        }
        // A dangling link occupies the name and would fail `createSymbolicLink`
        // with "file exists".
        if (try? fileManager.destinationOfSymbolicLink(atPath: claudeDir.path)) != nil {
            try? fileManager.removeItem(at: claudeDir)
        }
        try fileManager.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: claudeDir.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(atPath: claudeDir.path,
                                           withDestinationPath: "../.agents/skills")
        Log.usage.debug("bridged .claude/skills in \(project.lastPathComponent, privacy: .public)")
    }

    func removeClaudeBridge() throws {
        switch claudeBridge {
        case .absent:            return
        case .ownDirectory, .foreignLink:
            throw SkillMountError.notOurs(path: claudeDir.path)
        case .linked:
            try fileManager.removeItem(at: claudeDir)
        }
    }

    // MARK: - The instructions bridge

    /// The file three of the four agents read by themselves.
    var instructionsFile: URL { project.appendingPathComponent("AGENTS.md") }
    /// The file the fourth one reads, and the only one it auto-loads.
    var claudeInstructionsFile: URL { project.appendingPathComponent("CLAUDE.md") }

    var instructions: ProjectInstructionsState {
        let hasShared = fileManager.fileExists(atPath: instructionsFile.path)
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: claudeInstructionsFile.path
        ) else {
            return hasShared ? .absent : .none
        }

        guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
            return hasShared ? .divergent : .claudeOnly
        }
        guard let resolved = linkDestination(claudeInstructionsFile) else {
            // A dangling `CLAUDE.md` link. Debris either way: with an
            // `AGENTS.md` to point at it is one relink away, without one there
            // is nothing to do but say the file is empty.
            return hasShared ? .absent : .none
        }
        return resolved.standardizedFileURL.path
            == instructionsFile.resolvingSymlinksInPath().standardizedFileURL.path
            ? .linked
            : .foreignLink(destination: resolved.path)
    }

    /// Point `CLAUDE.md` at `AGENTS.md`.
    ///
    /// Relative, and for the same reason as the skills bridge: it never leaves
    /// the project, so `AGENTS.md` is true wherever the project is checked out
    /// — and this one belongs in the repository, where it makes every
    /// teammate's Claude Code read the instructions the other three already do.
    func bridgeInstructions() throws {
        switch instructions {
        case .linked:
            return
        case .none, .claudeOnly:
            throw SkillMountError.missingInLibrary(name: "AGENTS.md")
        case .divergent, .foreignLink:
            throw SkillMountError.notOurs(path: claudeInstructionsFile.path)
        case .absent:
            break
        }
        if (try? fileManager.destinationOfSymbolicLink(
            atPath: claudeInstructionsFile.path
        )) != nil {
            try? fileManager.removeItem(at: claudeInstructionsFile)
        }
        try fileManager.createSymbolicLink(atPath: claudeInstructionsFile.path,
                                           withDestinationPath: "AGENTS.md")
        Log.usage.debug("bridged CLAUDE.md in \(project.lastPathComponent, privacy: .public)")
    }

    /// Rename a Claude-only `CLAUDE.md` to `AGENTS.md` and link it back.
    ///
    /// The same move `promote` makes for a skill living in one agent's folder,
    /// and for the same reason: instructions written for one agent are almost
    /// never *about* that agent. Renaming them is what makes the other three
    /// read what they were always meant to read, and the link back means
    /// Claude Code loses nothing.
    func adoptClaudeInstructions() throws {
        guard instructions == .claudeOnly else {
            throw SkillMountError.notOurs(path: claudeInstructionsFile.path)
        }
        try fileManager.moveItem(at: claudeInstructionsFile, to: instructionsFile)
        try fileManager.createSymbolicLink(atPath: claudeInstructionsFile.path,
                                           withDestinationPath: "AGENTS.md")
        Log.usage.debug("adopted CLAUDE.md as AGENTS.md in \(project.lastPathComponent, privacy: .public)")
    }

    func removeInstructionsBridge() throws {
        switch instructions {
        case .linked:
            try fileManager.removeItem(at: claudeInstructionsFile)
        case .absent, .none, .claudeOnly:
            return
        case .divergent, .foreignLink:
            throw SkillMountError.notOurs(path: claudeInstructionsFile.path)
        }
    }

    /// Everything a project needs before it holds a single skill.
    ///
    /// Run when a project is added, not when its first skill is linked. The
    /// links cost nothing and are the same two either way, and doing it later
    /// means a freshly added project greets you with an orange warning about a
    /// thing you have not had a chance to do yet.
    ///
    /// Both halves are best-effort and neither ever replaces anything real: a
    /// project with its own `.claude/skills` folder, or with a `CLAUDE.md` that
    /// disagrees with its `AGENTS.md`, is left exactly as it was and says so on
    /// its row. Nothing here creates an `AGENTS.md` — instructions are prose
    /// somebody has to mean.
    func prepare() {
        try? mountClaudeBridge()
        if instructions.canBridge { try? bridgeInstructions() }
    }

    /// Whether the project has been prepared at all — used to decide between
    /// "add a skill" and "set this project up".
    var isPrepared: Bool {
        fileManager.fileExists(atPath: skillsDir.path) && claudeBridge == .linked
    }
}

/// One skill as a project sees it.
struct ProjectSkill: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL
    let frontmatter: SkillFrontmatter
    let state: MountState

    var id: String { name }
    var displayName: String { frontmatter.name ?? name }
    var summary: String? { frontmatter.description }
    /// A real folder in `.agents/skills` — written for this project and
    /// committed with it, rather than linked in from a root.
    var isOwn: Bool { state == .conflict(.realItem) }
}
