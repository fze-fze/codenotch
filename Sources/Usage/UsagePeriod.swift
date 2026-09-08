import Foundation

enum UsagePeriod: String, CaseIterable, Identifiable, Sendable {
    case day = "1d", week = "7d", month = "30d", all = "All"
    var id: String { rawValue }
    var seconds: TimeInterval? {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .all: return nil
        }
    }
    func contains(_ date: Date, now: Date) -> Bool {
        date <= now && (seconds.map { date >= now.addingTimeInterval(-$0) } ?? true)
    }
}
