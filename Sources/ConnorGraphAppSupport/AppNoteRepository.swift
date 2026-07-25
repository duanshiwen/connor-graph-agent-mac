import Foundation
import ConnorGraphCore
import ConnorGraphStore

public struct AppNoteRepository: Sendable {
    public let store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func upsert(_ note: NoteRecord) throws { try store.upsertNote(note) }
    public func note(id: String) throws -> NoteRecord? { try store.note(id: id) }
    public func note(sessionID: String) throws -> NoteRecord? { try store.note(sessionID: sessionID) }
    public func notes(ids: [String]) throws -> [NoteRecord] { try store.notes(ids: ids) }
    public func delete(sessionID: String, deletedAt: Date = Date()) throws { try store.deleteNote(sessionID: sessionID, deletedAt: deletedAt) }
    public func isDeleted(id: String) throws -> Bool { try store.isNoteDeleted(id: id) }
    public func attachImportMetadata(sessionID: String, metadata: NoteImportProjectionMetadata) throws { try store.attachNoteImportMetadata(sessionID: sessionID, metadata: metadata) }
    public func projectionCandidates(afterSessionID: String? = nil, limit: Int = 25) throws -> [NoteProjectionCandidate] { try store.noteProjectionCandidates(afterSessionID: afterSessionID, limit: limit) }
    public func claimProjection(sessionID: String, owner: String, leaseDuration: TimeInterval = 120) throws -> Bool { try store.claimNoteProjection(sessionID: sessionID, owner: owner, leaseDuration: leaseDuration) }
    public func releaseProjection(sessionID: String, owner: String) throws { try store.releaseNoteProjection(sessionID: sessionID, owner: owner) }
    public func orphanedSessionIDs(limit: Int = 25) throws -> [String] { try store.orphanedNoteSessionIDs(limit: limit) }
    public func notesNeedingIndex(version: Int, limit: Int = 25) throws -> [NoteRecord] { try store.notesNeedingIndex(version: version, limit: limit) }
    public func upsertSearchDocument(_ note: NoteRecord, indexedText: String, indexVersion: Int) throws { try store.upsertNoteSearchDocument(note, indexedText: indexedText, indexVersion: indexVersion) }
    public func search(matchQuery: String?, matchedTerms: [String], startDate: Date?, endDate: Date?, originKind: NoteOriginKind?, page: Int, pageSize: Int) throws -> NoteSearchPage {
        try store.searchNotes(matchQuery: matchQuery, matchedTerms: matchedTerms, startDate: startDate, endDate: endDate, originKind: originKind, page: page, pageSize: pageSize)
    }
}
