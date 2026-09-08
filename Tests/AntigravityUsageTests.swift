import XCTest
import SQLite3
@testable import Codenotch

/// Minimal protobuf *writer*, so the fixtures below are built the same way
/// Antigravity builds the real thing rather than pasted in as opaque bytes.
private enum Wire {
    static func varint(_ value: UInt64) -> Data {
        var value = value
        var out = Data()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    static func number(_ field: Int, _ value: UInt64) -> Data {
        varint(UInt64(field) << 3) + varint(value)
    }

    static func bytes(_ field: Int, _ payload: Data) -> Data {
        varint(UInt64(field) << 3 | 2) + varint(UInt64(payload.count)) + payload
    }

    static func text(_ field: Int, _ value: String) -> Data {
        bytes(field, Data(value.utf8))
    }

    static func fixed64(_ field: Int, _ value: UInt64) -> Data {
        varint(UInt64(field) << 3 | 1) + Data(withUnsafeBytes(of: value.littleEndian) { Array($0) })
    }
}

private struct Generation {
    var response: String
    var seconds: UInt64
    var input: UInt64
    var output: UInt64
    var cacheRead: UInt64 = 0
    var cacheWrite: UInt64 = 0
    var model: String? = "gemini-3.8-flash"

    var stats: Data {
        Wire.number(2, input) + Wire.number(3, output) + Wire.number(4, cacheWrite)
            + Wire.number(5, cacheRead) + Wire.text(11, response)
    }

    /// A `steps.metadata` row: timestamp in field 1, usage in field 9, plus a
    /// field this reader has no interest in, to prove it is skipped rather than
    /// tripped over.
    var stepMetadata: Data {
        var out = Data()
        if seconds > 0 {
            out += Wire.bytes(1, Wire.number(1, seconds) + Wire.number(2, 500_000_000))
        }
        out += Wire.number(3, 2)
        out += Wire.bytes(9, stats)
        out += Wire.text(12, "unrelated payload")
        return out
    }

    /// A `gen_metadata.data` row, which wraps everything in field 1.
    var generationMetadata: Data? {
        guard let model else { return nil }
        return Wire.bytes(1, Wire.bytes(4, stats) + Wire.text(19, model))
    }
}

private func makeDatabase(at url: URL, _ generations: [Generation]) throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
          let db else { throw CocoaError(.fileWriteUnknown) }
    defer { sqlite3_close(db) }
    let schema = """
    CREATE TABLE steps (idx integer PRIMARY KEY, metadata blob);
    CREATE TABLE gen_metadata (idx integer PRIMARY KEY, data blob);
    """
    guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }

    func insert(_ sql: String, _ index: Int, _ blob: Data) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(index))
        _ = blob.withUnsafeBytes { raw in
            sqlite3_bind_blob(statement, 2, raw.baseAddress, Int32(blob.count),
                              unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw CocoaError(.fileWriteUnknown) }
    }

    for (index, generation) in generations.enumerated() {
        try insert("INSERT INTO steps VALUES (?, ?)", index, generation.stepMetadata)
    }
    var row = 0
    for generation in generations {
        guard let data = generation.generationMetadata else { continue }
        try insert("INSERT INTO gen_metadata VALUES (?, ?)", row, data)
        row += 1
    }
}

final class ProtobufMessageTests: XCTestCase {
    func testReadsNumbersTextAndNestingAndSkipsUnwantedFields() throws {
        let payload = Wire.number(1, 42) + Wire.text(2, "gemini-3.8-flash")
            + Wire.fixed64(3, 7) + Wire.bytes(4, Wire.number(1, 9))
        let message = try XCTUnwrap(ProtobufMessage(payload))
        XCTAssertEqual(message.count(1), 42)
        XCTAssertEqual(message.string(2), "gemini-3.8-flash")
        // Read past a fixed-width field it does not want, rather than stopping there.
        XCTAssertEqual(message.message(4)?.count(1), 9)
        XCTAssertNil(message.string(5))
        XCTAssertEqual(message.count(5), 0)
    }

    func testRejectsTruncatedAndOverlongInputInsteadOfGuessing() {
        // A length that runs past the end of the buffer.
        XCTAssertNil(ProtobufMessage(Wire.varint(2 << 3 | 2) + Wire.varint(99) + Data([1, 2, 3])))
        // A varint whose continuation bits never stop.
        XCTAssertNil(ProtobufMessage(Wire.varint(1 << 3) + Data(repeating: 0xFF, count: 12)))
        // Wire type 3 — a group, removed from the language and never written here.
        XCTAssertNil(ProtobufMessage(Wire.varint(1 << 3 | 3)))
        XCTAssertNotNil(ProtobufMessage(Data()))
    }

    func testLastValueWinsForARepeatedScalar() throws {
        let message = try XCTUnwrap(ProtobufMessage(Wire.number(1, 5) + Wire.number(1, 8)))
        XCTAssertEqual(message.count(1), 8)
    }
}

final class AntigravityUsageReaderTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testReadsTokensTimestampsAndModelNamesFromAConversationDatabase() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("cf6ca969.db")
        try makeDatabase(at: database, [
            Generation(response: "resp-a", seconds: 1_788_872_409, input: 18_450, output: 446),
            Generation(response: "resp-b", seconds: 1_788_872_412, input: 3_106, output: 186,
                       cacheRead: 16_274, cacheWrite: 12),
        ])

        let result = AntigravityUsageReader.read(url: database)
        XCTAssertEqual(result.malformedLines, 0)
        XCTAssertEqual(result.records.count, 2)

        let records = result.records.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(records[0].agent, .antigravity)
        XCTAssertEqual(records[0].model, "gemini-3.8-flash")
        XCTAssertEqual(records[0].tokens.input, 18_450)
        XCTAssertEqual(records[0].tokens.output, 446)
        XCTAssertEqual(records[0].timestamp.timeIntervalSince1970, 1_788_872_409.5, accuracy: 0.001)
        XCTAssertEqual(records[1].tokens.cached, 16_274)
        XCTAssertEqual(records[1].tokens.cacheWrite, 12)
        // Prompt and cache are disjoint in Antigravity's accounting, so the
        // total is their sum and not the larger of the two.
        XCTAssertEqual(records[1].tokens.total, 3_106 + 16_274 + 12 + 186)
        // Both rows are one conversation, so they share a session.
        XCTAssertEqual(records[0].session, records[1].session)
    }

    func testCountsAGenerationEvenWhenItsModelNameIsMissing() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("no-name.db")
        try makeDatabase(at: database, [
            Generation(response: "resp-a", seconds: 1_788_872_409, input: 10, output: 5, model: nil)
        ])
        let result = AntigravityUsageReader.read(url: database)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records.first?.model, "Unknown model")
        XCTAssertEqual(result.records.first?.tokens.total, 15)
    }

    func testSkipsUndatedGenerationsRatherThanDatingThemNow() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("undated.db")
        try makeDatabase(at: database, [
            Generation(response: "resp-a", seconds: 0, input: 10, output: 5),
            Generation(response: "resp-b", seconds: 1_788_872_409, input: 10, output: 5),
        ])
        let result = AntigravityUsageReader.read(url: database)
        XCTAssertEqual(result.records.map(\.model), ["gemini-3.8-flash"])
        // Reported, so the file is retried on the next refresh instead of
        // being marked as fully imported.
        XCTAssertEqual(result.malformedLines, 1)
    }

    func testAMissingDatabaseIsReportedRatherThanCountedAsEmpty() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = AntigravityUsageReader.read(url: directory.appendingPathComponent("absent.db"))
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.malformedLines, 1)
    }

    func testTheSameConversationCopiedTwiceIsCountedOnce() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let ide = home.appendingPathComponent(".gemini/antigravity/conversations")
        let cli = home.appendingPathComponent(".gemini/antigravity-cli/conversations")
        for directory in [ide, cli] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let generations = [Generation(response: "resp-a", seconds: 1_788_872_409, input: 100, output: 20)]
        try makeDatabase(at: ide.appendingPathComponent("one.db"), generations)
        try makeDatabase(at: cli.appendingPathComponent("copy-of-one.db"), generations)

        let reader = UsageHistoryReader(home: home, archiveURL: home.appendingPathComponent("ledger.json"))
        let snapshot = try await reader.scan()
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records.first?.tokens.total, 120)
        XCTAssertEqual(snapshot.files[.antigravity], 2)
    }
}

final class UsageSourceStatusTests: XCTestCase {
    func testEachReasonForZeroReadsDifferently() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        // Antigravity installed but never used; Gemini CLI not installed at all.
        let conversations = home.appendingPathComponent(".gemini/antigravity/conversations")
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)

        let reader = UsageHistoryReader(home: home, archiveURL: home.appendingPathComponent("ledger.json"))
        let snapshot = try await reader.scan()
        let sources = Dictionary(uniqueKeysWithValues: snapshot.sources.map { ($0.agent, $0) })

        let antigravity = try XCTUnwrap(sources[.antigravity])
        XCTAssertEqual(antigravity.summary, "Installed, but no conversation databases yet")
        XCTAssertEqual(antigravity.folders, ["~/.gemini/antigravity/conversations"])
        XCTAssertEqual(antigravity.missingFolders,
                       ["~/.gemini/antigravity-ide/conversations",
                        "~/.gemini/antigravity-cli/conversations"])
        XCTAssertFalse(antigravity.isProblem)

        let gemini = try XCTUnwrap(sources[.gemini])
        XCTAssertEqual(gemini.summary, "Not installed on this Mac")
        XCTAssertEqual(gemini.detail, "~/.gemini/tmp")

        let cursor = try XCTUnwrap(sources[.cursor])
        XCTAssertEqual(cursor.summary, "Not collected — no local token log is published")
        XCTAssertFalse(cursor.isProblem)
    }

    func testAFileThatYieldsNothingIsFlaggedRatherThanShownAsAbsent() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let conversations = home.appendingPathComponent(".gemini/antigravity/conversations")
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        try makeDatabase(at: conversations.appendingPathComponent("empty.db"), [])

        let reader = UsageHistoryReader(home: home, archiveURL: home.appendingPathComponent("ledger.json"))
        let snapshot = try await reader.scan()
        let antigravity = try XCTUnwrap(snapshot.sources.first { $0.agent == .antigravity })
        XCTAssertEqual(antigravity.summary, "1 file read, no token metadata inside")
        XCTAssertTrue(antigravity.isProblem)
    }

    func testRecordCountsSurviveARescanThatReparsesNothing() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let conversations = home.appendingPathComponent(".gemini/antigravity/conversations")
        try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
        try makeDatabase(at: conversations.appendingPathComponent("one.db"), [
            Generation(response: "resp-a", seconds: 1_788_872_409, input: 100, output: 20)
        ])
        let reader = UsageHistoryReader(home: home, archiveURL: home.appendingPathComponent("ledger.json"))
        _ = try await reader.scan()
        let second = try await reader.scan()
        let antigravity = try XCTUnwrap(second.sources.first { $0.agent == .antigravity })
        XCTAssertEqual(antigravity.records, 1)
        XCTAssertEqual(antigravity.summary, "1 generation from 1 file")
    }
}
