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
    var supportsHistory: Bool { [.codex, .claudeCode, .gemini, .antigravity].contains(self) }

    /// Why the two remaining agents stay unavailable, rather than being guessed
    /// at from request counts. Both were checked against their own local state:
    /// Cursor writes a `tokenCount` on every chat message and leaves it zeroed,
    /// and Grok records no token counts at all — its usage telemetry is an
    /// opt-in OpenTelemetry export to a collector the user configures, so there
    /// is nothing on this Mac to read.
    var unavailableReason: String? {
        switch self {
        case .cursor: return "Cursor stores chat history without token counts"
        case .grok: return "Grok reports usage only to an external telemetry collector"
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
        default:
            return url.pathExtension == "jsonl"
        }
    }
}
