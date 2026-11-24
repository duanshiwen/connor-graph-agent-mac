import Foundation
import SQLite3

/// FTS5 UNINDEXED identifiers cannot serve as B-tree lookup keys. Keep the
/// existing FTS rowids (and ranking) while providing indexed identifier lookup.
struct SQLiteFTSRowLookup: Sendable {
    let table: String
    var lookup: String { "\(table)_row_lookup" }

    func migrate(db: OpaquePointer?, identifier: String) throws {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(lookup)'", -1, &statement, nil), db: db)
        let exists = sqlite3_step(statement) == SQLITE_ROW
        sqlite3_finalize(statement)
        guard !exists else { return }
        try execute("BEGIN IMMEDIATE", db: db)
        do {
            try execute("CREATE TABLE \(lookup) (fts_rowid INTEGER PRIMARY KEY, document_id TEXT NOT NULL)", db: db)
            try execute("CREATE INDEX \(lookup)_id ON \(lookup)(document_id)", db: db)
            // One atomic migration, including existing installations; no retokenizing.
            try execute("INSERT INTO \(lookup)(fts_rowid, document_id) SELECT rowid, \(identifier) FROM \(table)", db: db)
            try execute("COMMIT", db: db)
        } catch {
            try? execute("ROLLBACK", db: db)
            throw error
        }
    }

    func remove(_ id: String, db: OpaquePointer?) throws {
        try execute("DELETE FROM \(table) WHERE rowid IN (SELECT fts_rowid FROM \(lookup) WHERE document_id = ?)", id: id, db: db)
        try execute("DELETE FROM \(lookup) WHERE document_id = ?", id: id, db: db)
    }

    /// Must follow the FTS INSERT on the same connection and transaction.
    func recordInsertion(_ id: String, db: OpaquePointer?) throws {
        try execute("INSERT INTO \(lookup)(fts_rowid, document_id) VALUES (last_insert_rowid(), ?)", id: id, db: db)
    }

    func clear(db: OpaquePointer?) throws {
        try execute("DELETE FROM \(lookup)", db: db)
    }

    private func execute(_ sql: String, id: String? = nil, db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(db, sql, -1, &statement, nil), db: db)
        defer { sqlite3_finalize(statement) }
        if let id {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            try check(sqlite3_bind_text(statement, 1, id, -1, transient), db: db)
        }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw Failure(message: String(cString: sqlite3_errmsg(db))) }
    }

    private func check(_ result: Int32, db: OpaquePointer?) throws {
        guard result == SQLITE_OK else { throw Failure(message: String(cString: sqlite3_errmsg(db))) }
    }

    private struct Failure: Error { let message: String }
}
