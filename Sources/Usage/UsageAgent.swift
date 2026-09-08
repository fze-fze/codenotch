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
    var supportsHistory: Bool { [.codex, .claudeCode, .gemini].contains(self) }
    func roots(home: URL) -> [URL] {
        let paths: [String]
        switch self {
        case .codex: paths = [".codex/sessions", ".codex/archived_sessions"]
        case .claudeCode: paths = [".claude/projects"]
        case .gemini: paths = [".gemini/tmp"]
        default: paths = []
        }
        return paths.map { home.appendingPathComponent($0) }
    }
}
