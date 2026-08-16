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

@Test func noteRepositoryRoundTripsImportHierarchy() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let repository = AppNoteRepository(store: store)
    try repository.upsert(NoteRecord(
        id: "note:notion", sessionID: "session-notion", sourceMessageID: "message",
        title: "深层页面", body: "body", contentHash: "hash", sourceUpdatedAt: .now,
        createdAt: .now, updatedAt: .now, importHierarchy: ["笔记本", "子分类", "深层"]
    ))

    let loaded = try #require(try repository.note(sessionID: "session-notion"))
    #expect(loaded.importHierarchy == ["笔记本", "子分类", "深层"])
    #expect(loaded.title == "深层页面")
}

@Test func noteRepositoryAttachImportMetadataPersistsHierarchy() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let repository = AppNoteRepository(store: store)
    try repository.upsert(NoteRecord(
        id: "note:notion-2", sessionID: "session-notion-2", sourceMessageID: "message",
        title: "子页面", body: "body", contentHash: "hash", sourceUpdatedAt: .now,
        createdAt: .now, updatedAt: .now
    ))
    try repository.attachImportMetadata(sessionID: "session-notion-2", metadata: NoteImportProjectionMetadata(
        itemID: "item-1", sourceID: "source-1", sourceKind: "notion_export", sourceIdentity: "identity",
        externalID: "abc", relativePath: "笔记本/子分类/子页面.md", sourceCreatedAt: .now,
        hierarchy: ["笔记本", "子分类"]
    ))

    let loaded = try #require(try repository.note(sessionID: "session-notion-2"))
    #expect(loaded.importHierarchy == ["笔记本", "子分类"])
    #expect(loaded.originKind == .imported)
    #expect(loaded.relativePath == "笔记本/子分类/子页面.md")
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
