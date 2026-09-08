import Foundation

enum UsageGrouping: String, CaseIterable, Identifiable {
    case model = "Model", agent = "Agent"
    var id: String { rawValue }
    func key(for record: TokenUsageRecord) -> String {
        self == .model ? record.model : record.agent.title
    }
}
