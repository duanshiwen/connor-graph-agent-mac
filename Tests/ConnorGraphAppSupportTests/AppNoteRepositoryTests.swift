import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func noteRepositoryMigratesAndUpsertsBySessionIdentity() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let repository = AppNoteRepository(store: store)
    let first = NoteRecord(
        id: "note:session-1", sessionID: "session-1", sourceMessageID: "message-1",
        title: "First", body: "完整正文", contentHash: "hash-1",
        sourceUpdatedAt: Date(timeIntervalSince1970: 10), createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    try repository.upsert(first)
    var changed = first
    changed.title = "Changed"
    changed.body = "updated"
    changed.contentHash = "hash-2"
    try repository.upsert(changed)

    let loaded = try #require(try repository.note(sessionID: "session-1"))
    #expect(loaded.id == first.id)
    #expect(loaded.title == "Changed")
    #expect(loaded.body == "updated")
    #expect(try repository.notes(ids: [first.id]).count == 1)
}

@Test func noteRepositoryDeletesIdempotentlyAndKeepsTombstone() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let repository = AppNoteRepository(store: store)
    try repository.upsert(NoteRecord(
        id: "note:deleted", sessionID: "deleted", sourceMessageID: "message",
        title: "Deleted", body: "body", contentHash: "hash", sourceUpdatedAt: .now,
        createdAt: .now, updatedAt: .now
    ))

    try repository.delete(sessionID: "deleted")
    try repository.delete(sessionID: "deleted")

    #expect(try repository.note(sessionID: "deleted") == nil)
    #expect(try repository.isDeleted(id: "note:deleted"))
}
