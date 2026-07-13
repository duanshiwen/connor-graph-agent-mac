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

    public func jobs(limit: Int = 200) throws -> [NoteImportJobRecord] {
        try ledger.jobs(limit: limit)
    }

    public func items(jobID: String) throws -> [NoteImportItemRecord] {
        try ledger.items(jobID: jobID)
    }
}
