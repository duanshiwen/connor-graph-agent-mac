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

@Test func memoryOSChatIngestionIncludesStructuredPersonReferences() throws {
    let memoryStore = try SQLiteMemoryOSStore(path: ":memory:")
    try memoryStore.migrate()
    let facade = AppMemoryOSFacade(store: memoryStore)
    let reference = PersonReference(
        personID: ContactID(rawValue: "person-duan-leiqiang"),
        displayName: "段磊强",
        mentionText: "@段磊强",
        status: .active,
        memoryEntityID: "memory-person-duan"
    )
    let formatter = MemoryOSPersonReferenceContextFormatter()

    let result = try facade.ingestChatMessage(
        messageID: "message-person-ref",
        sessionID: "session-person-ref",
        role: "user",
        content: formatter.content("请整理和 @段磊强 相关的事项", personReferences: [reference]),
        occurredAt: Date(timeIntervalSince1970: 1_000),
        metadata: formatter.metadata(personReferences: [reference])
    )

    let provenance = try #require(result.provenanceObject)
    let captureEvent = try #require(result.captureEvent)
    #expect(provenance.content.contains("Referenced People in Chat Message"))
    #expect(provenance.content.contains("person_id: person-duan-leiqiang"))
    #expect(provenance.content.contains("memory_entity_id: memory-person-duan"))
    #expect(provenance.metadata["person_reference_ids"] == "person-duan-leiqiang")
    #expect(captureEvent.metadata["person_reference_ids"] == "person-duan-leiqiang")
    #expect(captureEvent.metadata["person_references_json"]?.contains("person-duan-leiqiang") == true)
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
