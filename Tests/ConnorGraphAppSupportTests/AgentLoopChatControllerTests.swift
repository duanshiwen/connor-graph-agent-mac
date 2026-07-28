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

private actor ProgressThenFinalProvider: AgentModelProvider {
    let modelID = "progress-then-final"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)
    private var callCount = 0

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        callCount += 1
        if callCount == 1 {
            return AgentModelResponse(
                text: nil,
                toolCalls: [AgentToolCall(id: "progress-call", name: "share_progress_update", argumentsJSON: #"{"message":"第一阶段已经完成，正在整理最终结果。"}"#)],
                finishReason: .toolCalls
            )
        }
        return AgentModelResponse(text: "最终结果")
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

@Test func loopChatControllerKeepsProgressAndFinalAsAssistantMessages() async throws {
    var registry = AgentToolRegistry()
    registry.register(ShareProgressUpdateTool())
    let loop = AgentLoopController(modelProvider: ProgressThenFinalProvider(), toolRegistry: registry)
    var controller = AgentLoopChatController(loopController: loop, session: AgentSession(id: "session-progress"))

    let response = try await controller.submit("完成一个分阶段任务")

    #expect(response.session.messages.map(\.role) == [.user, .assistant, .assistant])
    #expect(response.session.messages.map(\.content) == ["完成一个分阶段任务", "第一阶段已经完成，正在整理最终结果。", "最终结果"])
    #expect(response.session.messages.dropFirst().allSatisfy { $0.runID == response.events.first?.runID })
    #expect(response.session.messages.dropFirst().allSatisfy { $0.sessionID == "session-progress" })
}
