import Foundation

struct UsageSummary {
    struct ModelRow: Identifiable {
        let id: String
        let agents: String
        let tokens: TokenCounts
        let records: Int
        let cost: Double
        let unpriced: Int
    }
    struct Day: Identifiable {
        let date: Date
        let tokens: Int64
        var id: Date { date }
    }
    var tokens = TokenCounts()
    var cost: Double = 0
    var unpriced = 0
    var recordCount = 0
    var sessions = 0
    var activeDays = 0
    var models: [ModelRow] = []
    var days: [Day] = []
    var firstDate: Date?
    var cacheShare: Double {
        let input = tokens.input + tokens.cached + tokens.cacheWrite + tokens.cacheWriteLong
        return input > 0 ? Double(tokens.cached) / Double(input) : 0
    }
    var costLabel: String {
        if recordCount > 0 && unpriced == recordCount { return "Not priced" }
        return cost.formatted(.currency(code: "USD")) + (unpriced > 0 ? "+" : "")
    }

    init(records: [TokenUsageRecord] = [], prices: [String: ModelTokenPrice] = [:],
         calendar: Calendar = .current) {
        recordCount = records.count
        sessions = Set(records.map { "\($0.agent.rawValue):\($0.session)" }).count
        firstDate = records.map(\.timestamp).min()
        var grouped: [String: [TokenUsageRecord]] = [:]
        var daily: [Date: Int64] = [:]
        for record in records {
            tokens = tokens + record.tokens
            if let value = prices[record.model]?.cost(record.tokens) { cost += value } else { unpriced += 1 }
            grouped[record.model, default: []].append(record)
            daily[calendar.startOfDay(for: record.timestamp), default: 0] += record.tokens.total
        }
        activeDays = daily.count
        days = daily.map { Day(date: $0.key, tokens: $0.value) }.sorted { $0.date < $1.date }
        models = grouped.map { model, records in
            var tokens = TokenCounts()
            var cost = 0.0
            var unpriced = 0
            for record in records {
                tokens = tokens + record.tokens
                if let value = prices[model]?.cost(record.tokens) { cost += value } else { unpriced += 1 }
            }
            return ModelRow(id: model, agents: Set(records.map { $0.agent.title }).sorted().joined(separator: ", "),
                            tokens: tokens, records: records.count, cost: cost, unpriced: unpriced)
        }.sorted { $0.tokens.total == $1.tokens.total ? $0.id < $1.id : $0.tokens.total > $1.tokens.total }
    }
}
