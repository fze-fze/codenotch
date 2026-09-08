import Foundation
import os

/// What one agent currently makes of one skill.
enum MountState: Equatable, Sendable {
    /// The agent has never run here, so there is nowhere to put anything.
    case notInstalled
    /// The agent reads the shared library directly. Nothing was written, and
    /// nothing needs to be.
    case shared
    /// A link we made, pointing at the library entry.
    case mounted
    /// The agent's directory has no entry by this name.
    case notMounted
    /// Something is already there that we did not put there — a real folder, or
    /// a link into somewhere else. Reported, never touched.
    case conflict(Conflict)

    enum Conflict: Equatable, Sendable {
        /// A real file or directory with contents of its own.
        case realItem
        /// A symlink resolving outside the library, to something that is there.
        case foreignLink(destination: String)
        /// A symlink whose target does not exist.
        ///
        /// Not the same as a foreign link, and treating it as one was wrong.
        /// A link into a folder that is gone is not somebody's arrangement, it
        /// is debris: the agent sees a broken skill, there is no content behind
        /// it to lose, and replacing it with a link to the library costs
        /// nothing and fixes something. So this one *is* actionable.
        case brokenLink(destination: String)
    }

    /// Whether the agent can see the skill right now, however that came about.
    var isReachable: Bool {
        switch self {
        case .shared, .mounted: return true
        case .notInstalled, .notMounted, .conflict: return false
        }
    }

    /// A link pointing at something that is no longer there.
    var isBrokenLink: Bool {
        if case .conflict(.brokenLink) = self { return true }
        return false
    }

    /// Whether a switch on this row would do anything.
    var isToggleable: Bool {
        switch self {
        case .mounted, .notMounted, .conflict(.brokenLink): return true
        case .notInstalled, .shared,
             .conflict(.realItem), .conflict(.foreignLink): return false
        }
    }
}

enum SkillMountError: LocalizedError {
    /// The thing at the destination is not ours to remove.
    case notOurs(path: String)
    /// Nothing to link to.
    case missingInLibrary(name: String)

    var errorDescription: String? {
        switch self {
        case .notOurs(let path):
            return "\(path) was not put there by Codenotch, so it is left alone. "
                 + "Move or delete it yourself if you want the skill here instead."
        case .missingInLibrary(let name):
            return "\(name) is not in the library."
        }
    }
}

/// Puts library skills where each agent looks, and takes them away again.
///
/// The whole design is one rule: **a mount is a symlink into the library, and
/// nothing else is ever removed.** The library holds the one real copy, so a
/// skill edited once is edited for every agent, and an agent's directory holds
/// only links — which means the worst this can do on the way out is leave a
/// folder it did not create.
///
/// That rule is also the interoperability contract with the reference
/// `skills-manager` TUI, which refuses to replace a link resolving into a
/// managed root for exactly the same reason.
struct SkillMount: Sendable {
    let home: URL
    let fileManager: FileManager

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }

    var libraryRoot: URL { SkillAgent.sharedLibrary(home: home) }
    /// The quiet store, where a managed skill's real folder now lives. A mount
    /// resolves into it rather than into the library, because the library
    /// entry is itself a link — so without this every mount we made would read
    /// back as somebody else's arrangement.
    var storeRoot: URL { home.appendingPathComponent(".codenotch/skills") }

    /// Where a link for this skill would go — the agent's own folder. For the
    /// three that read the library there is no link, so this is the path a
    /// link *would* take rather than one anything writes to.
    func destination(name: String, for agent: SkillAgent) -> URL {
        agent.ownSkillsDir(home: home).appendingPathComponent(name)
    }

    // MARK: - Reading

    func state(name: String, for agent: SkillAgent) -> MountState {
        guard agent.isInstalled(home: home, fileManager: fileManager) else {
            return .notInstalled
        }
        if agent.readsSharedLibrary { return .shared }

        let target = destination(name: name, for: agent)
        // `lstat`, not `stat`: a dangling symlink — the library entry deleted
        // out from under it — has to read as *something there*, and `stat`
        // would report the path as empty and invite us to write over it.
        guard let attributes = try? fileManager.attributesOfItem(atPath: target.path) else {
            return .notMounted
        }
        guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
            return .conflict(.realItem)
        }
        guard let resolved = linkDestination(target) else { return .notMounted }
        if isInLibrary(resolved) { return .mounted }
        // Asked of the *resolved* path, so a chain of links that ends nowhere
        // reads as broken rather than as pointing somewhere real.
        return fileManager.fileExists(atPath: resolved.path)
            ? .conflict(.foreignLink(destination: resolved.path))
            : .conflict(.brokenLink(destination: resolved.path))
    }

    func states(name: String) -> [SkillAgent: MountState] {
        var result: [SkillAgent: MountState] = [:]
        for agent in SkillAgent.allCases { result[agent] = state(name: name, for: agent) }
        return result
    }

    /// Where a link actually points, following the whole chain when it resolves
    /// and falling back to one hop when it dangles.
    func linkDestination(_ url: URL) -> URL? {
        guard let raw = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }
        let absolute = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : url.deletingLastPathComponent().appendingPathComponent(raw)
        // `resolvingSymlinksInPath` on a dangling link returns the path
        // unchanged, which is what we want: the *intent* still tells us whose
        // link it is.
        return absolute.resolvingSymlinksInPath()
    }

    /// Is this path somewhere we manage — the library, or the store?
    ///
    /// Compared on standardised paths rather than strings — `/tmp` is a symlink
    /// to `/private/tmp` on macOS, so a test's temporary home compares unequal
    /// to itself unless both sides are resolved first.
    func isInLibrary(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return [libraryRoot, storeRoot].contains { candidate in
            let root = candidate.resolvingSymlinksInPath().standardizedFileURL.path
            return path == root || path.hasPrefix(root + "/")
        }
    }

    /// Whether this path is a link we own — the check the reference TUI makes
    /// before it will touch anything.
    func isManagedMount(_ url: URL) -> Bool {
        guard let destination = linkDestination(url) else { return false }
        return isInLibrary(destination)
    }

    // MARK: - Writing

    /// Link the library's copy into the agent's own directory.
    ///
    /// Idempotent: mounting something already mounted does nothing rather than
    /// unlinking and relinking, so a "Distribute to all" over a half-distributed
    /// skill cannot lose the half that was fine.
    func mount(name: String, into agent: SkillAgent) throws {
        guard agent.isInstalled(home: home, fileManager: fileManager) else { return }
        guard !agent.readsSharedLibrary else { return }

        // The store first: the library entry is a link into it, and a link to
        // a link resolves the same but breaks the moment the middle one goes.
        let stored = storeRoot.appendingPathComponent(name)
        let source = fileManager.fileExists(atPath: stored.path)
            ? stored
            : libraryRoot.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: source.path) else {
            throw SkillMountError.missingInLibrary(name: name)
        }

        let target = destination(name: name, for: agent)
        switch state(name: name, for: agent) {
        case .mounted:
            return
        case .conflict(.realItem), .conflict(.foreignLink):
            throw SkillMountError.notOurs(path: target.path)
        case .conflict(.brokenLink(let destination)):
            // Replaced rather than refused. The folder it named is gone, so the
            // link holds nothing: the agent is looking at a broken skill, and a
            // link to the library is strictly better than a link to nothing.
            // Nothing is lost because there was nothing there.
            Log.usage.debug("replacing broken link for \(name, privacy: .public): it pointed at \(destination, privacy: .public)")
        case .notMounted, .notInstalled, .shared:
            break
        }

        // Clears both the broken foreign link above and a dangling one of our
        // own, left by a library entry deleted by hand. Either way the name is
        // occupied and `createSymbolicLink` would fail with "file exists".
        if (try? fileManager.destinationOfSymbolicLink(atPath: target.path)) != nil {
            try? fileManager.removeItem(at: target)
        }

        try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        // An absolute link. A relative one would be prettier and would survive
        // the home directory being moved, but it breaks the moment either the
        // library or the agent directory is somewhere unexpected — and the
        // reference TUI resolves both to absolute paths before comparing, so
        // absolute is also the shape it recognises as managed.
        try fileManager.createSymbolicLink(at: target, withDestinationURL: source)
        Log.usage.debug("mounted skill \(name, privacy: .public) for \(agent.rawValue, privacy: .public)")
    }

    /// Remove our link, and only our link.
    func unmount(name: String, from agent: SkillAgent) throws {
        guard !agent.readsSharedLibrary else { return }
        let target = destination(name: name, for: agent)

        switch state(name: name, for: agent) {
        case .notMounted, .notInstalled, .shared:
            return
        case .conflict:
            throw SkillMountError.notOurs(path: target.path)
        case .mounted:
            try fileManager.removeItem(at: target)
            Log.usage.debug("unmounted skill \(name, privacy: .public) from \(agent.rawValue, privacy: .public)")
        }
    }

    /// Mount into every agent that is installed and does not already read the
    /// library. Conflicts are collected rather than thrown, so one obstructed
    /// agent does not stop the others.
    @discardableResult
    func mountEverywhere(name: String) -> [SkillAgent: Error] {
        var failures: [SkillAgent: Error] = [:]
        for agent in SkillAgent.installed(home: home, fileManager: fileManager) {
            do { try mount(name: name, into: agent) } catch { failures[agent] = error }
        }
        return failures
    }

    @discardableResult
    func unmountEverywhere(name: String) -> [SkillAgent: Error] {
        var failures: [SkillAgent: Error] = [:]
        for agent in SkillAgent.allCases {
            do { try unmount(name: name, from: agent) } catch { failures[agent] = error }
        }
        return failures
    }
}
