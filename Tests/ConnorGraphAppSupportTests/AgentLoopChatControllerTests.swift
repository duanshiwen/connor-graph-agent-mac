import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private actor FinalAnswerProvider: AgentModelProvider {
    let modelID = "final-answer"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        let final = AgentModelResponse(text: "Final loop answer", usage: AgentModelUsage(promptTokens: 10, completionTokens: 5))
        return appSupportAutomaticPhaseResponse(for: request, nextResponse: final) ?? final
    }
}

private actor ProgressThenFinalProvider: AgentModelProvider {
    let modelID = "progress-then-final"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)
    private var callCount = 0
    private var requests: [AgentModelRequest] = []

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        let nextResponse: AgentModelResponse = callCount == 0
            ? AgentModelResponse(
                text: nil,
                toolCalls: [AgentToolCall(id: "progress-call", name: "share_progress_update", argumentsJSON: #"{"message":"第一阶段已经完成，正在整理最终结果。"}"#)],
                finishReason: .toolCalls
            )
            : AgentModelResponse(text: "最终结果")
        if let automatic = appSupportAutomaticPhaseResponse(for: request, nextResponse: nextResponse) {
            return automatic
        }
        requests.append(request)
        callCount += 1
        if callCount == 1 {
            return nextResponse
        }
        return nextResponse
    }

    func recordedRequests() -> [AgentModelRequest] { requests }
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

@Test func loopChatControllerRemovesProgressAfterFinalAndOmitsItFromNextModelInput() async throws {
    var registry = AgentToolRegistry()
    registry.register(ShareProgressUpdateTool())
    let provider = ProgressThenFinalProvider()
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)
    var controller = AgentLoopChatController(loopController: loop, session: AgentSession(id: "session-progress"))

    let response = try await controller.submit("完成一个分阶段任务")
    let requests = await provider.recordedRequests()
    let secondRequest = try #require(requests.last)
    let toolCallingAssistant = try #require(secondRequest.messages.last(where: {
        $0.toolCalls?.contains { $0.name == ShareProgressUpdateTool.toolName } == true
    }))

    #expect(response.session.messages.map(\.role) == [.user, .assistant])
    #expect(response.session.messages.map(\.content) == ["完成一个分阶段任务", "最终结果"])
    #expect(response.session.messages.last?.runID == response.events.first?.runID)
    #expect(response.session.messages.last?.sessionID == "session-progress")
    #expect(toolCallingAssistant.content.isEmpty)
    #expect(toolCallingAssistant.toolCalls?.first?.argumentsJSON == #"{"message":""}"#)
}
