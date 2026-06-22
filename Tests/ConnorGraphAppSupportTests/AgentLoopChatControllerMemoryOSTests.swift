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
