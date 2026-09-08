import XCTest
import SQLite3
@testable import Codenotch

/// Antigravity's stores are protobuf inside SQLite, so these fixtures encode the
/// wire format by hand and write a real database: a test that stopped at the
/// decoded struct would not prove the blob ever came back out of SQLite intact.
final class AntigravityUsageTests: XCTestCase {
    // MARK: - Wire format fixtures

    private func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }
    private func field(_ number: Int, varint value: UInt64) -> [UInt8] {
        self.varint(UInt64(number) << 3) + self.varint(value)
    }
    private func field(_ number: Int, bytes: [UInt8]) -> [UInt8] {
        varint(UInt64(number) << 3 | 2) + varint(UInt64(bytes.count)) + bytes
    }

    private func usage(input: Int, cached: Int, output: Int) -> [UInt8] {
        // Field 1 is the conversation-constant the reader deliberately ignores.
        field(1, varint: 1318) + field(2, varint: UInt64(input))
            + field(3, varint: UInt64(output)) + field(5, varint: UInt64(cached))
            + field(6, varint: 24)
    }
    private func generation(input: Int, cached: Int, output: Int, model: String?,
                            steps: [Int]) -> Data {
        var record = field(4, bytes: usage(input: input, cached: cached, output: output))
        if let model { record += field(19, bytes: Array(model.utf8)) }
        let packed = steps.flatMap { varint(UInt64($0)) }
        return Data(field(1, bytes: record) + field(2, bytes: packed))
    }
    private func step(seconds: UInt64, nanos: UInt64 = 0) -> Data {
        Data(field(1, bytes: field(1, varint: seconds) + field(2, varint: nanos)))
    }

    /// Writes a store with Antigravity's schema, so the read path under test is
    /// the same one it takes against the real app.
    private func store(named name: String, generations: [(Int, Data)],
                       steps: [(Int, Data)]) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("antigravity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("\(name).db")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(file.path, &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        for sql in ["create table gen_metadata (idx integer primary key, data blob, size integer default 0)",
                    "create table steps (idx integer primary key, metadata blob)"] {
            XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        }
        for (table, column, rows) in [("gen_metadata", "data", generations), ("steps", "metadata", steps)] {
            for (index, blob) in rows {
                var statement: OpaquePointer?
                let sql = "insert into \(table) (idx, \(column)) values (?, ?)"
                XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
                sqlite3_bind_int64(statement, 1, Int64(index))
                // SQLITE_TRANSIENT: SQLite must copy the bytes, since the
                // pointer is only valid inside withUnsafeBytes.
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                blob.withUnsafeBytes { raw in
                    _ = sqlite3_bind_blob(statement, 2, raw.baseAddress, Int32(blob.count), transient)
                }
                XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
                sqlite3_finalize(statement)
            }
        }
        return file
    }

    // MARK: - Protobuf reader

    func testProtobufReaderAddressesNestedAndPackedFields() {
        let message = ProtobufMessage(generation(input: 10, cached: 20, output: 30,
                                                 model: "gemini-3.8-flash", steps: [5, 6, 300]))
        XCTAssertEqual(message.message(path: [1, 4])?.varint(2), 10)
        XCTAssertEqual(message.message(1)?.string(19), "gemini-3.8-flash")
        XCTAssertEqual(message.packedVarints(2), [5, 6, 300])
    }

    func testTruncatedAndUnknownWireTypesKeepWhatWasAlreadyRead() {
        let complete = Array(generation(input: 10, cached: 20, output: 30,
                                        model: "gemini-3.8-flash", steps: [1]))
        // Cuts the last field's payload, leaving the generation ahead of it whole.
        let truncated = ProtobufMessage(Array(complete.dropLast(1)))
        XCTAssertEqual(truncated.message(path: [1, 4])?.varint(2), 10,
                       "a cut-off tail must not discard the fields before it")
        XCTAssertEqual(truncated.packedVarints(2), [])
        // Cutting into a field's own declared length drops that field entirely.
        XCTAssertNil(ProtobufMessage(Array(complete.dropLast(6))).message(1))
        // Wire type 3 was removed from proto3; it ends the scan rather than looping.
        let unknown = ProtobufMessage(field(1, varint: 7) + [UInt8(2 << 3 | 3)] + [0xFF])
        XCTAssertEqual(unknown.varint(1), 7)
        XCTAssertNil(unknown.varint(2))
        XCTAssertEqual(ProtobufMessage(Data()).fields.count, 0)
    }

    func testAbsurdCountsAreRejectedRatherThanTrusted() {
        XCTAssertEqual(AntigravityUsageReader.count(UInt64.max), 0)
        XCTAssertEqual(AntigravityUsageReader.count(nil), 0)
        XCTAssertEqual(AntigravityUsageReader.count(42), 42)
    }

    // MARK: - Accounting

    func testGenerationsUseDisjointBucketsAndIgnoreTheConversationConstant() throws {
        let file = try store(named: "conversation", generations: [
            (0, generation(input: 10_258, cached: 8_138, output: 566,
                           model: "gemini-3.8-flash", steps: [1, 2]))
        ], steps: [(1, step(seconds: 1_788_600_685, nanos: 500_000_000))])

        let result = try UsageLogParser.read(url: file, agent: .antigravity)
        XCTAssertEqual(result.records.count, 1)
        let record = try XCTUnwrap(result.records.first)
        XCTAssertEqual(record.agent, .antigravity)
        XCTAssertEqual(record.model, "gemini-3.8-flash")
        XCTAssertEqual(record.tokens.input, 10_258)
        XCTAssertEqual(record.tokens.cached, 8_138)
        XCTAssertEqual(record.tokens.output, 566)
        // 1318 and 24 are conversation constants, not buckets: excluded from the total.
        XCTAssertEqual(record.tokens.total, 18_962)
        XCTAssertEqual(record.timestamp.timeIntervalSince1970, 1_788_600_685.5, accuracy: 0.001)
    }

    func testFailedAndUndatedGenerationsAreLeftOutRatherThanEstimated() throws {
        let file = try store(named: "conversation", generations: [
            // A request that errored before the model answered: no usage submessage.
            (0, Data(field(1, bytes: field(19, bytes: Array("gemini-3.8-flash".utf8))))),
            (1, generation(input: 0, cached: 0, output: 0, model: "gemini-3.8-flash", steps: [1])),
            // Real tokens, but every step it points at is gone from the store.
            (2, generation(input: 500, cached: 0, output: 20, model: "gemini-3.8-flash", steps: [99])),
            (3, generation(input: 100, cached: 0, output: 5, model: nil, steps: [1]))
        ], steps: [(1, step(seconds: 1_788_600_685))])

        let result = try UsageLogParser.read(url: file, agent: .antigravity)
        XCTAssertEqual(result.records.map { $0.tokens.total }, [105])
        XCTAssertEqual(result.records.first?.model, "Unknown model")
    }

    func testTheSameConversationSeenTwiceMergesInsteadOfDoubleCounting() throws {
        let blob = generation(input: 400, cached: 100, output: 40,
                              model: "gemini-3.8-flash", steps: [1])
        let steps = [(1, step(seconds: 1_788_600_685))]
        let first = try store(named: "shared-id", generations: [(0, blob)], steps: steps)
        let second = try store(named: "shared-id", generations: [(0, blob)], steps: steps)

        let left = try UsageLogParser.read(url: first, agent: .antigravity).records
        let right = try UsageLogParser.read(url: second, agent: .antigravity).records
        XCTAssertEqual(left.first?.id, right.first?.id,
                       "a conversation copied into a second install must not be counted twice")
        // The archive keys records by ID, so a shared ID collapses to one row.
        let archived = Dictionary((left + right).map { ($0.id, $0) }) { first, _ in first }
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(UsageSummary(records: Array(archived.values)).tokens.total, 540)
    }

    func testAnUnreadableStoreIsReportedInsteadOfSilentlyEmpty() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString).db")
        XCTAssertEqual(try UsageLogParser.read(url: url, agent: .antigravity).malformedLines, 1)
    }

    // MARK: - Discovery

    func testOnlyTokenBearingFilesAreScanned() {
        let home = URL(fileURLWithPath: "/Users/example")
        let roots = UsageAgent.antigravity.roots(home: home).map(\.lastPathComponent)
        XCTAssertEqual(roots, ["conversations", "conversations", "conversations"])
        XCTAssertTrue(UsageAgent.antigravity.matches(home.appendingPathComponent("a.db")))
        XCTAssertFalse(UsageAgent.antigravity.matches(home.appendingPathComponent("a.db-wal")))
        XCTAssertFalse(UsageAgent.antigravity.matches(home.appendingPathComponent("a.jsonl")))
        XCTAssertTrue(UsageAgent.codex.matches(home.appendingPathComponent("a.jsonl")))
        XCTAssertTrue(UsageAgent.antigravity.supportsHistory)
    }

    func testAgentsWithoutLocalTokenCountsSayWhyRatherThanShowingZero() {
        XCTAssertFalse(UsageAgent.cursor.supportsHistory)
        XCTAssertFalse(UsageAgent.grok.supportsHistory)
        XCTAssertNotNil(UsageAgent.cursor.unavailableReason)
        XCTAssertNotNil(UsageAgent.grok.unavailableReason)
        XCTAssertNil(UsageAgent.antigravity.unavailableReason)
        XCTAssertTrue(UsageAgent.cursor.roots(home: URL(fileURLWithPath: "/Users/example")).isEmpty)
    }
}
