import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private actor MemoryOSFinalAnswerProvider: AgentModelProvider {
    let modelID = "memory-os-final-answer"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        AgentModelResponse(text: "Memory OS assistant answer", usage: AgentModelUsage(promptTokens: 10, completionTokens: 5))
    }
}

@Test func loopChatControllerPersistsUserAndAssistantMessagesToMemoryOSL0L1() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    let store = try SQLiteMemoryOSStore(path: databaseURL.path)
    try store.migrate()
    let memoryOSRepository = AppMemoryOSRepository(store: store)
    let loop = AgentLoopController(modelProvider: MemoryOSFinalAnswerProvider(), toolRegistry: AgentToolRegistry())
    var controller = AgentLoopChatController(
        loopController: loop,
        session: AgentSession(id: "session-memory-os-loop"),
        memoryOSRepository: memoryOSRepository
    )

    _ = try await controller.submit("请记住：商用记忆系统必须可审计")

    let provenanceRows = try store.query(sql: "SELECT source_type, title, content FROM memory_l0_provenance_objects ORDER BY occurred_at ASC")
    let captureRows = try store.query(sql: "SELECT event_type FROM memory_l1_capture_events ORDER BY occurred_at ASC")

    #expect(provenanceRows.count == 2)
    #expect(provenanceRows.contains { $0[0] == "chat_message" && $0[2].contains("商用记忆系统") })
    #expect(provenanceRows.contains { $0[0] == "assistant_message" && $0[2] == "Memory OS assistant answer" })
    #expect(Set(captureRows.map { $0[0] }) == Set(["chat_message", "assistant_message"]))
}

@Test func loopChatControllerCanPersistMessagesThroughMemoryOSFacade() async throws {
    let store = try SQLiteMemoryOSStore(path: ":memory:")
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let loop = AgentLoopController(modelProvider: MemoryOSFinalAnswerProvider(), toolRegistry: AgentToolRegistry())
    var controller = AgentLoopChatController(
        loopController: loop,
        session: AgentSession(id: "session-memory-os-facade"),
        memoryOSFacade: facade
    )

    _ = try await controller.submit("请记住：Memory OS facade 是 App 层唯一新入口")

    let summary = try facade.operationalSummary()
    #expect(summary.dashboardSnapshot.l0ProvenanceObjectCount == 2)
    #expect(summary.dashboardSnapshot.l1PendingCaptureCount == 2)
}

@Test func appMemoryOSBackgroundJobRunnerDetectsExpiredQueueLeases() {
    let runner = AppMemoryOSBackgroundJobRunner()
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(runner.shouldRecover(queueStatus: .leased, leaseExpiresAt: now.addingTimeInterval(-10), now: now))
    #expect(!runner.shouldRecover(queueStatus: .leased, leaseExpiresAt: now.addingTimeInterval(10), now: now))
}

@Test func appMemoryOSBackgroundJobRunnerRunsProjectionQueueThroughFacade() throws {
    let store = try SQLiteMemoryOSStore(path: ":memory:")
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 1_000)
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "a", name: "诗闻", evidenceSpanIDs: ["span-1"]),
            GraphStructuredExtractedEntity(localID: "b", name: "Connor Memory OS", evidenceSpanIDs: ["span-1"])
        ],
        statements: [
            GraphStructuredExtractedStatement(subjectLocalID: "a", predicate: .relatedTo, objectLocalID: "b", statementText: "Background runner projects Memory OS jobs.", confidence: 0.94, evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "Background runner projects Memory OS jobs.")]
    )
    let raw = String(data: try JSONEncoder().encode(output), encoding: .utf8)!
    let payload = MemoryOSProjectionQueuePayload(rawContent: raw, modelID: "test-model")
    try store.enqueue(MemoryOSQueueItem(id: "background-projection", kind: "project_artifact", payloadJSON: store.json(payload), nextRunAt: now, idempotencyKey: "background-projection-key"))

    let summary = try AppMemoryOSBackgroundJobRunner().runOnce(facade: facade, now: now)

    #expect(summary.projectionRunCount == 1)
    #expect(try store.queueItem(id: "background-projection")?.status == .succeeded)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_statements;").first?.first == "1")
}

@Test func appMemoryOSBackgroundJobRunnerRunsThroughFacade() throws {
    let store = try SQLiteMemoryOSStore(path: ":memory:")
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 1_000)

    let summary = try AppMemoryOSBackgroundJobRunner().runOnce(facade: facade, now: now)

    #expect(summary.healthStatus == .healthy)
    #expect(summary.expiredLeaseCount == 0)
    #expect(summary.checkedAt == now)
}
