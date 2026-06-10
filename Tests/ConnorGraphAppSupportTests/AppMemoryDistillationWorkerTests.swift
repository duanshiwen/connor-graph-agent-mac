import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

private func temporaryAppMemoryDistillationDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func memoryDistillationWorkerEnqueuesExtractionJobAndDrainsBuffer() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = try SQLiteGraphKernelStore(path: temporaryAppMemoryDistillationDatabaseURL().path)
    try store.migrate()
    let repository = AppMemoryStagingBufferRepository(store: store)
    let bundle = ConversationTurnBundle(
        id: "bundle-1",
        sessionID: "session-1",
        userMessages: [ConversationTurnMessage(id: "user-1", role: .user, content: "诗闻喜欢结构化推进", createdAt: now)],
        assistantMessage: ConversationTurnMessage(id: "assistant-1", role: .assistant, content: "我会按步骤推进。", createdAt: now),
        startedAt: now,
        closedAt: now,
        status: .closed
    )
    try repository.saveBuffer(MemoryStagingBuffer(id: "buffer-1", sessionID: "session-1", pendingBundles: [bundle]), updatedAt: now)

    let result = try AppMemoryDistillationWorker(store: store).runOnce(now: now)

    #expect(result?.outcome == .succeeded)
    #expect(result?.enqueuedJobIDs.count == 1)
    let drainedBuffer = try repository.loadBuffer(id: "buffer-1")
    #expect(drainedBuffer?.status == .drained)
    #expect(drainedBuffer?.pendingBundles.isEmpty == true)
    #expect(drainedBuffer?.metadata["last_distillation_enqueued_job_count"] == "1")

    let jobs = try store.runnableJobs(graphID: "default", at: now)
    #expect(jobs.count == 1)
    #expect(jobs[0].type == .extraction)
    let payload = GraphExtractionJobPayload(dictionary: jobs[0].payload)
    #expect(payload?.source.sessionID == "session-1")
    #expect(payload?.source.sourceType == .chat)
    #expect(payload?.source.content.contains("User: 诗闻喜欢结构化推进") == true)
    #expect(payload?.source.metadata["memory_staging_buffer_id"] == "buffer-1")
}

@Test func memoryDistillationWorkerKeepsOpenBundlesWhenDrainingClosedBundles() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = try SQLiteGraphKernelStore(path: temporaryAppMemoryDistillationDatabaseURL().path)
    try store.migrate()
    let repository = AppMemoryStagingBufferRepository(store: store)
    let closedBundle = ConversationTurnBundle(
        id: "bundle-closed",
        sessionID: "session-mixed",
        userMessages: [ConversationTurnMessage(id: "user-closed", role: .user, content: "已完成的一轮", createdAt: now)],
        assistantMessage: ConversationTurnMessage(id: "assistant-closed", role: .assistant, content: "已回答", createdAt: now),
        startedAt: now,
        closedAt: now,
        status: .closed
    )
    let openBundle = ConversationTurnBundle(
        id: "bundle-open",
        sessionID: "session-mixed",
        userMessages: [ConversationTurnMessage(id: "user-open", role: .user, content: "新一轮还在等待回答", createdAt: now)],
        startedAt: now,
        status: .open
    )
    try repository.saveBuffer(MemoryStagingBuffer(id: "buffer-mixed", sessionID: "session-mixed", pendingBundles: [closedBundle, openBundle]), updatedAt: now)

    _ = try AppMemoryDistillationWorker(store: store).runOnce(now: now)

    let buffer = try repository.loadBuffer(id: "buffer-mixed")
    #expect(buffer?.status == .active)
    #expect(buffer?.pendingBundles.map(\.id) == ["bundle-open"])
    #expect(try store.runnableJobs(graphID: "default", at: now).count == 1)
}

@Test func memoryDistillationWorkerSkipsWhenNoClosedBundlesExist() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let store = try SQLiteGraphKernelStore(path: temporaryAppMemoryDistillationDatabaseURL().path)
    try store.migrate()
    let repository = AppMemoryStagingBufferRepository(store: store)
    let openBundle = ConversationTurnBundle(
        id: "bundle-open",
        sessionID: "session-open",
        userMessages: [ConversationTurnMessage(id: "user-open", role: .user, content: "还没回答")],
        status: .open
    )
    try repository.saveBuffer(MemoryStagingBuffer(id: "buffer-open", sessionID: "session-open", pendingBundles: [openBundle]), updatedAt: now)

    let result = try AppMemoryDistillationWorker(store: store).runOnce(now: now)

    #expect(result == nil)
    #expect(try store.runnableJobs(graphID: "default", at: now).isEmpty)
    #expect(try repository.loadBuffer(id: "buffer-open")?.status == .active)
}
