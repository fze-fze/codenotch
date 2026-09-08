import Foundation

/// Transcript sources, independent of account quota providers and Skills support.
enum UsageAgent: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex, claudeCode, gemini, cursor, antigravity, grok

    var id: String { rawValue }
    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .gemini: return "Gemini CLI"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        case .grok: return "Grok"
        }
    }
    var supportsHistory: Bool { [.codex, .claudeCode, .gemini, .antigravity].contains(self) }

    /// What this agent's own local history is written as, in the user's words —
    /// shown next to the folder when nothing was found there, because "no logs"
    /// is only actionable once you know what was being looked for.
    var historyDescription: String {
        switch self {
        case .codex: return "session and archive transcripts"
        case .claudeCode: return "project transcripts, including subagents"
        case .gemini: return "saved chat sessions"
        case .antigravity: return "conversation databases"
        case .cursor, .grok: return "no local token log is published"
        }
    }

    func roots(home: URL) -> [URL] {
        let paths: [String]
        switch self {
        case .codex: paths = [".codex/sessions", ".codex/archived_sessions"]
        case .claudeCode: paths = [".claude/projects"]
        case .gemini: paths = [".gemini/tmp"]
        // The IDE, the CLI and the older single-install layout each keep their
        // own copy of the same schema. `antigravity-backup` is deliberately
        // absent: it is a snapshot of one of these taken at upgrade time, and a
        // generation there whose response id did not survive the copy would be
        // counted a second time.
        case .antigravity:
            paths = [".gemini/antigravity/conversations",
                     ".gemini/antigravity-ide/conversations",
                     ".gemini/antigravity-cli/conversations"]
        case .cursor, .grok: paths = []
        }
        return paths.map { home.appendingPathComponent($0) }
    }

    /// Whether a file found under `roots` is one of this agent's logs.
    func isHistoryFile(_ url: URL) -> Bool {
        switch self {
        case .gemini:
            return url.pathExtension == "json"
                && url.lastPathComponent.hasPrefix("session-")
                && url.deletingLastPathComponent().lastPathComponent == "chats"
        case .antigravity:
            return url.pathExtension == "db"
        default:
            return url.pathExtension == "jsonl"
        }
    }
}
