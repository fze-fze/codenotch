import Foundation

/// Transcript sources, independent of account quota providers and Skills support.
enum UsageAgent: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex, claudeCode, gemini, cursor, antigravity, grok

    var id: String { rawValue }
    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        case .grok: return "Grok"
        }
    }
    var supportsHistory: Bool { self != .cursor }

    /// Why the remaining agent stays unavailable, rather than being guessed at
    /// from request counts. Cursor was checked against its own local state: it
    /// writes a `tokenCount` on every chat message and leaves both halves
    /// zeroed. The non-zero token figures it does keep are context-window
    /// limits and estimates, not what was billed.
    var unavailableReason: String? {
        switch self {
        case .cursor: return "Cursor stores chat history without token counts"
        default: return nil
        }
    }

    func roots(home: URL) -> [URL] {
        let paths: [String]
        switch self {
        case .codex: paths = [".codex/sessions", ".codex/archived_sessions"]
        case .claudeCode: paths = [".claude/projects"]
        case .gemini: paths = [".gemini/tmp"]
        // Antigravity keeps one store per install: the app, the CLI, and the
        // IDE integration each have their own conversations folder.
        case .antigravity: paths = [".gemini/antigravity/conversations",
                                    ".gemini/antigravity-cli/conversations",
                                    ".gemini/antigravity-ide/conversations"]
        case .grok: paths = [".grok/sessions"]
        default: paths = []
        }
        return paths.map { home.appendingPathComponent($0) }
    }

    /// Which files under a root actually carry token accounting. Keeping this
    /// beside the roots stops the scanner from parsing an agent's caches, locks,
    /// and search indexes looking for usage that was never there.
    func matches(_ url: URL) -> Bool {
        switch self {
        case .gemini:
            return url.pathExtension == "json" && url.lastPathComponent.hasPrefix("session-")
                && url.deletingLastPathComponent().lastPathComponent == "chats"
        case .antigravity:
            return url.pathExtension == "db"
        case .grok:
            // A Grok session folder holds several JSONL files; only the update
            // stream carries accounting, and the rest are transcript and state.
            return url.lastPathComponent == "updates.jsonl"
        default:
            return url.pathExtension == "jsonl"
        }
    }
}
