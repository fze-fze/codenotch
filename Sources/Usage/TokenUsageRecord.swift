import Foundation

/// Only accounting metadata is retained; prompts and responses never enter the archive.
struct TokenUsageRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let agent: UsageAgent
    let session: String
    let timestamp: Date
    let model: String
    var tokens: TokenCounts
}
