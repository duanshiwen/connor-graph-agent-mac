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
    private var itemSnapshots: [String: [NoteImportItemRecord]] = [:]

    public init(ledger: AppNoteImportRepository) {
        self.ledger = ledger
    }

    public func jobs(limit: Int = 200) throws -> [NoteImportJobRecord] {
        try ledger.jobsWithLiveCounts(limit: limit)
    }

    public func items(jobID: String) throws -> [NoteImportItemRecord] {
        let values = try ledger.items(jobID: jobID)
        itemSnapshots[jobID] = values
        return values
    }

    public func changedItems(jobID: String) throws -> [NoteImportItemRecord]? {
        let values = try ledger.items(jobID: jobID)
        guard itemSnapshots[jobID] != values else { return nil }
        itemSnapshots[jobID] = values
        return values
    }

    public func sourceNames() throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try ledger.sources().map { ($0.id, $0.displayName) })
    }
}
