import Foundation
import ConnorGraphCore

/// Serializes note-import projection reads away from the MainActor.
///
/// The underlying repository has a synchronous SQLite API. Calling it from a
/// MainActor-isolated view model would block all application interaction while
/// SQLite waits for its lock, WAL writer, or disk I/O. This actor is the async
/// boundary consumed by UI code.
public actor NoteImportActivityReader {
    private let ledger: AppNoteImportRepository

    public init(ledger: AppNoteImportRepository) {
        self.ledger = ledger
    }

    public func jobPage(cursor: String? = nil, pageSize: Int = 50) throws -> NoteImportJobPage {
        try ledger.jobPage(cursor: cursor, pageSize: pageSize)
    }

    public func itemPage(jobID: String, cursor: String? = nil, pageSize: Int = 50) throws -> NoteImportItemPage {
        try ledger.itemPage(jobID: jobID, cursor: cursor, pageSize: pageSize)
    }

    public func sourceNames() throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try ledger.sources().map { ($0.id, $0.displayName) })
    }
}
