import Foundation

struct UsageActivity {
    struct Cell: Identifiable {
        let date: Date
        let tokens: Int64
        let isInRange: Bool
        var id: Date { date }
    }
    let cells: [Cell]
    let tokens: Int64
    let peak: Int64
    let bestDay: Date?
    let bestMonth: Date?
    let longestStreak: Int
    let currentStreak: Int

    init(days: [UsageSummary.Day], now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -364, to: today)!
        var calendar = calendar
        calendar.firstWeekday = 1
        let gridStart = calendar.dateInterval(of: .weekOfYear, for: start)!.start
        let gridEnd = calendar.dateInterval(of: .weekOfYear, for: today)!.end
        let counts = Dictionary(days.filter { $0.date >= start && $0.date <= today }.map { ($0.date, $0.tokens) }, uniquingKeysWith: +)
        var cells: [Cell] = []
        var date = gridStart
        var months: [Date: Int64] = [:]
        var run = 0
        var longest = 0
        while date < gridEnd {
            let count = counts[date, default: 0]
            cells.append(Cell(date: date, tokens: count, isInRange: date >= start && date <= today))
            if count > 0 {
                run += 1
                longest = max(longest, run)
                let month = calendar.dateInterval(of: .month, for: date)!.start
                months[month, default: 0] += count
            } else { run = 0 }
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        self.cells = cells
        tokens = counts.values.reduce(0, +)
        peak = counts.values.max() ?? 0
        bestDay = counts.filter { $0.value > 0 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first?.key
        bestMonth = months.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first?.key
        longestStreak = longest
        var cursor = counts[today, default: 0] > 0 ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        var current = 0
        while counts[cursor, default: 0] > 0 {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        currentStreak = current
    }
}
