import Foundation
import SQLite3

/// Recovers Codex usage that archiving would otherwise take with it.
///
/// Archiving a thread in Codex Desktop deletes its rollout log. On the machine
/// this was written against that is not a rare event: 753 of 816 threads were
/// archived, and every one of them had lost its transcript, while all 63
/// unarchived threads still had theirs. Everything the detailed reader knows
/// comes from those logs, so without this an archived thread contributes
/// nothing at all.
///
/// Codex keeps a per-thread `tokens_used` in its own state database, and that
/// row outlives the log. It is a coarser reading in two ways, both of which are
/// carried honestly rather than smoothed over:
///
/// - It is the *final* cumulative counter, not the sum across context
///   compactions. Checked against the logs still on disk it matched exactly for
///   every thread that never compacted, and undercounted the ones that did —
///   188M against a true 311M across the same 63 threads. So a thread total is
///   a floor, and it lands in the unclassified bucket, which is already the
///   bucket that carries no cost estimate.
/// - It has no input/output split and no per-turn times, so the whole thread is
///   dated by when it was last worked on.
///
/// A thread is only read here when its log is genuinely gone *and* nothing was
/// imported from it earlier, so the detailed history of a thread archived after
/// Codenotch had already seen it is kept, and never counted twice.
enum CodexThreadReader {
    /// Codex versions its state database (`state_5.sqlite` today), so the name
    /// is matched rather than hardcoded. A shallow scan: `~/.codex` also holds
    /// the session tree, and walking it here would be walking it twice.
    static func stateFiles(home: URL) -> [URL] {
        let root = home.appendingPathComponent(".codex")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return contents.filter {
            $0.pathExtension == "sqlite" && $0.lastPathComponent.hasPrefix("state_")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Columns in the order the query below asks for them.
    private enum Column {
        static let id = 0, tokens = 1, model = 2, updatedMilliseconds = 3
        static let updatedSeconds = 4, rollout = 5
        static let count = 6
    }

    static func read(url: URL, importedSessions: Set<String>) throws -> UsageLogParser.Result {
        guard let database = SQLiteStore.open(url) else {
            return UsageLogParser.Result(malformedLines: 1)
        }
        defer { sqlite3_close(database) }
        let rows = SQLiteStore.rows(in: database, sql: """
            select id, tokens_used, model, updated_at_ms, updated_at, rollout_path from threads
            """, columns: Column.count)
        try Task.checkCancellation()
        return UsageLogParser.Result(records: records(rows: rows, importedSessions: importedSessions))
    }

    /// Pure, so the accounting can be tested without a database.
    static func records(rows: [[String]], importedSessions: Set<String>,
                        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) })
        -> [TokenUsageRecord] {
        rows.compactMap { row in
            guard row.count >= Column.count else { return nil }
            let thread = row[Column.id]
            guard !thread.isEmpty, let used = Int64(row[Column.tokens]), used > 0 else { return nil }

            // The log is the better source wherever it still exists, and
            // anything already imported from it must not be added again.
            let rollout = row[Column.rollout]
            guard !fileExists(rollout) else { return nil }
            let session = UsageLogParser.key(thread)
            guard !importedSessions.contains(session) else { return nil }

            guard let date = timestamp(milliseconds: row[Column.updatedMilliseconds],
                                       seconds: row[Column.updatedSeconds]) else { return nil }
            let model = row[Column.model].isEmpty ? "Unknown model" : row[Column.model]
            // Unclassified: a single total with no split, which is exactly what
            // the other bucket means and why it carries no cost.
            return TokenUsageRecord(id: UsageLogParser.key("codex-thread:\(thread)"),
                                    agent: .codex, session: session, timestamp: date,
                                    model: model, tokens: TokenCounts(other: used))
        }
    }

    /// Newer rows carry milliseconds; older ones only whole seconds.
    static func timestamp(milliseconds: String, seconds: String) -> Date? {
        if let value = Double(milliseconds), value > 0, value < 4_102_444_800_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        if let value = Double(seconds), value > 0, value < 4_102_444_800 {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }
}
