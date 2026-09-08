import Foundation

/// A real skill folder living in one agent's own directory rather than in the
/// library — a skill that agent has and the others do not.
struct AgentSkill: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL
    /// Whose folder it was found in. One agent, not a list: the same name under
    /// two agents is two folders that may hold different text, and merging them
    /// into one row would hide that.
    let agent: SkillAgent
    let frontmatter: SkillFrontmatter
    /// True when the library already holds a different skill of this name, so
    /// promoting it would collide. Surfaced rather than discovered on failure.
    let collidesWithLibrary: Bool

    var id: String { "\(agent.rawValue)/\(name)" }

    var displayName: String { frontmatter.name ?? name }
    var summary: String? { frontmatter.description }
}

/// Finds the skills each agent keeps to itself.
///
/// The first version of this only ever looked at the library and was blind
/// because of it: `~/.codex/skills` holds fifteen real skills that belong to
/// Codex alone, and none of them were ever seen. Every agent has its own folder,
/// including the three that *also* read the library.
///
/// What is deliberately never looked at is the vendors' own bundled folders —
/// `~/.codex/skills/.system`, `~/.cursor/skills-cursor`, `~/.grok/bundled/skills`,
/// some fifty-odd skills between them. They are read-only and they are not
/// yours; there is nothing to be done to one, so listing them would be fifty
/// rows of inert text between you and your own.
struct SkillScan: Sendable {
    let home: URL
    let fileManager: FileManager

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }

    /// Every agent-local skill, in agent order then alphabetical.
    ///
    /// Symlinks are skipped whatever they point at. A link into the library is
    /// ours and already managed; a link somewhere else is someone's deliberate
    /// arrangement, and promoting the far end of it would fork a folder they
    /// expect to have one copy of.
    func agentSkills() -> [AgentSkill] {
        let library = SkillLibrary(home: home, fileManager: fileManager)
        let known = Set(library.list().map(\.name))
        let libraryRoot = library.root.standardizedFileURL.path

        var found: [AgentSkill] = []

        for agent in SkillAgent.installed(home: home, fileManager: fileManager) {
            let directory = agent.ownSkillsDir(home: home)
            // Belt and braces. No agent's own folder *is* the library today,
            // but reading the library as if it were one agent's private stash
            // would offer every global skill back as a local one.
            guard directory.standardizedFileURL.path != libraryRoot else { continue }

            // `skipsHiddenFiles` is what keeps Codex's bundled `.system` out;
            // the other two vendors' folders are not inside an own-folder at
            // all, so they are excluded by never being scanned.
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            let bundled = Set(agent.bundledSkillDirs(home: home)
                .map(\.standardizedFileURL.path))

            var forAgent: [AgentSkill] = []
            for entry in entries {
                guard !bundled.contains(entry.standardizedFileURL.path) else { continue }
                // `attributesOfItem` does not follow the link, which is the
                // point — this has to tell a link from a folder.
                let attributes = try? fileManager.attributesOfItem(atPath: entry.path)
                guard attributes?[.type] as? FileAttributeType == .typeDirectory else { continue }
                guard SkillFrontmatter.isSkill(directory: entry, fileManager: fileManager) else {
                    continue
                }

                let name = entry.lastPathComponent
                forAgent.append(AgentSkill(
                    name: name, url: entry, agent: agent,
                    frontmatter: SkillFrontmatter.read(skillDirectory: entry),
                    collidesWithLibrary: known.contains(name)
                ))
            }
            found += forAgent.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }

        return found
    }
}
