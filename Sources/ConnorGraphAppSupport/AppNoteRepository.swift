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
}
