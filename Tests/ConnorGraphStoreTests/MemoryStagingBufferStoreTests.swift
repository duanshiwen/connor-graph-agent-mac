import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

private func temporaryMemoryStagingDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphKernelStoreCreatesMemoryStagingBufferTable() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryMemoryStagingDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("memory_staging_buffers"))
}

@Test func graphKernelStoreRoundTripsMemoryStagingBuffer() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryMemoryStagingDatabaseURL().path)
    try store.migrate()
    let base = Date(timeIntervalSince1970: 20_000)
    let bundle = ConversationTurnBundle(
        id: "bundle-1",
        sessionID: "session-1",
        userMessages: [ConversationTurnMessage(id: "u1", role: .user, content: "记住这个偏好", createdAt: base)],
        assistantMessage: ConversationTurnMessage(id: "a1", role: .assistant, content: "已记录", createdAt: base.addingTimeInterval(2)),
        artifacts: [MemoryStagingArtifact(id: "browser-1", kind: .browserContext, content: "网页正文", summary: "网页摘要", createdAt: base.addingTimeInterval(1))],
        startedAt: base,
        closedAt: base.addingTimeInterval(2),
        status: .closed
    )
    var buffer = MemoryStagingBuffer(
        id: "buffer-1",
        sessionID: "session-1",
        pendingBundles: [bundle],
        tokenEstimate: 42
    )
    buffer.lastDistilledAt = base.addingTimeInterval(10)

    try store.upsertMemoryStagingBuffer(buffer, updatedAt: base.addingTimeInterval(11))

    let loadedByID = try store.memoryStagingBuffer(id: "buffer-1")
    let loadedBySession = try store.memoryStagingBuffer(sessionID: "session-1")

    #expect(loadedByID == buffer)
    #expect(loadedBySession == buffer)
    #expect(loadedBySession?.pendingBundles.first?.artifacts.first?.kind == .browserContext)
}

@Test func graphKernelStoreReplacesMemoryStagingBufferForSameSession() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryMemoryStagingDatabaseURL().path)
    try store.migrate()
    let first = MemoryStagingBuffer(id: "buffer-1", sessionID: "session-2", tokenEstimate: 10)
    let second = MemoryStagingBuffer(id: "buffer-2", sessionID: "session-2", tokenEstimate: 20)

    try store.upsertMemoryStagingBuffer(first)
    try store.upsertMemoryStagingBuffer(second)

    #expect(try store.memoryStagingBuffer(sessionID: "session-2")?.id == "buffer-2")
    #expect(try store.memoryStagingBuffer(id: "buffer-1") == nil)
}

@Test func graphKernelStoreListsMemoryStagingBuffersByStatusAndDeletesThem() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryMemoryStagingDatabaseURL().path)
    try store.migrate()
    let active = MemoryStagingBuffer(id: "active", sessionID: "session-active", status: .active)
    let drained = MemoryStagingBuffer(id: "drained", sessionID: "session-drained", status: .drained)

    try store.upsertMemoryStagingBuffer(active, updatedAt: Date(timeIntervalSince1970: 1))
    try store.upsertMemoryStagingBuffer(drained, updatedAt: Date(timeIntervalSince1970: 2))

    #expect(try store.memoryStagingBuffers(status: .active).map(\.id) == ["active"])
    #expect(try store.memoryStagingBuffers(status: nil).map(\.id) == ["drained", "active"])

    try store.deleteMemoryStagingBuffer(sessionID: "session-active")
    try store.deleteMemoryStagingBuffer(id: "drained")

    #expect(try store.memoryStagingBuffers(status: nil).isEmpty)
}
