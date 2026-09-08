import Foundation

/// Zero-filled daily series: each stack layer is that group's own running total.
struct UsageSeries {
    struct Point: Identifiable {
        let group: String
        let date: Date
        let total: Int64
        var id: String { "\(group):\(date.timeIntervalSince1970)" }
    }
    struct Category: Identifiable {
        let id: String
        let tokens: Int64
        let cost: Double
        let unpriced: Int
        let count: Int
    }
    let points: [Point]
    let categories: [Category]
    let domain: [String]
    let start: Date
    let end: Date

    init(records: [TokenUsageRecord], grouping: UsageGrouping, period: UsagePeriod,
         now: Date, prices: [String: ModelTokenPrice], domain: [String], calendar: Calendar = .current) {
        self.domain = domain
        let today = calendar.startOfDay(for: now)
        start = calendar.startOfDay(for: period.seconds.map { now.addingTimeInterval(-$0) } ?? records.map(\.timestamp).min() ?? now)
        end = max(now, start.addingTimeInterval(1))
        let groups = Dictionary(grouping: records, by: { grouping.key(for: $0) })
        categories = groups.map { key, records in
            let summary = UsageSummary(records: records, prices: prices, calendar: calendar)
            return Category(id: key, tokens: summary.tokens.total, cost: summary.cost,
                            unpriced: summary.unpriced, count: summary.recordCount)
        }.sorted { $0.tokens == $1.tokens ? $0.id < $1.id : $0.tokens > $1.tokens }
        var points: [Point] = []
        for key in domain where groups[key] != nil {
            let daily = Dictionary(grouping: groups[key]!, by: { calendar.startOfDay(for: $0.timestamp) })
                .mapValues { $0.reduce(Int64(0)) { $0 + $1.tokens.total } }
            var total: Int64 = 0
            var date = start
            points.append(Point(group: key, date: start, total: 0))
            while date <= today {
                total += daily[date, default: 0]
                let next = calendar.date(byAdding: .day, value: 1, to: date)!
                points.append(Point(group: key, date: min(next, end), total: total))
                date = next
            }
        }
        self.points = points
    }
}
