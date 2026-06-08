import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

@Test func agentChatSessionPresentationFormatsRelativeUpdatedTime() {
    let session = AgentSession(
        id: "session-1",
        title: "Prompt inspection timeline",
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_900)
    )

    let row = AgentChatSessionPresentation(session: session, now: Date(timeIntervalSince1970: 2_800))

    #expect(row.id == "session-1")
    #expect(row.title == "Prompt inspection timeline")
    #expect(row.relativeUpdatedTime == "15 分钟")
}

@Test func agentChatMessagePresentationAssignsTurnNumbersByUserAssistantPairs() {
    let messages = [
        AgentMessage(id: "user-1", role: .user, content: "First"),
        AgentMessage(id: "assistant-1", role: .assistant, content: "Answer 1"),
        AgentMessage(id: "user-2", role: .user, content: "Second"),
        AgentMessage(id: "assistant-2", role: .assistant, content: "Answer 2")
    ]

    let rows = AgentChatMessagePresentation.rows(messages: messages, lastContext: nil)

    #expect(rows.map(\.turnNumber) == [1, 1, 2, 2])
    #expect(rows.map(\.roleLabel) == ["用户", "助手", "用户", "助手"])
}

@Test func agentChatTurnTimelinePlacesProcessBetweenUserAndAssistant() {
    let snapshot = AgentPromptInspectionSnapshot(
        includesSummary: false,
        recentMessageCount: 2,
        currentRequest: "memory",
        renderedPrompt: "Prompt",
        renderedPromptCharacterCount: 120,
        estimatedPromptTokenCount: 30,
        promptBudgetStatus: .safe
    )
    let messages = [
        AgentMessage(id: "user-1", role: .user, content: "memory"),
        AgentMessage(id: "assistant-1", role: .assistant, content: "Answer", promptInspection: snapshot)
    ]

    let items = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false)

    #expect(items.map(\.id) == ["user-1", "process-assistant-1", "assistant-1"])
    #expect(items.map(\.kindLabel) == ["message", "process", "message"])
    #expect(items[1].process?.turnNumber == 1)
    #expect(items[1].process?.state == .completed)
    #expect(items[1].process?.summary == "第 1 轮 · 本轮提示词：摘要未包含 · 对话上下文 2 条 · 完整历史 1 条 · 约 30 tokens · 安全")
}

@Test func agentChatTurnTimelineCarriesFullConversationHistoryForEachProcess() {
    let firstSnapshot = AgentPromptInspectionSnapshot(
        includesSummary: false,
        recentMessageCount: 0,
        currentRequest: "你好",
        renderedPrompt: "你好",
        renderedPromptCharacterCount: 8,
        estimatedPromptTokenCount: 2,
        promptBudgetStatus: .safe
    )
    let secondSnapshot = AgentPromptInspectionSnapshot(
        includesSummary: false,
        recentMessageCount: 2,
        currentRequest: "我们会说些什么呢？",
        renderedPrompt: "Prompt",
        renderedPromptCharacterCount: 144,
        estimatedPromptTokenCount: 36,
        promptBudgetStatus: .safe
    )
    let messages = [
        AgentMessage(id: "user-1", role: .user, content: "你好"),
        AgentMessage(id: "assistant-1", role: .assistant, content: "你好！", promptInspection: firstSnapshot),
        AgentMessage(id: "user-2", role: .user, content: "我们会说些什么呢？"),
        AgentMessage(id: "assistant-2", role: .assistant, content: "我们可以聊图谱。", promptInspection: secondSnapshot)
    ]

    let items = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false)
    let processes = items.compactMap(\.process)

    #expect(items.map(\.id) == ["user-1", "process-assistant-1", "assistant-1", "user-2", "process-assistant-2", "assistant-2"])
    #expect(processes[0].fullConversationMessageCount == 1)
    #expect(processes[0].conversationHistory.map(\.message.content) == ["你好"])
    #expect(processes[1].fullConversationMessageCount == 3)
    #expect(processes[1].conversationHistory.map(\.message.content) == ["你好", "你好！", "我们会说些什么呢？"])
    #expect(processes[1].summary == "第 2 轮 · 本轮提示词：摘要未包含 · 对话上下文 2 条 · 完整历史 3 条 · 约 36 tokens · 安全")
}

@Test func agentChatTurnTimelinePlacesPendingProcessAfterOpenUserTurn() {
    let messages = [AgentMessage(id: "user-1", role: .user, content: "memory")]

    let items = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: true)

    #expect(items.map(\.id) == ["user-1", "process-pending-assistant"])
    #expect(items.map(\.kindLabel) == ["message", "process"])
    #expect(items[1].process?.turnNumber == 1)
    #expect(items[1].process?.state == .running)
}

@Test func agentChatAssistantTurnMetadataSummarizesPromptInspection() {
    let snapshot = AgentPromptInspectionSnapshot(
        includesSummary: true,
        recentMessageCount: 4,
        currentRequest: "What changed?",
        renderedPrompt: "Rendered prompt",
        renderedPromptCharacterCount: 400,
        estimatedPromptTokenCount: 100,
        promptBudgetStatus: .safe
    )
    let message = AgentMessage(id: "assistant-1", role: .assistant, content: "Answer", promptInspection: snapshot)

    let row = AgentChatMessagePresentation(message: message, turnNumber: 3, isLatestAssistantMessage: true, lastContext: nil)

    #expect(row.turnMetadataSummary == "第 3 轮 · 本轮提示词：摘要已包含 · 对话上下文 4 条 · 约 100 tokens · 安全")
    #expect(row.promptSnapshotText == "Rendered prompt")
    #expect(row.currentRequest == "What changed?")
}

@Test func agentChatPendingAssistantPresentationUsesOpenUserTurn() {
    let messages = [
        AgentMessage(id: "user-1", role: .user, content: "First"),
        AgentMessage(id: "assistant-1", role: .assistant, content: "Answer 1"),
        AgentMessage(id: "user-2", role: .user, content: "Second")
    ]

    let pending = AgentChatPendingAssistantPresentation(messages: messages)

    #expect(pending.id == "pending-assistant")
    #expect(pending.turnNumber == 2)
    #expect(pending.title == "助手正在思考…")
    #expect(pending.processingSummary == "正在准备图谱上下文和提示词…")
}

@Test func agentChatMessagePresentationShowsLastContextOnlyForLatestAssistantMessage() {
    let context = AgentContext(
        query: "memory",
        items: [AgentContextItem(sourceID: "node:memory", kind: .node, content: "Graph memory context", reason: "matched")]
    )
    let olderAssistant = AgentMessage(id: "assistant-1", role: .assistant, content: "Old", citations: ["node:old"])
    let latestAssistant = AgentMessage(id: "assistant-2", role: .assistant, content: "New", citations: ["node:memory"])

    let older = AgentChatMessagePresentation(message: olderAssistant, turnNumber: 1, isLatestAssistantMessage: false, lastContext: context)
    let latest = AgentChatMessagePresentation(message: latestAssistant, turnNumber: 2, isLatestAssistantMessage: true, lastContext: context)

    #expect(older.citationIDs == ["node:old"])
    #expect(older.expandedContextItems.isEmpty)
    #expect(latest.citationIDs == ["node:memory"])
    #expect(latest.expandedContextItems.map(\.sourceID) == ["node:memory"])
}
