import Foundation
import SQLite3

/// Token accounting for Antigravity, read out of its own conversation
/// databases.
///
/// **Why this exists.** Google publishes no usage figure for Antigravity —
/// `loadCodeAssist` answers with tiers and no numbers — so this app long
/// assumed there was nothing to count and reported Antigravity as having no
/// local token history at all. That assumption was wrong. Every conversation
/// database under `~/.gemini/antigravity*/conversations` carries a
/// `ModelUsageStats` message per generation: prompt tokens, completion tokens,
/// the thinking/response split of the completion, and how much of the prompt
/// was served from cache. It is exact, it is the provider's own accounting,
/// and it was simply never read.
///
/// **Where each fact comes from.** Two tables, joined on the response id the
/// server assigns:
///
/// - `steps.metadata` holds the usage *and* the timestamp. This is the table
///   that matters: the counts without a time are a total with nowhere to put
///   it on a chart.
/// - `gen_metadata.data` holds the model *name* as a string. The steps table
///   names the model only by an internal enum number, which changes meaning
///   between releases; the string does not.
///
/// A generation missing from `gen_metadata` is still counted, under an unknown
/// model. Losing the label is worth much less than losing the tokens.
enum AntigravityUsageReader {
    /// `ModelUsageStats`, by field number. Read out of the protobuf descriptor
    /// embedded in Antigravity's own `language_server` binary rather than
    /// inferred from the values, so these are the program's definitions.
    private enum Stats {
        static let inputTokens = 2
        static let outputTokens = 3
        static let cacheWriteTokens = 4
        static let cacheReadTokens = 5
        static let responseID = 11
    }
    /// The step record that wraps a `ModelUsageStats`.
    private enum Step {
        static let startedAt = 1
        /// Fallbacks, in the order the language server fills them in.
        static let completedAt = [6, 7, 8, 32]
        static let usage = 9
    }
    /// The generation record in `gen_metadata`, which is wrapped in one
    /// outer field before anything useful begins.
    private enum Generation {
        static let envelope = 1
        static let usage = 4
        static let modelName = 19
    }
    /// `google.protobuf.Timestamp`.
    private enum Stamp {
        static let seconds = 1
        static let nanos = 2
    }

    static func read(url: URL) -> UsageLogParser.Result {
        guard let db = SQLiteStore.open(url) else {
            // Reported rather than treated as an empty conversation, so the
            // file is retried instead of being remembered as fully imported.
            return UsageLogParser.Result(malformedLines: 1)
        }
        defer { sqlite3_close(db) }

        // The file is named for the conversation, which is what a session is
        // here. Antigravity does not repeat that id inside the tables this
        // reads.
        let name = url.deletingPathExtension().lastPathComponent
        let session = UsageLogParser.key(name.isEmpty ? url.path : name)
        let names = modelNames(in: db)
        var result = UsageLogParser.Result()
        var seen = Set<String>()

        // Ordered, so that the fallback identity below is the same on every
        // scan and a row without a response id is not re-imported as a new one.
        let steps = SQLiteStore.blobs(in: db, sql: "SELECT metadata FROM steps WHERE metadata IS NOT NULL ORDER BY idx")
        for (row, blob) in steps.enumerated() {
            guard let step = ProtobufMessage(blob) else {
                result.malformedLines += 1
                continue
            }
            guard let usage = step.message(Step.usage) else { continue }

            let input = usage.count(Stats.inputTokens)
            let cached = usage.count(Stats.cacheReadTokens)
            let write = usage.count(Stats.cacheWriteTokens)
            // `output_tokens` is already the sum of the thinking and response
            // halves — the descriptor splits it, it does not add to it. Adding
            // the halves back on would count every reasoning token twice.
            let output = usage.count(Stats.outputTokens)
            let tokens = TokenCounts(input: input, cached: cached, cacheWrite: write, output: output)
            guard tokens.total > 0 else { continue }

            guard let date = timestamp(step) else {
                // A generation with no time cannot be placed on any chart or
                // period, and silently dating it "now" would move history.
                result.malformedLines += 1
                continue
            }

            let response = usage.string(Stats.responseID).flatMap { $0.isEmpty ? nil : $0 }
            // The server-assigned response id is unique across installs, which
            // is what lets the same conversation be counted once no matter how
            // many copies of the database are on disk. Without one, fall back
            // to something unique to this file so a real generation is not
            // dropped — at the cost of that row not deduplicating against a
            // copy of the same database elsewhere.
            let identity = response ?? "\(url.path)#\(row)"
            guard seen.insert(identity).inserted else { continue }

            result.records.append(TokenUsageRecord(
                id: UsageLogParser.key("antigravity:\(identity)"),
                agent: .antigravity,
                session: session,
                timestamp: date,
                model: response.flatMap { names[$0] } ?? "Unknown model",
                tokens: tokens))
        }
        return result
    }

    /// Model name per response id. `gen_metadata` is read separately and only
    /// for this: it is the one place the name appears as text.
    private static func modelNames(in db: OpaquePointer?) -> [String: String] {
        var names: [String: String] = [:]
        for blob in SQLiteStore.blobs(in: db, sql: "SELECT data FROM gen_metadata") {
            guard let row = ProtobufMessage(blob),
                  let generation = row.message(Generation.envelope),
                  let name = generation.string(Generation.modelName), !name.isEmpty,
                  let usage = generation.message(Generation.usage),
                  let response = usage.string(Stats.responseID), !response.isEmpty else { continue }
            names[response] = name
        }
        return names
    }

    private static func timestamp(_ step: ProtobufMessage) -> Date? {
        for field in [Step.startedAt] + Step.completedAt {
            guard let stamp = step.message(field) else { continue }
            let seconds = stamp.count(Stamp.seconds)
            // Field 1 of a step is a Timestamp, but a zero-second one is the
            // proto default rather than 1970, and dating a request to the epoch
            // would silently anchor every chart's range to it.
            guard seconds > 0 else { continue }
            let nanos = Double(stamp.count(Stamp.nanos)) / 1_000_000_000
            return Date(timeIntervalSince1970: Double(seconds) + nanos)
        }
        return nil
    }
}
