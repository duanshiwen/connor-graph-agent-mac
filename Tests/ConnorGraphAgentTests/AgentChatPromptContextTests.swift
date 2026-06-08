import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Test func agentChatPromptContextReturnsRawPromptWithoutSummaryOrRecentMessages() {
    let context = AgentChatPromptContext(userPrompt: "What next?")

    #expect(context.renderedPrompt == "What next?")
}

@Test func agentChatPromptContextRendersSessionSummary() {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "We planned the next implementation phase.",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let context = AgentChatPromptContext(userPrompt: "What next?", sessionSummary: summary)

    #expect(context.renderedPrompt.contains("Previous session summary:"))
    #expect(context.renderedPrompt.contains("We planned the next implementation phase."))
    #expect(context.renderedPrompt.contains("Current user request:"))
    #expect(context.renderedPrompt.contains("What next?"))
}

@Test func agentChatPromptContextRendersRecentConversation() {
    let context = AgentChatPromptContext(
        userPrompt: "What next?",
        recentMessages: [
            AgentMessage(id: "message-1", role: .user, content: "Earlier question"),
            AgentMessage(id: "message-2", role: .assistant, content: "Earlier answer")
        ]
    )

    #expect(context.renderedPrompt.contains("Recent conversation:"))
    #expect(context.renderedPrompt.contains("User: Earlier question"))
    #expect(context.renderedPrompt.contains("Assistant: Earlier answer"))
    #expect(context.renderedPrompt.contains("Current user request:"))
    #expect(context.renderedPrompt.contains("What next?"))
}

@Test func agentChatPromptContextOrdersSummaryBeforeRecentConversationBeforeCurrentRequest() {
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
        recentMessages: [AgentMessage(id: "message-1", role: .user, content: "Earlier question")]
    )

    let rendered = context.renderedPrompt
    let summaryRange = rendered.range(of: "Previous session summary:")
    let recentRange = rendered.range(of: "Recent conversation:")
    let currentRange = rendered.range(of: "Current user request:")

    #expect(summaryRange != nil)
    #expect(recentRange != nil)
    #expect(currentRange != nil)
    #expect(summaryRange!.lowerBound < recentRange!.lowerBound)
    #expect(recentRange!.lowerBound < currentRange!.lowerBound)
}

@Test func agentChatPromptContextSkipsEmptySummaryContent() {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "   \n  ",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let context = AgentChatPromptContext(userPrompt: "What next?", sessionSummary: summary)

    #expect(!context.renderedPrompt.contains("Previous session summary:"))
    #expect(context.renderedPrompt == "What next?")
}
