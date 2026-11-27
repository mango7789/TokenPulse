import Foundation
import SQLite3

/// Lightweight read-only SQLite helper that never writes or locks active app databases.
final class SQLiteReader {
    private var db: OpaquePointer?

    init?(path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let uri = "file:\(path)?mode=ro&immutable=0"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        var handle: OpaquePointer?
        if sqlite3_open_v2(uri, &handle, flags, nil) != SQLITE_OK {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        sqlite3_busy_timeout(handle, 500)
        self.db = handle
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func query(_ sql: String, rowHandler: (OpaquePointer) -> Void) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            rowHandler(stmt)
        }
    }

    static func string(_ stmt: OpaquePointer, col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }

    static func int(_ stmt: OpaquePointer, col: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, col))
    }
}
