import Foundation
import os

/// The quiet store: `~/.codenotch/skills`, a folder **no agent reads**.
///
/// This is the inversion at the heart of the project mode, and it is worth
/// spelling out because the global design argues the exact opposite.
///
/// For distributing a skill everywhere, `~/.agents/skills` is the perfect
/// library precisely *because* Codex and Cursor read it with no configuration —
/// putting a skill there is installing it for them. But that same fact is fatal
/// to "install this skill in one project only": anything left in
/// `~/.agents/skills` is loaded into every session of every project those tools
/// ever open. A measurement from this Mac, taken from a real Codex session:
/// twenty-five skills, 21 KB of descriptions, and Codex's own warning that it
/// had already *truncated* them to fit its skills budget.
///
/// So a skill that should reach one project has to rest somewhere nothing
/// scans. `~/.codenotch/skills` was rejected for the global library and is
/// right here for the same reason it was wrong there — being a name only
/// Codenotch knows is the entire point.
///
/// **Every managed skill's real folder lives here, global or not.** Being
/// loaded everywhere is a *symlink* at `~/.agents/skills/<name>` pointing back
/// into this store, not a different home — Codex was probed and follows such a
/// link, listing a skill whose only real copy was in `~/.codenotch/skills`.
///
/// That is the difference between a switch that moves somebody's prose around
/// and one that writes or removes a link. Three things fall out of it:
/// the real path never changes, so Finder and an editor always go to the same
/// place; toggling is trivially reversible; and a link somebody else made into
/// `~/.agents/skills/<name>` keeps resolving, where moving the folder would
/// have broken it silently.
///
/// Skills that live in a cloned repository (`~/GitHub/…-skills/skills/x`) need
/// no store at all: the repo is already somewhere nothing scans, and moving
/// them out of it would cut them off from `git pull`. Those are registered as
/// **origins** and linked where they lie.
struct SkillStore: Sendable {
    let home: URL
    let fileManager: FileManager
    /// Folders outside the store that also hold real skills — cloned skill
    /// repositories, most often. Registered rather than searched for: guessing
    /// at `~/GitHub/*/skills` would be a scan of somebody's whole disk.
    let origins: [URL]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         origins: [URL] = [],
         fileManager: FileManager = .default) {
        self.home = home
        self.origins = origins
        self.fileManager = fileManager
    }

    var root: URL { home.appendingPathComponent(".codenotch/skills") }

    /// The folder Codex, Cursor and Grok read in every project. Not a home for
    /// skills any more — a place to *point from*. What is in it is a link per
    /// globally-loaded skill, and whatever real folders were there before
    /// Codenotch was asked to take them in.
    var globalRoot: URL { SkillAgent.sharedLibrary(home: home) }

    /// Every root that can hold the real copy of a skill, nearest first.
    ///
    /// A link is recognised as ours when it lands in one of these. The global
    /// root is still included, because a skill that has never been taken in is
    /// a real folder sitting in it.
    var roots: [URL] { [root, globalRoot] + origins }

    func contains(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return roots.contains { candidate in
            let base = candidate.resolvingSymlinksInPath().standardizedFileURL.path
            return path == base || path.hasPrefix(base + "/")
        }
    }

    // MARK: - Reading

    /// Every skill available to be put into a project, from every root.
    ///
    /// Deduplicated by folder name, nearest root winning, because that is what
    /// a link can express: one name in `<project>/.agents/skills` points at one
    /// folder. Two roots offering `pdf` is a collision to be reported, not a
    /// pair of rows pretending they can both be installed.
    func available() -> [StoredSkill] {
        var byName: [String: StoredSkill] = [:]
        var order: [String] = []

        for (index, root) in roots.enumerated() {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries.sorted(by: {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }) {
                guard SkillFrontmatter.isSkill(directory: entry, fileManager: fileManager) else {
                    continue
                }
                let name = entry.lastPathComponent
                // A link in the global root is a *reach*, not a copy: it is
                // counted by `isGlobal(name:)` below and must not be offered
                // as a second skill of the same name.
                if index == 1, isOurGlobalLink(name: name) { continue }

                let skill = StoredSkill(
                    name: name, url: entry,
                    frontmatter: SkillFrontmatter.read(skillDirectory: entry),
                    isGlobal: isGlobal(name: name),
                    isTakenIn: index == 0,
                    shadowed: byName[name] != nil
                )
                if byName[name] == nil {
                    byName[name] = skill
                    order.append(name)
                } else {
                    // Kept only as a warning on the winner's row. Nothing can
                    // be done to the loser from here: it is a real folder in
                    // somebody's root, and the fix is to rename one of them.
                    byName[name]?.shadowedBy.append(entry)
                }
            }
        }

        return order.compactMap { byName[$0] }
    }

    // MARK: - Writing

    // MARK: - Reach

    /// Is this skill loaded in every session?
    ///
    /// True for both shapes the global root can hold: a link we wrote, and a
    /// real folder that was there before anyone asked us to take it in.
    func isGlobal(name: String) -> Bool {
        fileManager.fileExists(atPath: globalRoot.appendingPathComponent(name).path)
    }

    /// A symlink in the global root resolving into a root we manage.
    func isOurGlobalLink(name: String) -> Bool {
        let entry = globalRoot.appendingPathComponent(name)
        guard let attributes = try? fileManager.attributesOfItem(atPath: entry.path),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink,
              let raw = try? fileManager.destinationOfSymbolicLink(atPath: entry.path)
        else { return false }
        let absolute = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : entry.deletingLastPathComponent().appendingPathComponent(raw)
        return contains(absolute)
    }

    /// Load it in every session, or stop.
    ///
    /// Switching on writes one symlink; switching off removes it. Neither
    /// touches the skill itself — which is the whole reason the real folder
    /// lives in the store rather than moving between two homes.
    ///
    /// The one move left is the migration: a skill that is still a real folder
    /// in `~/.agents/skills` has never been taken in, and switching it *off*
    /// is the moment to do it. Nothing else would work — leaving it there is
    /// exactly the state being switched off.
    func setGlobal(_ wanted: Bool, name: String) throws {
        let entry = globalRoot.appendingPathComponent(name)
        let isLink = isOurGlobalLink(name: name)
        let exists = fileManager.fileExists(atPath: entry.path)

        if wanted {
            guard !isLink else { return }
            if exists {
                // Already a real folder there: it is global by being present,
                // and replacing it with a link to a copy of itself would be
                // two folders where there was one.
                Log.usage.info("reach: \(name, privacy: .public) is already a real folder in the global root")
                return
            }
            let source = try realFolder(name: name)
            try fileManager.createDirectory(at: globalRoot, withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: entry, withDestinationURL: source)
            Log.usage.info("reach: \(name, privacy: .public) linked into the global root")
            return
        }

        guard exists else { return }
        if isLink {
            try fileManager.removeItem(at: entry)
            Log.usage.info("reach: \(name, privacy: .public) unlinked from the global root")
            return
        }
        // A real folder. Somebody else's link may point at it, so this is the
        // one case where switching off costs a move — and afterwards it never
        // will again.
        guard (try? fileManager.destinationOfSymbolicLink(atPath: entry.path)) == nil else {
            // A link somewhere we do not manage. Not ours to remove.
            throw SkillMountError.notOurs(path: entry.path)
        }
        try take(entry, name: name)
    }

    /// Where the real folder is, wherever it has got to.
    private func realFolder(name: String) throws -> URL {
        for candidate in roots {
            let url = candidate.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            // A link in the global root points at one of the others; keep
            // looking rather than pointing a link at a link.
            if candidate == globalRoot, isOurGlobalLink(name: name) { continue }
            return url
        }
        throw SkillMountError.missingInLibrary(name: name)
    }

    /// Move any real skill folder into the store.
    ///
    /// Refused for a skill that is a *subdirectory* of a checkout. Pulling one
    /// folder out of somebody's repository detaches it from `git pull`, so the
    /// next version of it silently never arrives. Those are linked where they
    /// lie instead, which is what registering the repo as an origin is for.
    ///
    /// A skill that **is** the repository — its own folder holding the `.git` —
    /// is a different case and moves freely: the checkout travels with it, and
    /// `git pull` works exactly as well from the store. Refusing that was a
    /// bug, and a common one to hit: a skill cloned straight into
    /// `~/.codex/skills/<name>` is its own repo by construction.
    @discardableResult
    func take(_ source: URL, name: String? = nil) throws -> StoredSkill {
        let name = name ?? source.lastPathComponent
        // `info` and not `debug`: debug messages are not kept, and the first
        // time this did nothing in the real window there was no record of how
        // far it had got. Every refusal below is silent from the outside, so
        // each one says so here.
        Log.usage.info("store: taking \(name, privacy: .public) from \(source.path, privacy: .public)")

        if let repo = Self.enclosingRepository(of: source, fileManager: fileManager) {
            Log.usage.info("store: refused \(name, privacy: .public) — a subdirectory of the repo at \(repo.path, privacy: .public)")
            throw SkillStoreError.insideRepository(path: source.path, repo: repo.path)
        }

        let destination = root.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destination.path) {
            guard destination.resolvingSymlinksInPath().path
                    != source.resolvingSymlinksInPath().path else {
                return StoredSkill(name: name, url: destination,
                                   frontmatter: SkillFrontmatter.read(skillDirectory: destination),
                                   isGlobal: isGlobal(name: name), isTakenIn: true,
                                   shadowed: false)
            }
            Log.usage.info("store: refused \(name, privacy: .public) — the name is taken at \(destination.path, privacy: .public)")
            throw SkillLibraryError.nameTaken(name: name)
        }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            Log.usage.info("store: could not move \(name, privacy: .public) into \(root.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        Log.usage.info("store: stored \(name, privacy: .public) at \(destination.path, privacy: .public)")
        return StoredSkill(name: name, url: destination,
                           frontmatter: SkillFrontmatter.read(skillDirectory: destination),
                           isGlobal: isGlobal(name: name), isTakenIn: true,
                           shadowed: false)
    }

    /// Take a skill that lives in one agent's own folder into the store, and
    /// leave a link where it was.
    ///
    /// The link back is not a courtesy, it is the difference between taking a
    /// skill in and taking it away: `~/.codex/skills/x` moved into the store
    /// with nothing left behind is a skill Codex has lost. Afterwards the same
    /// folder is reachable from anywhere — the agent that had it, any project
    /// that links it, and globally if it is switched on.
    @discardableResult
    func takeIn(_ source: URL, name: String? = nil) throws -> StoredSkill {
        let name = name ?? source.lastPathComponent
        let skill = try take(source, name: name)
        do {
            try fileManager.createSymbolicLink(at: source, withDestinationURL: skill.url)
        } catch {
            // The move succeeded and the link did not, which would leave the
            // agent without a skill it had a moment ago. Put it back.
            try? fileManager.moveItem(at: skill.url, to: source)
            Log.usage.info("store: could not link \(name, privacy: .public) back to \(source.path, privacy: .public); undone")
            throw error
        }
        Log.usage.info("store: took in \(name, privacy: .public), linked back at \(source.path, privacy: .public)")
        return skill
    }

    /// The nearest enclosing directory holding a `.git`, or `nil`.
    ///
    /// `.git` is checked as a plain path rather than as a directory: a worktree
    /// and a submodule both write a `.git` *file* pointing elsewhere, and both
    /// are just as much somebody's checkout.
    static func gitWorkingTree(containing url: URL,
                               fileManager: FileManager = .default) -> URL? {
        var directory = url.resolvingSymlinksInPath().standardizedFileURL
        while directory.path != "/" {
            if fileManager.fileExists(
                atPath: directory.appendingPathComponent(".git").path
            ) { return directory }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
        return nil
    }

    /// A checkout this folder sits *inside* — `nil` when it is the checkout
    /// itself, or is not in one at all.
    ///
    /// The distinction is the whole rule. Moving a subdirectory out of a
    /// repository breaks its connection to the remote; moving a repository
    /// takes the `.git` along with it and breaks nothing.
    static func enclosingRepository(of url: URL,
                                    fileManager: FileManager = .default) -> URL? {
        guard let repo = gitWorkingTree(containing: url, fileManager: fileManager) else {
            return nil
        }
        let folder = url.resolvingSymlinksInPath().standardizedFileURL.path
        return repo.standardizedFileURL.path == folder ? nil : repo
    }
}

/// One skill that can be put into a project — from the quiet store, from the
/// global library, or from a registered origin repository.
struct StoredSkill: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL
    let frontmatter: SkillFrontmatter
    /// Reachable from `~/.agents/skills`, so it is loaded into every session
    /// of every project whether a project asks for it or not.
    let isGlobal: Bool
    /// Its real folder is in the store. False for one that has never been
    /// taken in — still a real folder in the global root, where switching it
    /// off is what finally moves it.
    var isTakenIn: Bool = false
    /// Another root offers the same folder name and lost. Reported on the row
    /// because a link can only ever point at one of them.
    var shadowed: Bool
    var shadowedBy: [URL] = []

    var id: String { name }
    var displayName: String { frontmatter.name ?? name }
    var summary: String? { frontmatter.description }
}

enum SkillStoreError: LocalizedError {
    case insideRepository(path: String, repo: String)

    var errorDescription: String? {
        switch self {
        case .insideRepository(let path, let repo):
            return "\(path) is inside the git repository at \(repo). Moving it "
                 + "out would cut it off from `git pull`, so it is linked where "
                 + "it is instead — add that repository as an origin."
        }
    }
}
