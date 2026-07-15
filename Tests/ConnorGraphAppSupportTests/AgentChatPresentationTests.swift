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

@Test func agentChatTurnTimelinePlacesTimestampAndProcessBetweenUserAndAssistant() {
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
        AgentMessage(id: "user-1", role: .user, content: "memory", createdAt: Date(timeIntervalSince1970: 1_000)),
        AgentMessage(id: "assistant-1", role: .assistant, content: "Answer", promptInspection: snapshot)
    ]

    let items = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false, now: Date(timeIntervalSince1970: 1_900))

    #expect(items.map(\.id) == ["timestamp-turn-1", "user-1", "process-assistant-1", "assistant-1"])
    #expect(items.map(\.kindLabel) == ["timestamp", "message", "process", "message"])
    #expect(items[0].timestamp?.text == "上午 8:16")
    #expect(items[2].process?.turnNumber == 1)
    #expect(items[2].process?.state == .completed)
    #expect(items[2].process?.summary == "第 1 轮 · 本轮提示词：摘要未包含 · 对话上下文 2 条 · 完整历史 1 条 · 约 30 tokens · 安全")
}

@Test func agentChatTurnTimestampFormatsTodayYesterdayAndOlderDates() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
    let now = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 13, hour: 15, minute: 21).date!
    let today = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 13, hour: 9, minute: 5).date!
    let yesterday = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 12, hour: 22, minute: 30).date!
    let olderSameYear = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 10, hour: 15, minute: 8).date!
    let olderPreviousYear = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2025, month: 12, day: 31, hour: 23, minute: 59).date!

    #expect(AgentChatTurnTimestampPresentation.text(for: today, now: now, calendar: calendar) == "上午 9:05")
    #expect(AgentChatTurnTimestampPresentation.text(for: yesterday, now: now, calendar: calendar) == "昨天 下午 10:30")
    #expect(AgentChatTurnTimestampPresentation.text(for: olderSameYear, now: now, calendar: calendar) == "6月10日 下午 3:08")
    #expect(AgentChatTurnTimestampPresentation.text(for: olderPreviousYear, now: now, calendar: calendar) == "2025年12月31日 下午 11:59")
}

@Test func agentChatTurnTimelineThrottlesTimestampsForShortConsecutiveUserTurns() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
    let now = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 25, hour: 12).date!
    let messages = [
        AgentMessage(id: "user-1", role: .user, content: "第一条", createdAt: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 25, hour: 10, minute: 0).date!),
        AgentMessage(id: "assistant-1", role: .assistant, content: "回复 1", createdAt: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 25, hour: 10, minute: 1).date!),
        AgentMessage(id: "user-2", role: .user, content: "连续追问", createdAt: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 25, hour: 10, minute: 3).date!),
        AgentMessage(id: "assistant-2", role: .assistant, content: "回复 2", createdAt: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 25, hour: 10, minute: 4).date!),
        AgentMessage(id: "user-3", role: .user, content: "间隔后再问", createdAt: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 25, hour: 10, minute: 8).date!)
    ]

    let items = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false, now: now, calendar: calendar)

    #expect(items.compactMap(\.timestamp?.text) == ["上午 10:00", "上午 10:08"])
    #expect(items.map(\.id) == ["timestamp-turn-1", "user-1", "process-assistant-1", "assistant-1", "user-2", "process-assistant-2", "assistant-2", "timestamp-turn-3", "user-3"])
}

@Test func agentChatTurnTimelineShowsTimestampWhenUserTurnCrossesDayEvenWithinInterval() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
    let now = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 25, hour: 1).date!
    let messages = [
        AgentMessage(id: "user-1", role: .user, content: "前一天", createdAt: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 24, hour: 23, minute: 59).date!),
        AgentMessage(id: "assistant-1", role: .assistant, content: "回复", createdAt: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 24, hour: 23, minute: 59, second: 30).date!),
        AgentMessage(id: "user-2", role: .user, content: "跨日后", createdAt: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 25, hour: 0, minute: 1).date!)
    ]

    let items = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false, now: now, calendar: calendar)

    #expect(items.compactMap(\.timestamp?.text) == ["昨天 下午 11:59", "上午 12:01"])
    #expect(items.map(\.id) == ["timestamp-turn-1", "user-1", "process-assistant-1", "assistant-1", "timestamp-turn-2", "user-2"])
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

    #expect(items.map(\.id) == ["timestamp-turn-1", "user-1", "process-assistant-1", "assistant-1", "user-2", "process-assistant-2", "assistant-2"])
    #expect(processes[0].fullConversationMessageCount == 1)
    #expect(processes[0].conversationHistory.map(\.message.content) == ["你好"])
    #expect(processes[0].sourceUserMessageID == "user-1")
    #expect(processes[0].assistantMessageID == "assistant-1")
    #expect(processes[1].fullConversationMessageCount == 3)
    #expect(processes[1].conversationHistory.map(\.message.content) == ["你好", "你好！", "我们会说些什么呢？"])
    #expect(processes[1].sourceUserMessageID == "user-2")
    #expect(processes[1].assistantMessageID == "assistant-2")
    #expect(processes[1].summary == "第 2 轮 · 本轮提示词：摘要未包含 · 对话上下文 2 条 · 完整历史 3 条 · 约 36 tokens · 安全")
}

@Test func agentChatTurnTimelinePlacesPendingProcessAfterOpenUserTurn() {
    let messages = [AgentMessage(id: "user-1", role: .user, content: "memory")]

    let items = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: true)

    #expect(items.map(\.id) == ["timestamp-turn-1", "user-1", "process-pending-assistant"])
    #expect(items.map(\.kindLabel) == ["timestamp", "message", "process"])
    #expect(items[2].process?.turnNumber == 1)
    #expect(items[2].process?.state == .running)
    #expect(items[2].process?.sourceUserMessageID == "user-1")
    #expect(items[2].process?.assistantMessageID == nil)
}

@Test func agentChatTurnTimelinePreservesOpenProcessAfterCancellation() {
    let messages = [AgentMessage(id: "user-1", role: .user, content: "cancel midway")]

    let items = AgentChatTurnTimelineItem.items(messages: messages, lastContext: nil, isSubmitting: false, preservesOpenProcess: true)

    #expect(items.map(\.id) == ["timestamp-turn-1", "user-1", "process-pending-assistant"])
    #expect(items.map(\.kindLabel) == ["timestamp", "message", "process"])
    #expect(items[2].process?.turnNumber == 1)
    #expect(items[2].process?.state == .cancelled)
    #expect(items[2].process?.title == "第 1 轮已取消")
    #expect(items[2].process?.sourceUserMessageID == "user-1")
    #expect(items[2].process?.assistantMessageID == nil)
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
    #expect(row.promptSnapshotText == nil)
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

@Test func agentEventPresenterHidesRenderedPromptSnapshotFromDebugDetail() {
    let presenter = AgentEventPresenter()
    let event = AgentPromptAssembledEvent(
        runID: "run-1",
        sessionID: "session-1",
        projectionMode: "legacySingleUserMessage",
        sections: [
            AgentPromptSectionSnapshot(
                id: "instruction",
                title: "Instruction",
                role: "system",
                characterCount: 42,
                estimatedTokenCount: 10
            )
        ],
        totalEstimatedTokenCount: 10,
        appliedTransformers: ["diagnostics"],
        renderedPromptSnapshot: "### SYSTEM\n## 用户基本信息\n- 称呼：段诗闻\n\n### USER\n用户询问姓名"
    )

    let row = presenter.presentation(for: .promptAssembled(event))

    #expect(row.title == "Prompt assembled")
    #expect(row.detail.contains("Projection: legacySingleUserMessage"))
    #expect(!row.detail.contains("### Rendered prompt snapshot"))
    #expect(!row.detail.contains("## 用户基本信息"))
    #expect(!row.detail.contains("- 称呼：段诗闻"))
}

@Test func agentEventPresenterSummarizesToolAndPermissionTimelineEvents() {
    let presenter = AgentEventPresenter()
    let toolCall = AgentToolCall(
        id: "tool-1",
        runID: "run-1",
        sessionID: "session-1",
        name: "Read",
        argumentsJSON: "{\"file_path\":\"README.md\"}"
    )
    let permission = AgentPermissionRequest(
        id: "permission-tool-1",
        runID: "run-1",
        sessionID: "session-1",
        capability: .readSession,
        toolName: "Read",
        payloadJSON: "{\"file_path\":\"README.md\"}"
    )
    let result = AgentToolResult(
        runID: "run-1",
        sessionID: "session-1",
        toolCallID: "tool-1",
        toolName: "Read",
        contentText: "README contents"
    )
    let failure = AgentToolFailure(
        runID: "run-1",
        sessionID: "session-1",
        toolCallID: "tool-1",
        toolName: "Write",
        message: "Denied by Connor policy"
    )

    let rows = [
        presenter.presentation(for: .toolRequested(toolCall)),
        presenter.presentation(for: .permissionRequested(permission)),
        presenter.presentation(for: .toolStarted(toolCall)),
        presenter.presentation(for: .toolFinished(result)),
        presenter.presentation(for: .toolFailed(failure))
    ]

    #expect(rows.map(\.title) == [
        "Tool requested: Read",
        "Permission requested: readSession",
        "Tool running: Read",
        "Tool finished: Read",
        "Tool failed: Write"
    ])
    #expect(rows.map(\.severity) == [.info, .warning, .info, .success, .error])
    #expect(rows[0].detail == "Call tool-1 · Arguments: {\"file_path\":\"README.md\"}")
    #expect(rows[1].detail == "Request permission-tool-1 · Tool: Read · Payload: {\"file_path\":\"README.md\"}")
    #expect(rows[2].detail == "Call tool-1 is executing.")
    #expect(rows[3].detail == "Call tool-1 · README contents")
    #expect(rows[4].detail == "Call tool-1 · Denied by Connor policy")
    #expect(rows.allSatisfy { $0.runID == "run-1" && $0.sessionID == "session-1" })
}

@Test func agentEventPresenterBoundsLargeToolOutputInTimelineDetail() {
    let content = String(repeating: "x", count: 10_000)
    let result = AgentToolResult(
        runID: "run-1",
        sessionID: "session-1",
        toolCallID: "tool-1",
        toolName: "Read",
        contentText: content
    )

    let row = AgentEventPresenter().presentation(for: .toolFinished(result))

    #expect(row.detail.hasPrefix("Call tool-1 · "))
    #expect(row.detail.hasSuffix("…"))
    #expect(row.detail.count < 300)
    #expect(!row.detail.contains(content))
}

@Test func agentEventPresenterSummarizesPermissionResolvedTimelineEvents() {
    let presenter = AgentEventPresenter()
    let approved = AgentPermissionDecision(
        requestID: "permission-approve-1",
        runID: "run-1",
        sessionID: "session-1",
        capability: .commitGraphWrite,
        outcome: .approved,
        reason: "Human approved graph commit"
    )
    let denied = AgentPermissionDecision(
        requestID: "permission-deny-1",
        runID: "run-1",
        sessionID: "session-1",
        capability: .externalNetwork,
        outcome: .denied,
        reason: "External network is blocked"
    )
    let needsApproval = AgentPermissionDecision(
        requestID: "permission-review-1",
        runID: "run-1",
        sessionID: "session-1",
        capability: .costlyModelCall,
        outcome: .needsApproval,
        reason: "Costly model call requires review"
    )

    let rows = [
        presenter.presentation(for: .permissionResolved(approved)),
        presenter.presentation(for: .permissionResolved(denied)),
        presenter.presentation(for: .permissionResolved(needsApproval))
    ]

    #expect(rows.map(\.title) == [
        "Permission approved: commitGraphWrite",
        "Permission denied: externalNetwork",
        "Permission needs approval: costlyModelCall"
    ])
    #expect(rows.map(\.severity) == [.success, .error, .warning])
    #expect(rows[0].detail == "Request permission-approve-1 · Human approved graph commit")
    #expect(rows[1].detail == "Request permission-deny-1 · External network is blocked")
    #expect(rows[2].detail == "Request permission-review-1 · Costly model call requires review")
    #expect(rows.allSatisfy { $0.runID == "run-1" && $0.sessionID == "session-1" })
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
