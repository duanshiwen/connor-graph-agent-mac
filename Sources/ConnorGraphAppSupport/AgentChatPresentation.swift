import Foundation
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch

public struct AgentChatSessionPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var relativeUpdatedTime: String
    public var statusText: String
    public var status: AgentSessionStatus
    public var labels: [AgentSessionLabel]
    public var isArchived: Bool
    public var isFlagged: Bool
    public var messageCount: Int

    public init(session: AgentSession, now: Date = Date()) {
        self.id = session.id
        self.title = session.title.isEmpty || session.title == "New Chat" ? "新对话" : session.title
        self.relativeUpdatedTime = Self.relativeTime(from: session.updatedAt, to: now)
        self.status = session.governance.status
        self.statusText = session.governance.status.displayName
        self.labels = session.governance.labels
        self.isArchived = session.governance.isArchived
        self.isFlagged = session.governance.isFlagged
        self.messageCount = session.messages.count
    }

    private static func relativeTime(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时" }
        let days = hours / 24
        if days < 7 { return "\(days) 天" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks) 周" }
        return "\(days) 天"
    }
}

public enum AgentChatTurnProcessState: String, Sendable, Equatable {
    case running
    case completed
}

public struct AgentChatTurnProcessPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var turnNumber: Int
    public var state: AgentChatTurnProcessState
    public var summary: String
    public var title: String
    public var currentRequest: String?
    public var assistantResponse: String?
    public var promptSnapshotText: String?
    public var citationIDs: [String]
    public var expandedContextItems: [AgentContextItem]
    public var fullConversationMessageCount: Int
    public var conversationHistory: [AgentChatMessagePresentation]

    public init(completedAssistant row: AgentChatMessagePresentation, conversationHistory: [AgentChatMessagePresentation]) {
        self.id = "process-\(row.id)"
        self.turnNumber = row.turnNumber
        self.state = .completed
        self.fullConversationMessageCount = conversationHistory.count
        self.conversationHistory = conversationHistory
        if let inspection = row.message.promptInspection {
            self.summary = Self.completedSummary(turnNumber: row.turnNumber, inspection: inspection, fullConversationMessageCount: conversationHistory.count)
        } else {
            self.summary = "第 \(row.turnNumber) 轮 · 已完成 · 完整历史 \(conversationHistory.count) 条"
        }
        self.title = "第 \(row.turnNumber) 轮处理详情"
        self.currentRequest = row.currentRequest
        self.assistantResponse = row.message.content
        self.promptSnapshotText = row.promptSnapshotText
        self.citationIDs = row.citationIDs
        self.expandedContextItems = row.expandedContextItems
    }

    public init(pending: AgentChatPendingAssistantPresentation, conversationHistory: [AgentChatMessagePresentation]) {
        self.id = "process-\(pending.id)"
        self.turnNumber = pending.turnNumber
        self.state = .running
        self.fullConversationMessageCount = conversationHistory.count
        self.conversationHistory = conversationHistory
        self.summary = "第 \(pending.turnNumber) 轮 · 正在处理 · 完整历史 \(conversationHistory.count) 条"
        self.title = "第 \(pending.turnNumber) 轮处理中…"
        self.currentRequest = conversationHistory.last(where: { $0.message.role == .user })?.message.content
        self.assistantResponse = nil
        self.promptSnapshotText = nil
        self.citationIDs = []
        self.expandedContextItems = []
    }

    private static func completedSummary(turnNumber: Int, inspection: AgentPromptInspectionSnapshot, fullConversationMessageCount: Int) -> String {
        "第 \(turnNumber) 轮 · 本轮提示词：摘要\(inspection.includesSummary ? "已包含" : "未包含") · 对话上下文 \(inspection.recentMessageCount) 条 · 完整历史 \(fullConversationMessageCount) 条 · 约 \(inspection.estimatedPromptTokenCount) tokens · \(AgentChatMessagePresentation.budgetStatusText(inspection.promptBudgetStatus))"
    }
}

public struct AgentChatTurnTimelineItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var message: AgentChatMessagePresentation?
    public var process: AgentChatTurnProcessPresentation?

    public var kindLabel: String {
        process == nil ? "message" : "process"
    }

    public static func message(_ message: AgentChatMessagePresentation) -> AgentChatTurnTimelineItem {
        AgentChatTurnTimelineItem(id: message.id, message: message, process: nil)
    }

    public static func process(_ process: AgentChatTurnProcessPresentation) -> AgentChatTurnTimelineItem {
        AgentChatTurnTimelineItem(id: process.id, message: nil, process: process)
    }

    public static func items(messages: [AgentMessage], lastContext: AgentContext?, isSubmitting: Bool) -> [AgentChatTurnTimelineItem] {
        let rows = AgentChatMessagePresentation.rows(messages: messages, lastContext: lastContext)
        var items: [AgentChatTurnTimelineItem] = []
        var conversationHistory: [AgentChatMessagePresentation] = []
        for row in rows {
            if row.message.role == .assistant {
                items.append(.process(AgentChatTurnProcessPresentation(completedAssistant: row, conversationHistory: conversationHistory)))
            }
            items.append(.message(row))
            conversationHistory.append(row)
        }
        if isSubmitting {
            items.append(.process(AgentChatTurnProcessPresentation(pending: AgentChatPendingAssistantPresentation(messages: messages), conversationHistory: conversationHistory)))
        }
        return items
    }
}

public struct AgentChatPendingAssistantPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var turnNumber: Int
    public var title: String
    public var processingSummary: String

    public init(messages: [AgentMessage]) {
        self.id = "pending-assistant"
        self.turnNumber = Self.pendingTurnNumber(messages: messages)
        self.title = "助手正在思考…"
        self.processingSummary = "正在准备图谱上下文和提示词…"
    }

    private static func pendingTurnNumber(messages: [AgentMessage]) -> Int {
        var currentTurn = 0
        var hasOpenUserTurn = false
        for message in messages {
            switch message.role {
            case .user:
                currentTurn += 1
                hasOpenUserTurn = true
            case .assistant:
                if !hasOpenUserTurn {
                    currentTurn += 1
                }
                hasOpenUserTurn = false
            case .system:
                if currentTurn == 0 { currentTurn = 1 }
            }
        }
        if hasOpenUserTurn { return max(currentTurn, 1) }
        return max(currentTurn + 1, 1)
    }
}

public struct AgentChatMessagePresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var message: AgentMessage
    public var turnNumber: Int
    public var roleLabel: String
    public var isLatestAssistantMessage: Bool
    public var turnMetadataSummary: String?
    public var currentRequest: String?
    public var promptSnapshotText: String?
    public var citationIDs: [String]
    public var expandedContextItems: [AgentContextItem]

    public init(
        message: AgentMessage,
        turnNumber: Int,
        isLatestAssistantMessage: Bool,
        lastContext: AgentContext?
    ) {
        self.id = message.id
        self.message = message
        self.turnNumber = turnNumber
        self.roleLabel = Self.makeRoleLabel(for: message.role)
        self.isLatestAssistantMessage = isLatestAssistantMessage
        self.citationIDs = message.citations
        if isLatestAssistantMessage {
            self.expandedContextItems = lastContext?.items ?? []
        } else {
            self.expandedContextItems = []
        }
        if message.role == .assistant, let inspection = message.promptInspection {
            self.turnMetadataSummary = Self.turnMetadataSummary(turnNumber: turnNumber, inspection: inspection)
            self.currentRequest = inspection.currentRequest
            self.promptSnapshotText = inspection.renderedPrompt
        } else {
            self.turnMetadataSummary = nil
            self.currentRequest = nil
            self.promptSnapshotText = nil
        }
    }

    public static func rows(messages: [AgentMessage], lastContext: AgentContext?) -> [AgentChatMessagePresentation] {
        let latestAssistantID = messages.last(where: { $0.role == .assistant })?.id
        var currentTurn = 0
        var hasOpenUserTurn = false
        return messages.map { message in
            switch message.role {
            case .user:
                currentTurn += 1
                hasOpenUserTurn = true
            case .assistant:
                if !hasOpenUserTurn {
                    currentTurn += 1
                }
                hasOpenUserTurn = false
            case .system:
                if currentTurn == 0 { currentTurn = 1 }
            }
            return AgentChatMessagePresentation(
                message: message,
                turnNumber: max(currentTurn, 1),
                isLatestAssistantMessage: message.id == latestAssistantID,
                lastContext: lastContext
            )
        }
    }

    public static func turnMetadataSummary(turnNumber: Int, inspection: AgentPromptInspectionSnapshot) -> String {
        "第 \(turnNumber) 轮 · 本轮提示词：摘要\(inspection.includesSummary ? "已包含" : "未包含") · 对话上下文 \(inspection.recentMessageCount) 条 · 约 \(inspection.estimatedPromptTokenCount) tokens · \(budgetStatusText(inspection.promptBudgetStatus))"
    }

    public static func budgetStatusText(_ status: AgentPromptBudgetStatus) -> String {
        switch status {
        case .safe: return "安全"
        case .warning: return "警告"
        case .over: return "超限"
        }
    }

    private static func makeRoleLabel(for role: AgentRole) -> String {
        switch role {
        case .user: return "用户"
        case .assistant: return "助手"
        case .system: return "系统"
        }
    }
}
