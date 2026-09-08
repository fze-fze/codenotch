import XCTest
@testable import Codenotch

final class TokenUsageTests: XCTestCase {
    private let stamp = "2026-09-08T10:00:00Z"

    private func data(_ json: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
    private func tokenEvent(input: Int, cached: Int, output: Int, time: String? = nil) throws -> Data {
        try data(["type": "event_msg", "timestamp": time ?? stamp,
            "payload": ["type": "token_count", "info": ["total_token_usage": [
                "input_tokens": input, "cached_input_tokens": cached, "output_tokens": output,
                "reasoning_output_tokens": output / 2, "total_tokens": input + output]]]])
    }
    private func claude(output: Int, longWrite: Int = 0) throws -> Data {
        try data(["type": "assistant", "timestamp": stamp, "sessionId": "fixture-session",
            "message": ["id": "fixture-message", "model": "claude-test", "usage": [
                "input_tokens": 10, "cache_read_input_tokens": 20,
                "cache_creation_input_tokens": 100, "output_tokens": output,
                "cache_creation": ["ephemeral_1h_input_tokens": longWrite]]]])
    }

    func testCodexUsesDeltasAndDoesNotAddReasoningOrRepeatQuotaEvents() throws {
        var parser = UsageLogParser.Lines(agent: .codex, session: "test")
        parser.consume(try data(["type": "turn_context", "payload": ["model": "gpt-test"]]))
        parser.consume(try tokenEvent(input: 100, cached: 20, output: 10))
        parser.consume(try tokenEvent(input: 100, cached: 20, output: 10))
        parser.consume(try tokenEvent(input: 180, cached: 50, output: 30, time: "2026-09-08T11:00:00Z"))
        XCTAssertEqual(parser.result.records.count, 2)
        let summary = UsageSummary(records: parser.result.records)
        XCTAssertEqual(summary.tokens.total, 210)
        XCTAssertEqual(summary.tokens.input, 130)
        XCTAssertEqual(summary.tokens.cached, 50)
        XCTAssertEqual(summary.tokens.output, 30)
        XCTAssertEqual(summary.models.first?.id, "gpt-test")
    }

    func testCodexModelSwitchAndCounterReset() throws {
        var parser = UsageLogParser.Lines(agent: .codex, session: "test")
        parser.consume(try data(["type": "turn_context", "payload": ["model": "first"]]))
        parser.consume(try tokenEvent(input: 100, cached: 0, output: 10))
        parser.consume(try data(["type": "turn_context", "payload": ["model": "second"]]))
        parser.consume(try tokenEvent(input: 150, cached: 0, output: 20))
        parser.consume(try tokenEvent(input: 10, cached: 0, output: 2, time: "2026-09-08T12:00:00Z"))
        XCTAssertEqual(parser.result.records.map(\.model), ["first", "second", "second"])
        XCTAssertEqual(parser.result.records.map { $0.tokens.total }, [110, 60, 12])
    }

    func testForkedCodexHistoryIsOnlyACounterBaseline() throws {
        var parser = UsageLogParser.Lines(agent: .codex, session: "test")
        parser.consume(try data(["type": "session_meta", "payload": ["id": "child",
            "forked_from_id": "parent", "timestamp": "2026-09-08T10:30:00Z"]]))
        parser.consume(try tokenEvent(input: 100, cached: 0, output: 10))
        parser.consume(try tokenEvent(input: 150, cached: 0, output: 20, time: "2026-09-08T11:00:00Z"))
        XCTAssertEqual(parser.result.records.map { $0.tokens.total }, [60])
    }

    func testClaudeCacheWritesAreDisjointAndStreamingIDsAreStable() throws {
        var parser = UsageLogParser.Lines(agent: .claudeCode, session: "test")
        parser.consume(try claude(output: 5, longWrite: 80))
        parser.consume(try claude(output: 30, longWrite: 80))
        XCTAssertEqual(parser.result.records[0].id, parser.result.records[1].id)
        let last = try XCTUnwrap(parser.result.records.last)
        XCTAssertEqual(last.tokens, TokenCounts(input: 10, cached: 20, cacheWrite: 20, cacheWriteLong: 80, output: 30))
        XCTAssertEqual(last.tokens.total, 160)
    }

    func testGeminiAddsThoughtsOnceAndKeepsUnclassifiedTokens() throws {
        let parsed = try UsageLogParser.gemini(data(["sessionId": "test", "messages": [
            ["id": "message", "type": "gemini", "timestamp": stamp, "model": "gemini-test",
             "tokens": ["input": 100, "cached": 40, "output": 20, "thoughts": 10, "total": 135]],
            ["id": "user", "type": "user", "timestamp": stamp]
        ]]), fallbackSession: "unused")
        let tokens = try XCTUnwrap(parsed.records.first?.tokens)
        XCTAssertEqual(tokens, TokenCounts(input: 60, cached: 40, output: 30, other: 5))
        XCTAssertEqual(tokens.total, 135)
        XCTAssertNil(ModelTokenPrice(input: 1).cost(tokens))
    }

    func testMalformedAccountingLineDoesNotLoseFollowingRecords() throws {
        var parser = UsageLogParser.Lines(agent: .codex, session: "test")
        parser.consume(Data("{\"token_count\": ".utf8))
        parser.consume(try tokenEvent(input: 100, cached: 0, output: 10))
        XCTAssertEqual(parser.result.malformedLines, 1)
        XCTAssertEqual(parser.result.records.count, 1)
        XCTAssertEqual(UsageLogParser.count(["n": true], "n"), 0)
        XCTAssertEqual(UsageLogParser.count(["n": -5], "n"), 0)
    }

    func testRollingTimeBoundariesAndFutureRecords() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        for period in [UsagePeriod.day, .week, .month] {
            let start = now.addingTimeInterval(-period.seconds!)
            XCTAssertTrue(period.contains(start, now: now))
            XCTAssertFalse(period.contains(start.addingTimeInterval(-0.001), now: now))
            XCTAssertTrue(period.contains(now, now: now))
            XCTAssertFalse(period.contains(now.addingTimeInterval(1), now: now))
        }
        XCTAssertTrue(UsagePeriod.all.contains(.distantPast, now: now))
        XCTAssertFalse(UsagePeriod.all.contains(.distantFuture, now: now))
    }

    func testCostUsesDisjointRatesAndUnknownPricingIsPartial() {
        let tokens = TokenCounts(input: 1_000_000, cached: 2_000_000, cacheWrite: 1_000_000,
                                 cacheWriteLong: 1_000_000, output: 1_000_000)
        let price = ModelTokenPrice(input: 3, cached: 0.3, output: 15, cacheWrite: 3.75, cacheWriteLong: 6)
        XCTAssertEqual(price.cost(tokens)!, 28.35, accuracy: 0.00001)
        let records = ["known", "unknown"].map { model in
            TokenUsageRecord(id: model, agent: .codex, session: "test", timestamp: Date(), model: model, tokens: tokens)
        }
        let summary = UsageSummary(records: records, prices: ["known": price])
        XCTAssertEqual(summary.tokens.total, 12_000_000)
        XCTAssertEqual(summary.unpriced, 1)
        XCTAssertTrue(summary.costLabel.hasSuffix("+"))
        XCTAssertEqual(UsageSummary(records: records).costLabel, "Not priced")
        XCTAssertFalse(ModelTokenPrice(input: -.infinity).isValid)
        XCTAssertFalse(ModelTokenPrice(input: -1).isValid)
    }
}
