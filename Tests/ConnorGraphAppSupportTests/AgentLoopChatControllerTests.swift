import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

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
