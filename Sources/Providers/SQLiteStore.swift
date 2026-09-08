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
///
/// The catch is that `sqlite3_open_v2` does not open anything. It allocates a
/// handle and returns `SQLITE_OK` without touching the file, and the "unable to
/// open database file" that a missing `-shm` causes only appears when the first
/// statement runs. Taking that `SQLITE_OK` at face value meant the `mode=ro`
/// attempt always won, the `immutable=1` fallback was never reached, and every
/// query against a quit-and-checkpointed database came back as *no rows* — not
/// an error, an empty result, which reads as "this app has no history" rather
/// than "this app was not read". So each candidate is made to answer a real
/// query before it is accepted.
enum SQLiteStore {
    static func open(_ url: URL) -> OpaquePointer? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        for query in ["mode=ro", "immutable=1"] {
            var db: OpaquePointer?
            guard sqlite3_open_v2("file:\(url.path)?\(query)", &db,
                                  SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
                  let handle = db else {
                sqlite3_close(db)
                continue
            }
            if isReadable(handle) { return handle }
            sqlite3_close(handle)
        }
        return nil
    }

    /// Whether the handle can actually reach the file. Reading the schema is
    /// the cheapest statement that has to consult it.
    private static func isReadable(_ db: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master", -1, &statement, nil) == SQLITE_OK
        else { return false }
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

    /// First column of every row, as bytes.
    ///
    /// Separate from the text accessors because `sqlite3_column_text` stops at
    /// the first NUL byte, and the rows this reads are serialized protobuf —
    /// where a NUL is an ordinary part of a number, not the end of anything.
    static func blobs(in db: OpaquePointer?, sql: String) -> [Data] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var out: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let raw = sqlite3_column_blob(statement, 0) else { continue }
            out.append(Data(bytes: raw, count: count))
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
