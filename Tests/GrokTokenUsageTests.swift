import XCTest
@testable import Codenotch

/// Grok's accounting hid behind two things at once: it is written to the update
/// stream rather than the transcript, and it spells its fields in camelCase
/// where every other agent uses snake_case. These fixtures pin both.
final class GrokTokenUsageTests: XCTestCase {
    private let stamp = 1_787_562_736

    private func data(_ json: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    private func update(prompt: String, usage: [String: Any], time: Int? = nil) throws -> Data {
        try data(["method": "_x.ai/session/update", "timestamp": time ?? stamp,
                  "params": ["update": ["prompt_id": prompt, "sessionUpdate": "usage",
                                        "stop_reason": "end_turn", "usage": usage]]])
    }

    /// The shape Grok actually writes, taken from a real update stream.
    private func usage(input: Int, cachedRead: Int, output: Int, reasoning: Int,
                       model: String = "grok-4.6-build") -> [String: Any] {
        let counts: [String: Any] = ["inputTokens": input, "outputTokens": output,
            "totalTokens": input + output, "cachedReadTokens": cachedRead,
            "cacheCreationTokens": 0, "reasoningTokens": reasoning, "modelCalls": 5,
            "apiDurationMs": 113_376, "costUsdTicks": 526_689_000]
        return counts.merging(["modelUsage": [model: counts], "numTurns": 5]) { _, new in new }
    }

    func testCachedReadsAreCarvedOutOfInputAndReasoningStaysInsideOutput() throws {
        var parser = UsageLogParser.Lines(agent: .grok, session: "test")
        parser.consume(try update(prompt: "p1",
            usage: usage(input: 159_535, cachedRead: 103_680, output: 4_770, reasoning: 4_567)))

        XCTAssertEqual(parser.result.records.count, 1)
        let record = try XCTUnwrap(parser.result.records.first)
        XCTAssertEqual(record.agent, .grok)
        XCTAssertEqual(record.model, "grok-4.6-build")
        XCTAssertEqual(record.tokens.cached, 103_680)
        XCTAssertEqual(record.tokens.input, 55_855, "input is reported inclusive of cache reads")
        XCTAssertEqual(record.tokens.output, 4_770, "reasoning is already inside output")
        XCTAssertEqual(record.tokens.other, 0)
        // Total must equal what Grok reported, with nothing counted twice.
        XCTAssertEqual(record.tokens.total, 164_305)
        XCTAssertEqual(record.timestamp.timeIntervalSince1970, Double(stamp))
    }

    /// A prompt is summarised more than once while it runs and the counts are
    /// cumulative, so the repeats have to land on one record rather than stack.
    func testRepeatedSummariesForOnePromptCollapseOntoOneRecord() throws {
        var parser = UsageLogParser.Lines(agent: .grok, session: "test")
        parser.consume(try update(prompt: "p1",
            usage: usage(input: 40_000, cachedRead: 10_000, output: 500, reasoning: 100)))
        parser.consume(try update(prompt: "p1",
            usage: usage(input: 96_374, cachedRead: 56_192, output: 12_548, reasoning: 1_692)))

        let ids = Set(parser.result.records.map(\.id))
        XCTAssertEqual(ids.count, 1, "the same prompt must not become two records")
        // The archive keeps the largest reading of each bucket.
        let merged = parser.result.records.map(\.tokens).reduce(TokenCounts()) { $0.merging($1) }
        XCTAssertEqual(merged.cached, 56_192)
        XCTAssertEqual(merged.output, 12_548)
        XCTAssertEqual(merged.total, 108_922)
    }

    func testATurnSplitAcrossModelsIsAttributedToEach() throws {
        var parser = UsageLogParser.Lines(agent: .grok, session: "test")
        let counts: [String: Any] = ["inputTokens": 300, "outputTokens": 30, "totalTokens": 330,
                                     "cachedReadTokens": 100, "cacheCreationTokens": 0]
        let small: [String: Any] = ["inputTokens": 100, "outputTokens": 10, "totalTokens": 110,
                                    "cachedReadTokens": 0, "cacheCreationTokens": 0]
        parser.consume(try update(prompt: "p1", usage: counts.merging(
            ["modelUsage": ["grok-4.6": counts, "grok-4.3": small]]) { _, new in new }))

        XCTAssertEqual(parser.result.records.map(\.model), ["grok-4.3", "grok-4.6"])
        XCTAssertEqual(parser.result.records.map { $0.tokens.total }, [110, 330])
    }

    func testRowsWithoutAccountingOrATimeAreIgnored() throws {
        var parser = UsageLogParser.Lines(agent: .grok, session: "test")
        // A plain transcript update: no usage summary at all.
        parser.consume(try data(["method": "session/update", "timestamp": stamp,
            "params": ["update": ["sessionUpdate": "agent_message_chunk"]]]))
        // Accounting with no usable timestamp.
        parser.consume(try data(["method": "_x.ai/session/update",
            "params": ["update": ["prompt_id": "p", "usage": usage(
                input: 10, cachedRead: 0, output: 1, reasoning: 0)]]]))
        // Reported but empty.
        parser.consume(try update(prompt: "p2",
            usage: usage(input: 0, cachedRead: 0, output: 0, reasoning: 0)))
        XCTAssertTrue(parser.result.records.isEmpty)
        XCTAssertEqual(parser.result.malformedLines, 0)
    }

    func testEpochSecondsRejectsNonsenseAndAcceptsBothSpellings() {
        XCTAssertEqual(UsageLogParser.epochSeconds(1_787_562_736)?.timeIntervalSince1970, 1_787_562_736)
        XCTAssertEqual(UsageLogParser.epochSeconds("2026-09-08T10:00:00Z"),
                       ISO8601Stamp.date(from: "2026-09-08T10:00:00Z"))
        XCTAssertNil(UsageLogParser.epochSeconds(true), "a boolean is not a date")
        XCTAssertNil(UsageLogParser.epochSeconds(0))
        XCTAssertNil(UsageLogParser.epochSeconds(-1))
        XCTAssertNil(UsageLogParser.epochSeconds(99_999_999_999))
        XCTAssertNil(UsageLogParser.epochSeconds(nil))
    }

    func testOnlyTheUpdateStreamIsScanned() {
        let folder = URL(fileURLWithPath: "/Users/example/.grok/sessions/cwd/session-id")
        XCTAssertTrue(UsageAgent.grok.supportsHistory)
        XCTAssertTrue(UsageAgent.grok.matches(folder.appendingPathComponent("updates.jsonl")))
        XCTAssertFalse(UsageAgent.grok.matches(folder.appendingPathComponent("chat_history.jsonl")),
                       "the transcript carries no accounting and must not be parsed")
        XCTAssertFalse(UsageAgent.grok.matches(folder.appendingPathComponent("events.jsonl")))
        XCTAssertEqual(UsageAgent.grok.roots(home: URL(fileURLWithPath: "/Users/example"))
                        .map(\.lastPathComponent), ["sessions"])
    }

    /// Grok Build's own model ID is not a published one, and Grok's cost figure
    /// for it does not reproduce from `grok-4.6` rates, so it stays unpriced
    /// while its tokens still count.
    func testPublishedGrokModelsArePricedAndTheBuildModelIsNot() throws {
        XCTAssertNotNil(UsagePricing.defaults["grok-4.6"])
        XCTAssertNotNil(UsagePricing.defaults["grok-4.3"])
        XCTAssertNotNil(UsagePricing.defaults["grok-build-0.1"])
        XCTAssertNil(UsagePricing.defaults["grok-4.6-build"])
        let price = try XCTUnwrap(UsagePricing.defaults["grok-4.6"])
        XCTAssertEqual(price.cost(TokenCounts(input: 1_000_000, cached: 1_000_000,
                                              output: 1_000_000)), 8.5)
    }
}
