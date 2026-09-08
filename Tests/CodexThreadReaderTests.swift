import XCTest
@testable import Codenotch

/// Archiving a Codex thread deletes its rollout log, so everything the detailed
/// reader knows about that thread goes with it. These pin the recovery, and in
/// particular the two ways it could go wrong: counting a thread twice, or
/// preferring the coarse total over a log that is still there.
final class CodexThreadReaderTests: XCTestCase {
    /// Columns in the order `CodexThreadReader` selects them.
    private func row(id: String, tokens: String, model: String = "gpt-5.6-sol",
                     updatedMs: String = "1787385123389", updatedSeconds: String = "1787385123",
                     rollout: String = "/nonexistent/rollout.jsonl") -> [String] {
        [id, tokens, model, updatedMs, updatedSeconds, rollout]
    }

    private func records(_ rows: [[String]], imported: Set<String> = [],
                         present: Set<String> = []) -> [TokenUsageRecord] {
        CodexThreadReader.records(rows: rows, importedSessions: imported,
                                  fileExists: { present.contains($0) })
    }

    func testAnArchivedThreadIsRecoveredAsAnUnclassifiedTotal() throws {
        let out = records([row(id: "thread-a", tokens: "109296")])
        XCTAssertEqual(out.count, 1)
        let record = try XCTUnwrap(out.first)
        XCTAssertEqual(record.agent, .codex)
        XCTAssertEqual(record.model, "gpt-5.6-sol")
        XCTAssertEqual(record.tokens.total, 109_296)
        // The state database reports one number with no split, and that is
        // exactly what the unclassified bucket is for.
        XCTAssertEqual(record.tokens.other, 109_296)
        XCTAssertEqual(record.tokens.input, 0)
        XCTAssertEqual(record.tokens.output, 0)
        XCTAssertEqual(record.timestamp.timeIntervalSince1970, 1_787_385_123.389, accuracy: 0.001)
    }

    /// A coarse total carries no cost, because it cannot be split across the
    /// buckets a rate is defined over. Its tokens still count.
    func testARecoveredTotalIsCountedButNotPriced() {
        let summary = UsageSummary(records: records([row(id: "a", tokens: "500000")]),
                                   prices: UsagePricing.defaults)
        XCTAssertEqual(summary.tokens.total, 500_000)
        XCTAssertEqual(summary.costLabel, "Not priced")
        XCTAssertEqual(summary.unpriced, 1)
    }

    /// The log is the better source: it has the bucket split, per-turn times,
    /// and the segments before each context compaction.
    func testAThreadWhoseLogStillExistsIsLeftToTheDetailedReader() {
        let live = "/Users/example/.codex/sessions/2026/09/rollout-live.jsonl"
        XCTAssertTrue(records([row(id: "a", tokens: "500", rollout: live)],
                              present: [live]).isEmpty)
    }

    /// The case that would silently inflate every total: a thread archived after
    /// Codenotch had already imported its log. The detail stays; the coarse
    /// total must not be added on top of it.
    func testAThreadAlreadyImportedIsNotCountedASecondTime() {
        let thread = "thread-a"
        let session = UsageLogParser.key(thread)
        XCTAssertTrue(records([row(id: thread, tokens: "500000")], imported: [session]).isEmpty)
        // And its session id matches the one the log reader derives, so the
        // two sources agree on what a session is rather than inventing extras.
        let recovered = records([row(id: thread, tokens: "500000")])
        XCTAssertEqual(recovered.first?.session, session)
    }

    func testThreadsWithNothingToReportAreSkipped() {
        XCTAssertTrue(records([
            row(id: "zero", tokens: "0"),
            row(id: "negative", tokens: "-5"),
            row(id: "blank", tokens: ""),
            row(id: "", tokens: "100"),
        ]).isEmpty)
        XCTAssertTrue(records([["too", "few", "columns"]]).isEmpty)
    }

    func testAMissingModelStaysUnknownRatherThanBlank() {
        XCTAssertEqual(records([row(id: "a", tokens: "10", model: "")]).first?.model, "Unknown model")
    }

    /// Older rows predate the millisecond column and carry only whole seconds.
    func testTimestampsFallBackFromMillisecondsToSeconds() throws {
        let fromMilliseconds = try XCTUnwrap(
            CodexThreadReader.timestamp(milliseconds: "1787385123389", seconds: "0"))
        XCTAssertEqual(fromMilliseconds.timeIntervalSince1970, 1_787_385_123.389, accuracy: 0.001)
        XCTAssertEqual(CodexThreadReader.timestamp(milliseconds: "", seconds: "1787385123")?
                        .timeIntervalSince1970, 1_787_385_123)
        XCTAssertEqual(CodexThreadReader.timestamp(milliseconds: "0", seconds: "1787385123")?
                        .timeIntervalSince1970, 1_787_385_123)
        XCTAssertNil(CodexThreadReader.timestamp(milliseconds: "0", seconds: "0"))
        XCTAssertNil(CodexThreadReader.timestamp(milliseconds: "-1", seconds: "-1"))
        XCTAssertNil(CodexThreadReader.timestamp(milliseconds: "nonsense", seconds: ""))
        // A seconds value pasted into the milliseconds column is still in range
        // for milliseconds, so the row that has no usable time is refused.
        XCTAssertNil(records([row(id: "a", tokens: "10", updatedMs: "", updatedSeconds: "")]).first)
    }

    func testTheStateDatabaseIsFoundByNameRatherThanHardcoded() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-home-\(UUID().uuidString)", isDirectory: true)
        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codex.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        for name in ["state_5.sqlite", "state_6.sqlite", "logs_2.sqlite", "state_5.sqlite-wal"] {
            try Data().write(to: codex.appendingPathComponent(name))
        }
        XCTAssertEqual(CodexThreadReader.stateFiles(home: home).map(\.lastPathComponent),
                       ["state_5.sqlite", "state_6.sqlite"])
    }

    func testNoCodexHomeIsQuietRatherThanAnError() {
        let absent = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        XCTAssertTrue(CodexThreadReader.stateFiles(home: absent).isEmpty)
    }
}
