import Foundation
import Testing
@testable import ConnorGraphAgent
import ConnorGraphCore

@Test func assistantRunEnvelopeFreezesTurnIdentityAndRuntimeTime() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let request = AgentChatRequest(
        runID: "run-1",
        sessionID: "session-1",
        groupID: "group-1",
        userMessage: "prepare my day",
        permissionMode: .askToWrite
    )

    let envelope = AssistantRunEnvelope(
        request: request,
        now: date,
        timeZone: TimeZone(identifier: "Asia/Shanghai")!
    )

    #expect(envelope.runID == "run-1")
    #expect(envelope.userMessage == "prepare my day")
    #expect(envelope.startedAt == date)
    #expect(envelope.timeZoneIdentifier == "Asia/Shanghai")
}

@Test func assistantRunBudgetClampsUnsafeValues() {
    let budget = AssistantRunBudget(
        maximumModelTurns: 0,
        maximumToolCalls: 0,
        maximumContextPackTokens: 1,
        maximumVisibleToolResultTokens: 1
    )

    #expect(budget.maximumModelTurns == 1)
    #expect(budget.maximumToolCalls == 1)
    #expect(budget.maximumContextPackTokens == 256)
    #expect(budget.maximumVisibleToolResultTokens == 128)
}

@Test func assistantRunStartsAtDeterministicBootstrap() {
    let request = AgentChatRequest(sessionID: "session", userMessage: "hello")
    var state = AssistantRunState(envelope: AssistantRunEnvelope(request: request))

    #expect(state.stage == .bootstrap)
    state.transition(to: .decide)
    #expect(state.stage == .decide)
}
