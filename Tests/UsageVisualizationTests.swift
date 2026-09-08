import XCTest
@testable import Codenotch

final class UsageVisualizationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ text: String) -> Date { ISO8601Stamp.date(from: text)! }

    func testHeatmapIncludes365DaysAndExcludesFutureAndOldHistory() {
        let today = date("2026-09-08T00:00:00Z")
        let days = [-365, -364, 0, 1].map {
            UsageSummary.Day(date: calendar.date(byAdding: .day, value: $0, to: today)!, tokens: 10)
        }
        let activity = UsageActivity(days: days, now: today, calendar: calendar)
        XCTAssertEqual(activity.tokens, 20)
        XCTAssertEqual(activity.cells.filter(\.isInRange).count, 365)
        XCTAssertEqual(activity.cells.count % 7, 0)
        XCTAssertEqual(calendar.component(.weekday, from: activity.cells[0].date), 1)
    }

    func testStreaksUseCalendarDaysAndAllowYesterday() {
        let now = date("2026-09-08T10:00:00Z")
        let days = ["2026-08-30", "2026-08-31", "2026-09-01", "2026-09-06", "2026-09-07"].map {
            UsageSummary.Day(date: date($0 + "T00:00:00Z"), tokens: 100)
        }
        let activity = UsageActivity(days: days, now: now, calendar: calendar)
        XCTAssertEqual(activity.longestStreak, 3)
        XCTAssertEqual(activity.currentStreak, 2)
        XCTAssertEqual(activity.bestMonth, date("2026-09-01T00:00:00Z"))
        let stale = UsageActivity(days: days, now: date("2026-09-09T10:00:00Z"), calendar: calendar)
        XCTAssertEqual(stale.currentStreak, 0)
        XCTAssertNil(UsageActivity(days: [], now: now).bestDay)
    }

    func testGroupingConservesTokensAndCumulativeSeriesFillsMissingDays() {
        let records = [
            TokenUsageRecord(id: "a", agent: .codex, session: "a", timestamp: date("2026-09-06T12:00:00Z"), model: "shared", tokens: .init(input: 10)),
            TokenUsageRecord(id: "b", agent: .claudeCode, session: "b", timestamp: date("2026-09-08T09:00:00Z"), model: "shared", tokens: .init(input: 20)),
            TokenUsageRecord(id: "c", agent: .codex, session: "c", timestamp: date("2026-09-08T10:00:00Z"), model: "second", tokens: .init(input: 30))
        ]
        let now = date("2026-09-08T12:00:00Z")
        for grouping in UsageGrouping.allCases {
            let domain = Set(records.map { grouping.key(for: $0) }).sorted()
            let series = UsageSeries(records: records, grouping: grouping, period: .all, now: now,
                                     prices: [:], domain: domain, calendar: calendar)
            XCTAssertEqual(series.categories.reduce(0) { $0 + $1.tokens }, 60)
            XCTAssertEqual(series.points.filter { $0.date == series.end }.reduce(0) { $0 + $1.total }, 60)
            XCTAssertEqual(series.end, now)
            for category in series.categories {
                let points = series.points.filter { $0.group == category.id }
                XCTAssertEqual(points.count, 4)
                XCTAssertEqual(points[1].total, points[2].total, "September 7 has no new usage")
                XCTAssertEqual(points.last?.total, category.tokens)
            }
            if grouping == .agent {
                XCTAssertEqual(series.categories.first?.id, "Codex")
                XCTAssertEqual(series.categories.first?.tokens, 40)
            } else {
                XCTAssertEqual(series.categories.first?.tokens, 30)
            }
        }
    }
}
