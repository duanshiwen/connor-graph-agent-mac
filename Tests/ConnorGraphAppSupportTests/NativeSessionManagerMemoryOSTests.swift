import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private actor NativeSessionMemoryOSProvider: AgentModelProvider {
    let modelID = "native-session-memory-os"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        AgentModelResponse(text: "Native Memory OS assistant response", usage: AgentModelUsage(promptTokens: 4, completionTokens: 3))
    }
}

@Test func nativeSessionManagerPersistsMessagesThroughMemoryOSFacade() async throws {
    let graphStore = try SQLiteGraphKernelStore(path: ":memory:")
    try graphStore.migrate()
    let memoryStore = try SQLiteMemoryOSStore(path: ":memory:")
    try memoryStore.migrate()
    let facade = AppMemoryOSFacade(store: memoryStore)
    let repository = AppChatSessionRepository(store: graphStore)
    let loop = AgentLoopController(modelProvider: NativeSessionMemoryOSProvider(), toolRegistry: AgentToolRegistry())
    var manager = NativeSessionManager(
        backend: AgentLoopBackend(loopController: loop),
        sessionRepository: repository,
        session: AgentSession(id: "native-memory-os-session"),
        memoryOSFacade: facade
    )

    _ = try await manager.submit("请将 NativeSessionManager 接入 Memory OS")
    try await manager.flushMemoryOSIngestion()

    let summary = try facade.operationalSummary()
    #expect(summary.l0ProvenanceObjectCount == 2)
    #expect(summary.l1PendingCaptureCount == 2)
}
