import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

private actor FinalAnswerProvider: AgentModelProvider {
    let modelID = "final-answer"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        AgentModelResponse(text: "Final loop answer", usage: AgentModelUsage(promptTokens: 10, completionTokens: 5))
    }
}

@Test func loopChatControllerAppendsUserAndAssistantAndCapturesEvents() async throws {
    let loop = AgentLoopController(modelProvider: FinalAnswerProvider(), toolRegistry: AgentToolRegistry())
    var controller = AgentLoopChatController(loopController: loop, session: AgentSession(id: "session-loop"))

    let response = try await controller.submit("Hello")

    #expect(response.session.messages.map(\.role) == [.user, .assistant])
    #expect(response.session.messages.last?.content == "Final loop answer")
    #expect(response.events.map(\.kind).contains(.runStarted))
    #expect(response.events.map(\.kind).contains(.runCompleted))
    #expect(controller.eventPresentations.contains(where: { $0.title == "Run completed" }))
}

@Test func loopChatControllerPersistsMemoryStagingBufferWhenRepositoryIsConfigured() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    let store = try SQLiteGraphKernelStore(path: databaseURL.path)
    try store.migrate()
    let stagingRepository = AppMemoryStagingBufferRepository(store: store)
    let loop = AgentLoopController(modelProvider: FinalAnswerProvider(), toolRegistry: AgentToolRegistry())
    var controller = AgentLoopChatController(
        loopController: loop,
        session: AgentSession(id: "session-memory-loop"),
        memoryStagingRepository: stagingRepository
    )

    _ = try await controller.submit("记住这个偏好")

    let buffer = try stagingRepository.loadBuffer(sessionID: "session-memory-loop")
    #expect(buffer?.pendingBundles.count == 1)
    #expect(buffer?.pendingBundles.first?.status == .closed)
    #expect(buffer?.pendingBundles.first?.userMessages.first?.content == "记住这个偏好")
    #expect(buffer?.pendingBundles.first?.assistantMessage?.content == "Final loop answer")
}
