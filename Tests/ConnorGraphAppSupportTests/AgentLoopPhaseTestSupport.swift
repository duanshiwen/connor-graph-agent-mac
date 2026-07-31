import ConnorGraphAgent

func appSupportAutomaticPhaseResponse(
    for request: AgentModelRequest,
    nextResponse: AgentModelResponse? = nil
) -> AgentModelResponse? {
    guard request.auditContext.operation == "AgentLoopController.completeModelRequest" else { return nil }
    switch request.promptCacheContext?.phase {
    case .strategyResearch:
        return AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(
                id: "automatic-app-support-strategy",
                name: AgentPhaseToolContract.commitStrategyName,
                argumentsJSON: #"{"provisionalApproach":"test fixture approach","recommendedApproach":"test fixture approach","taskMode":"coding","memoryDecision":{"action":"skip","reason":"historyIndependentMechanicalOrCodingTask"}}"#
            )],
            finishReason: .toolCalls
        )
    case .taskExecution where nextResponse?.toolCalls.isEmpty != false:
        return AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(
                id: "automatic-app-support-final",
                name: AgentPhaseToolContract.prepareFinalOutputName,
                argumentsJSON: #"{"reason":"complete test response"}"#
            )],
            finishReason: .toolCalls
        )
    default:
        return nil
    }
}
