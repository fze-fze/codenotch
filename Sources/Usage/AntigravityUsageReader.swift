import Foundation
import SQLite3

/// Reads Antigravity's token accounting out of its per-conversation SQLite stores.
///
/// Antigravity is not the Gemini CLI and keeps nothing resembling a transcript
/// log. Each conversation is its own database under `~/.gemini/antigravity*/
/// conversations/<uuid>.db`, and the accounting lives in `gen_metadata`: one
/// protobuf blob per model generation. The blob names the model and carries a
/// usage submessage; the timestamps live in a separate `steps` table, which each
/// generation points at by index.
///
/// The field numbers below were read off the wire, since Antigravity ships no
/// descriptors. They were confirmed two ways before being trusted: the output
/// field is exactly the sum of the two fields beside it (reasoning and answer
/// tokens), and input + cached tracks Antigravity's own context-used counter
/// across a conversation, offset by a constant the client adds for its own
/// prompt estimate.
enum AntigravityUsageReader {
    /// Field numbers in a `gen_metadata` row.
    private enum Blob {
        static let generation = 1
        /// Packed indices of the `steps` rows this generation produced.
        static let stepIndices = 2
    }
    private enum Generation {
        static let usage = 4
        static let model = 19
    }
    /// Disjoint buckets. Field 1 is constant for a whole conversation, so it is
    /// a property of the prompt rather than a per-request bucket, and counting
    /// it once per generation would inflate every conversation by a multiple of
    /// its own system prompt. It is deliberately left out.
    private enum Usage {
        static let input = 2
        static let output = 3
        static let cached = 5
    }
    /// `steps.metadata` opens with a google.protobuf.Timestamp.
    private enum Step {
        static let timestamp = 1
        static let seconds = 1
        static let nanos = 2
    }

    struct Record: Equatable {
        var index: Int
        var stepIndices: [Int]
        var model: String
        var tokens: TokenCounts
    }

    /// Guards against a mis-framed blob turning into an absurd token count.
    static func count(_ value: UInt64?) -> Int64 {
        guard let value, value < UInt64(Int64.max) / 16 else { return 0 }
        return Int64(value)
    }

    /// One usage record per generation that actually spent tokens.
    static func generations(_ blobs: [(index: Int, data: Data)]) -> [Record] {
        blobs.compactMap { blob in
            let root = ProtobufMessage(blob.data)
            guard let generation = root.message(Blob.generation) else { return nil }
            let steps = root.packedVarints(Blob.stepIndices)
                .compactMap { $0 < UInt64(Int.max) ? Int($0) : nil }
            guard let usage = generation.message(Generation.usage) else { return nil }
            let tokens = TokenCounts(input: count(usage.varint(Usage.input)),
                                     cached: count(usage.varint(Usage.cached)),
                                     output: count(usage.varint(Usage.output)))
            guard tokens.total > 0 else { return nil }
            return Record(index: blob.index, stepIndices: steps,
                          model: generation.string(Generation.model) ?? "Unknown model",
                          tokens: tokens)
        }
    }

    /// When each step happened, so a generation can be placed in time.
    static func timestamps(_ blobs: [(index: Int, data: Data)]) -> [Int: Date] {
        var out: [Int: Date] = [:]
        for blob in blobs {
            guard let stamp = ProtobufMessage(blob.data).message(Step.timestamp),
                  let seconds = stamp.varint(Step.seconds), seconds > 0,
                  seconds < UInt64(Int64.max) / 16 else { continue }
            let nanos = Double(count(stamp.varint(Step.nanos))) / 1_000_000_000
            out[blob.index] = Date(timeIntervalSince1970: Double(seconds) + nanos)
        }
        return out
    }

    /// A generation is dated by the first of its steps that carries a time. A
    /// generation none of whose steps survived stays out: an undated record
    /// cannot be placed in any period, and guessing one would put invented
    /// tokens on a real day.
    static func records(session: String, generations: [Record],
                        timestamps: [Int: Date]) -> [TokenUsageRecord] {
        generations.compactMap { generation in
            guard let date = generation.stepIndices.lazy.compactMap({ timestamps[$0] }).first
            else { return nil }
            let identity = "antigravity:\(session):\(generation.index)"
            return TokenUsageRecord(id: UsageLogParser.key(identity), agent: .antigravity,
                                    session: session, timestamp: date, model: generation.model,
                                    tokens: generation.tokens)
        }
    }

    /// Reads one conversation store. The conversation's own file name is its
    /// identity, so the same conversation seen through a second Antigravity
    /// install — or a backup of it — produces the same record IDs and merges
    /// instead of double-counting.
    static func read(url: URL) throws -> UsageLogParser.Result {
        guard let database = SQLiteStore.open(url) else {
            return UsageLogParser.Result(malformedLines: 1)
        }
        defer { sqlite3_close(database) }
        let session = UsageLogParser.key(url.deletingPathExtension().lastPathComponent)
        let generated = SQLiteStore.blobRows(in: database, sql: "select idx, data from gen_metadata")
        try Task.checkCancellation()
        let stepped = SQLiteStore.blobRows(in: database, sql: "select idx, metadata from steps")
        try Task.checkCancellation()
        return UsageLogParser.Result(records: records(session: session,
                                                      generations: generations(generated),
                                                      timestamps: timestamps(stepped)))
    }
}
