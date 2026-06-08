import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Test func agentSessionSummaryPolicyReturnsNilWhenSummaryIsMissing() {
    let policy = AgentSessionSummaryPolicy()
    let session = AgentSession(id: "session-1")

    let selected = policy.summaryForContext(nil, session: session)

    #expect(selected == nil)
}

@Test func agentSessionSummaryPolicyAllowsFreshSummary() {
    let policy = AgentSessionSummaryPolicy()
    let session = AgentSession(
        id: "session-1",
        messages: [
            AgentMessage(id: "message-1", role: .user, content: "First"),
            AgentMessage(id: "message-2", role: .assistant, content: "Second")
        ]
    )
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "Fresh summary",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )

    let selected = policy.summaryForContext(summary, session: session)

    #expect(selected == summary)
}

@Test func agentSessionSummaryPolicyRejectsStaleSummary() {
    let policy = AgentSessionSummaryPolicy()
    let session = AgentSession(
        id: "session-1",
        messages: [
            AgentMessage(id: "message-1", role: .user, content: "First"),
            AgentMessage(id: "message-2", role: .assistant, content: "Second"),
            AgentMessage(id: "message-3", role: .user, content: "Third")
        ]
    )
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "Stale summary",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )

    let selected = policy.summaryForContext(summary, session: session)

    #expect(selected == nil)
}
