import Foundation

/// A coding agent that reads skills off this Mac.
///
/// A "skill" is a folder holding a `SKILL.md` — YAML frontmatter naming and
/// describing it, then instructions. The format is the same for all five, which
/// is what makes one library distributable to all of them; where they differ is
/// *which directory* they look in.
///
/// Deliberately five and not the reference project's forty. Every agent here is
/// one this app already reads usage for, so the two halves of Codenotch know
/// about the same set of tools; an agent nobody on this machine runs is a row
/// that can only ever say "Not installed".
enum SkillAgent: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case cursor
    case grok
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode:  return "Claude Code"
        case .codex:       return "Codex"
        case .cursor:      return "Cursor"
        case .grok:        return "Grok"
        case .antigravity: return "Antigravity"
        }
    }

    /// The mark on the notch, reused here so one tool looks the same in both
    /// halves of the app.
    var glyph: ProviderGlyph {
        switch self {
        case .claudeCode:  return .claude
        case .codex:       return .openai
        case .cursor:      return .cursor
        case .grok:        return .grok
        case .antigravity: return .antigravity
        }
    }

    // MARK: - Where it lives

    /// The shared root the ecosystem settled on. Codex, Cursor and Grok read it
    /// natively, so it is both the library and — for those three — the delivery.
    static func sharedLibrary(home: URL) -> URL {
        home.appendingPathComponent(".agents/skills")
    }

    /// Directories whose existence means this agent has been run here.
    ///
    /// Several rather than one because two of them have more than one home:
    /// Antigravity writes under `~/.gemini` on a fresh install but keeps
    /// `~/.antigravity` from older ones, and either is proof enough.
    func detectPaths(home: URL) -> [URL] {
        switch self {
        case .claudeCode:  return [home.appendingPathComponent(".claude")]
        case .codex:       return [home.appendingPathComponent(".codex")]
        case .cursor:      return [home.appendingPathComponent(".cursor")]
        case .grok:        return [home.appendingPathComponent(".grok")]
        case .antigravity: return [home.appendingPathComponent(".gemini"),
                                   home.appendingPathComponent(".antigravity")]
        }
    }

    /// Whether this agent reads `~/.agents/skills` itself.
    ///
    /// The three that do need nothing from us at all: putting a skill in the
    /// library *is* installing it for them. Saying so on the row matters more
    /// than it sounds — the alternative is a toggle that appears to do something
    /// and in fact does nothing, or worse, a second copy that then drifts.
    var readsSharedLibrary: Bool {
        switch self {
        case .codex, .cursor, .grok: return true
        case .claudeCode, .antigravity: return false
        }
    }

    /// The agent's **own** skills folder — the one it keeps its private skills
    /// in, as opposed to the shared library.
    ///
    /// Every agent has one, including the three that also read the library.
    /// That is not a redundancy, and assuming it was is what made the first
    /// version of this feature blind: `~/.codex/skills` holds fifteen real
    /// skills that belong to Codex alone, and a scan that only ever looked at
    /// the library never saw one of them.
    func ownSkillsDir(home: URL) -> URL {
        switch self {
        case .claudeCode:  return home.appendingPathComponent(".claude/skills")
        case .codex:       return home.appendingPathComponent(".codex/skills")
        case .cursor:      return home.appendingPathComponent(".cursor/skills")
        case .grok:        return home.appendingPathComponent(".grok/skills")
        // `~/.gemini/config/skills` and not `~/.gemini/antigravity/skills`:
        // the first is the one all three Antigravity surfaces read (IDE, CLI
        // and the agent itself), and the second has a known bug where
        // symlinked skills are not discovered at all.
        case .antigravity: return home.appendingPathComponent(".gemini/config/skills")
        }
    }

    /// Where a link has to go for this agent to see a library skill — `nil`
    /// when it reads the library already and no link is needed.
    ///
    /// Nothing is written into the own-folder of an agent that reads the
    /// library: a skill mounted at `~/.codex/skills` *as well* would be the
    /// same skill twice, and Codex would have to pick one.
    func mountDir(home: URL) -> URL? {
        readsSharedLibrary ? nil : ownSkillsDir(home: home)
    }

    /// Folders the vendor ships its own skills in.
    ///
    /// Listed so they can be **excluded**. They are read-only, they are not
    /// yours, and there is nothing to be done to one — so they are never
    /// scanned, never offered, and never shown.
    func bundledSkillDirs(home: URL) -> [URL] {
        switch self {
        // Hidden, and marked by `.codex-system-skills.marker`.
        case .codex:  return [home.appendingPathComponent(".codex/skills/.system")]
        case .cursor: return [home.appendingPathComponent(".cursor/skills-cursor")]
        case .grok:   return [home.appendingPathComponent(".grok/bundled/skills")]
        case .claudeCode, .antigravity: return []
        }
    }

    /// Has this agent been run on this Mac?
    func isInstalled(home: URL, fileManager: FileManager = .default) -> Bool {
        detectPaths(home: home).contains { fileManager.fileExists(atPath: $0.path) }
    }

    static func installed(home: URL, fileManager: FileManager = .default) -> [SkillAgent] {
        allCases.filter { $0.isInstalled(home: home, fileManager: fileManager) }
    }
}
