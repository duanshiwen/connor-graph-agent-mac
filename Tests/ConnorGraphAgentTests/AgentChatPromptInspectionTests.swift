import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Test func agentChatPromptInspectionDescribesSummaryRecentMessagesAndCurrentRequest() {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "Summary content",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let context = AgentChatPromptContext(
        userPrompt: "What next?",
        sessionSummary: summary,
        recentMessages: [
            AgentMessage(id: "message-1", role: .user, content: "Earlier question"),
            AgentMessage(id: "message-2", role: .assistant, content: "Earlier answer")
        ]
    )

    let inspection: AgentChatPromptInspection = context.inspection

    #expect(inspection.includesSummary)
    #expect(inspection.recentMessageCount == 2)
    #expect(inspection.currentRequest == "What next?")
    #expect(inspection.renderedPrompt.contains("Previous session summary:"))
    #expect(inspection.renderedPrompt.contains("Recent conversation:"))
    #expect(inspection.renderedPrompt.contains("Current user request:"))
}

@Test func agentChatPromptInspectionSkipsEmptySummaryContent() {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "  \n  ",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let context = AgentChatPromptContext(userPrompt: "What next?", sessionSummary: summary)

    let inspection = context.inspection

    #expect(!inspection.includesSummary)
}

@Test func agentChatPromptInspectionReportsZeroRecentMessagesWhenNoneArePresent() {
    let context = AgentChatPromptContext(userPrompt: "What next?")

    let inspection = context.inspection

    #expect(inspection.recentMessageCount == 0)
}

@Test func agentChatPromptInspectionConvertsToCoreSnapshot() {
    let inspection = AgentChatPromptInspection(
        includesSummary: true,
        recentMessageCount: 2,
        currentRequest: "What next?",
        renderedPrompt: "Rendered prompt"
    )

    let snapshot = AgentPromptInspectionSnapshot(inspection)

    #expect(snapshot.includesSummary)
    #expect(snapshot.recentMessageCount == 2)
    #expect(snapshot.currentRequest == "What next?")
    #expect(snapshot.renderedPrompt == "Rendered prompt")
}
