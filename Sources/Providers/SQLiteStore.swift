import Foundation
import SQLite3

/// Read-only access to another app's SQLite store.
///
/// Both Cursor and Codex keep their state this way, and both run it in WAL mode,
/// which makes opening it more delicate than it looks:
///
/// - `immutable=1` tells SQLite to ignore the write-ahead log entirely, so a
///   running app's most recent writes are invisible. That is how a live agent
///   looks idle and a rotated token looks current.
/// - `mode=ro` sees the log, but needs the `-shm` sidecar to do it — and that
///   file exists only *while the owning app is running*. Once it has quit and
///   checkpointed, a read-only open fails outright with "unable to open
///   database file".
///
/// So: `mode=ro` first, `immutable=1` second. The fallback is only ever reached
/// when there is no write-ahead log left to miss, which is exactly when ignoring
/// it costs nothing.
enum SQLiteStore {
    static func open(_ url: URL) -> OpaquePointer? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        for query in ["mode=ro", "immutable=1"] {
            var db: OpaquePointer?
            if sqlite3_open_v2("file:\(url.path)?\(query)", &db,
                               SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
               let db, canRead(db) {
                return db
            }
            sqlite3_close(db)
        }
        return nil
    }

    /// `sqlite3_open_v2` allocates the connection before it ever touches the
    /// file, so `mode=ro` reports success for a write-ahead-logged database
    /// whose `-shm` sidecar is gone, and only fails at the first statement.
    /// Taking that handle at its word is worse than failing: it answers every
    /// query with no rows, so a store full of history reads as an empty one and
    /// the `immutable=1` fallback below it is never reached. Reading the schema
    /// is the cheapest proof that the handle can actually see the file.
    private static func canRead(_ db: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "select count(*) from sqlite_master", -1,
                                 &statement, nil) == SQLITE_OK else { return false }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// Every column of every row, as text. Needed where one row carries more
    /// than one fact — a thread's title *and* when it was last touched — and
    /// two queries would be two chances for them to disagree.
    static func rows(in db: OpaquePointer?, sql: String, columns: Int) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var out: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String] = []
            for index in 0..<Int32(columns) {
                row.append(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "")
            }
            out.append(row)
        }
        return out
    }

    /// An integer key and a binary payload per row, for stores that keep
    /// serialized protobuf rather than text. A row whose blob is empty or whose
    /// key is not an integer is skipped rather than reported: these tables are
    /// written by another app and may hold rows this build knows nothing about.
    static func blobRows(in db: OpaquePointer?, sql: String) -> [(index: Int, data: Data)] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var out: [(index: Int, data: Data)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard sqlite3_column_type(statement, 0) == SQLITE_INTEGER else { continue }
            let index = Int(sqlite3_column_int64(statement, 0))
            let count = Int(sqlite3_column_bytes(statement, 1))
            guard count > 0, let raw = sqlite3_column_blob(statement, 1) else { continue }
            out.append((index, Data(bytes: raw, count: count)))
        }
        return out
    }

    /// First column of every row, as text.
    static func rows(in db: OpaquePointer?, sql: String, bind: String? = nil) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        if let bind {
            sqlite3_bind_text(statement, 1, bind, -1,
                              unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        var out: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let raw = sqlite3_column_text(statement, 0) { out.append(String(cString: raw)) }
        }
        return out
    }
}
