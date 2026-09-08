import Foundation

/// How much Antigravity has actually been used, counted from its own
/// transcripts.
///
/// This exists because Google publishes no usage figure. `loadCodeAssist`
/// returns tiers and nothing else, and no quota comes back on the wire.
/// Counting locally is the only honest number available.
///
/// It is a *count*, never a percentage. A fraction needs a limit and there is
/// no published limit to divide by — inventing a denominator would put a
/// confident ring on a guess.
///
/// This counts *requests*, from the transcripts, which is what the notch cell
/// needs: a cheap, current "how busy has today been". It is not where tokens
/// come from. Antigravity does record exact per-generation token counts, in
/// the `ModelUsageStats` messages inside its conversation databases — an
/// earlier version of this comment claimed those databases held nothing of the
/// sort, which was wrong — and `AntigravityUsageReader` is what reads them for
/// the Usage page.
struct AntigravityActivity: Equatable {
    let requestsToday: Int
    let lastRequest: Date?

    static var transcriptRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".gemini/antigravity/brain")
    }

    /// A step the model actually answered. User input and system checkpoints
    /// share the transcript, and counting those would inflate the number with
    /// work the model never did.
    private static let modelSource = "MODEL"
    /// The same word as bytes, to sieve lines with before paying for JSON.
    private static let modelMarker = Data(modelSource.utf8)
    private static let newline = UInt8(ascii: "\n")

    /// Read as bytes, sieved, then decoded — in that order, and none of it more
    /// than once.
    ///
    /// The transcripts are append-only and grow without bound, and this runs on
    /// every fetch. The first version decoded the whole file to a `String`,
    /// split it into substrings, converted each substring **back** to `Data`,
    /// and built a fresh `JSONDecoder` and a fresh `ISO8601DateFormatter` per
    /// line. On a machine with a few weeks of Antigravity history that is tens
    /// of thousands of throwaway objects a minute, which is what put this app's
    /// heap where it was.
    ///
    /// Three things changed and none of them alter the answer. The file stays
    /// `Data`, so slicing it costs nothing and there is no UTF-8 round trip.
    /// The decoder and the formatters are made once. And a line is only handed
    /// to the decoder if the bytes `MODEL` appear in it at all — a step whose
    /// source is `MODEL` always contains them, so nothing that used to be
    /// counted stops being counted, while the great majority of lines, which
    /// are user turns and checkpoints, are rejected by a byte search instead of
    /// a JSON parse.
    static func read(root: URL = transcriptRoot, now: Date = Date()) -> AntigravityActivity {
        let manager = FileManager.default
        guard let trajectories = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return AntigravityActivity(requestsToday: 0, lastRequest: nil) }

        var today = 0
        var latest: Date?
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let decoder = JSONDecoder()

        for trajectory in trajectories {
            let transcript = trajectory
                .appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard let data = try? Data(contentsOf: transcript) else { continue }

            for line in data.split(separator: newline, omittingEmptySubsequences: true) {
                guard line.range(of: modelMarker) != nil,
                      let step = try? decoder.decode(Step.self, from: line),
                      step.source == modelSource,
                      let at = parse(step.created_at)
                else { continue }

                if latest == nil || at > latest! { latest = at }
                // `created_at` is UTC — the trailing Z is not decoration. The
                // comparison has to be against the *local* day, which is what
                // `isDate(_:inSameDayAs:)` on a local calendar does; treating
                // the timestamp as local instead would move every count either
                // side of midnight by the offset.
                if calendar.isDate(at, inSameDayAs: now) { today += 1 }
            }
        }
        return AntigravityActivity(requestsToday: today, lastRequest: latest)
    }

    private struct Step: Decodable {
        let created_at: String
        let source: String?
    }

    static func parse(_ value: String) -> Date? { ISO8601Stamp.date(from: value) }

    /// What the cell says. Deliberately a count with the limit's absence stated,
    /// rather than a number that looks like a percentage.
    var summary: String {
        guard requestsToday > 0 else { return "no requests today" }
        return "~\(requestsToday) request\(requestsToday == 1 ? "" : "s") today"
    }
}
