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
    case cancelled
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
    public var sourceUserMessageID: String?
    public var assistantMessageID: String?
    public var activeSkillLabel: String?

    public init(completedAssistant row: AgentChatMessagePresentation, conversationHistory: [AgentChatMessagePresentation]) {
        self.id = "process-\(row.id)"
        self.turnNumber = row.turnNumber
        self.state = .completed
        self.fullConversationMessageCount = conversationHistory.count
        self.conversationHistory = conversationHistory
        let sourceUserMessage = conversationHistory.last(where: { $0.message.role == .user })
        self.sourceUserMessageID = sourceUserMessage?.id
        self.assistantMessageID = row.id
        self.activeSkillLabel = Self.activeSkillLabel(from: sourceUserMessage?.message.contextSnapshot)
        if let inspection = row.message.promptInspection {
            self.summary = Self.completedSummary(turnNumber: row.turnNumber, inspection: inspection, fullConversationMessageCount: conversationHistory.count)
        } else {
            self.summary = "第 \(row.turnNumber) 轮 · 已完成 · 完整历史 \(conversationHistory.count) 条"
        }
        self.title = "第 \(row.turnNumber) 轮处理详情"
        self.currentRequest = row.currentRequest
        self.assistantResponse = row.message.content
        self.promptSnapshotText = nil
        self.citationIDs = row.citationIDs
        self.expandedContextItems = row.expandedContextItems
    }

    public init(pending: AgentChatPendingAssistantPresentation, conversationHistory: [AgentChatMessagePresentation], state: AgentChatTurnProcessState = .running) {
        self.id = "process-\(pending.id)"
        self.turnNumber = pending.turnNumber
        self.state = state
        self.fullConversationMessageCount = conversationHistory.count
        self.conversationHistory = conversationHistory
        let sourceUserMessage = conversationHistory.last(where: { $0.message.role == .user })
        self.sourceUserMessageID = sourceUserMessage?.id
        self.assistantMessageID = nil
        self.activeSkillLabel = Self.activeSkillLabel(from: sourceUserMessage?.message.contextSnapshot)
        switch state {
        case .running:
            self.summary = "第 \(pending.turnNumber) 轮 · 正在处理 · 完整历史 \(conversationHistory.count) 条"
            self.title = "第 \(pending.turnNumber) 轮处理中…"
        case .cancelled:
            self.summary = "第 \(pending.turnNumber) 轮 · 已取消 · 已保留收到的运行记录"
            self.title = "第 \(pending.turnNumber) 轮已取消"
        case .completed:
            self.summary = "第 \(pending.turnNumber) 轮 · 已记录 · 完整历史 \(conversationHistory.count) 条"
            self.title = "第 \(pending.turnNumber) 轮处理详情"
        }
        self.currentRequest = conversationHistory.last(where: { $0.message.role == .user })?.message.content
        self.assistantResponse = nil
        self.promptSnapshotText = nil
        self.citationIDs = []
        self.expandedContextItems = []
    }

    private static func completedSummary(turnNumber: Int, inspection: AgentPromptInspectionSnapshot, fullConversationMessageCount: Int) -> String {
        "第 \(turnNumber) 轮 · 本轮提示词：摘要\(inspection.includesSummary ? "已包含" : "未包含") · 对话上下文 \(inspection.recentMessageCount) 条 · 完整历史 \(fullConversationMessageCount) 条 · 约 \(inspection.estimatedPromptTokenCount) tokens · \(AgentChatMessagePresentation.budgetStatusText(inspection.promptBudgetStatus))"
    }

    private static func activeSkillLabel(from contextSnapshot: String?) -> String? {
        guard let contextSnapshot else { return nil }
        let prefix = "Active skill:"
        guard let line = contextSnapshot
            .components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix) })
        else { return nil }
        let label = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }
}

public struct AgentChatTurnTimestampPresentation: Sendable, Equatable {
    public var date: Date
    public var text: String

    public init(date: Date, now: Date = Date(), calendar: Calendar = .current) {
        self.date = date
        self.text = Self.text(for: date, now: now, calendar: calendar)
    }

    public static func text(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return dayPeriodTimeFormatter.string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 " + dayPeriodTimeFormatter.string(from: date)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return monthDayTimeFormatter.string(from: date)
        }
        return fullDateTimeFormatter.string(from: date)
    }

    private static let dayPeriodTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()

    private static let monthDayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 a h:mm"
        return formatter
    }()

    private static let fullDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日 a h:mm"
        return formatter
    }()
}

public struct AgentChatTurnTimelineItem: Sendable, Equatable, Identifiable {
    private static let defaultTimestampDisplayInterval: TimeInterval = 5 * 60

    public var id: String
    public var message: AgentChatMessagePresentation?
    public var process: AgentChatTurnProcessPresentation?
    public var timestamp: AgentChatTurnTimestampPresentation?

    public var kindLabel: String {
        if message != nil { return "message" }
        if process != nil { return "process" }
        return "timestamp"
    }

    public static func message(_ message: AgentChatMessagePresentation) -> AgentChatTurnTimelineItem {
        AgentChatTurnTimelineItem(id: message.id, message: message, process: nil, timestamp: nil)
    }

    public static func process(_ process: AgentChatTurnProcessPresentation) -> AgentChatTurnTimelineItem {
        AgentChatTurnTimelineItem(id: process.id, message: nil, process: process, timestamp: nil)
    }

    public static func timestamp(turnNumber: Int, date: Date, now: Date = Date(), calendar: Calendar = .current) -> AgentChatTurnTimelineItem {
        AgentChatTurnTimelineItem(
            id: "timestamp-turn-\(turnNumber)",
            message: nil,
            process: nil,
            timestamp: AgentChatTurnTimestampPresentation(date: date, now: now, calendar: calendar)
        )
    }

    public static func items(messages: [AgentMessage], lastContext: AgentContext?, isSubmitting: Bool, preservesOpenProcess: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> [AgentChatTurnTimelineItem] {
        let rows = AgentChatMessagePresentation.rows(messages: messages, lastContext: lastContext)
        var items: [AgentChatTurnTimelineItem] = []
        var conversationHistory: [AgentChatMessagePresentation] = []
        var lastTimestampDate: Date?
        for row in rows {
            if row.message.role == .user,
               shouldInsertTimestamp(
                   for: row.message.createdAt,
                   lastTimestampDate: lastTimestampDate,
                   calendar: calendar,
                   minimumInterval: defaultTimestampDisplayInterval
               ) {
                items.append(.timestamp(turnNumber: row.turnNumber, date: row.message.createdAt, now: now, calendar: calendar))
                lastTimestampDate = row.message.createdAt
            }
            if row.message.role == .assistant {
                items.append(.process(AgentChatTurnProcessPresentation(completedAssistant: row, conversationHistory: conversationHistory)))
            }
            items.append(.message(row))
            conversationHistory.append(row)
        }
        if isSubmitting || preservesOpenProcess {
            let state: AgentChatTurnProcessState = isSubmitting ? .running : .cancelled
            items.append(.process(AgentChatTurnProcessPresentation(pending: AgentChatPendingAssistantPresentation(messages: messages), conversationHistory: conversationHistory, state: state)))
        }
        return items
    }

    private static func shouldInsertTimestamp(
        for date: Date,
        lastTimestampDate: Date?,
        calendar: Calendar,
        minimumInterval: TimeInterval
    ) -> Bool {
        guard let lastTimestampDate else { return true }
        if !calendar.isDate(date, inSameDayAs: lastTimestampDate) { return true }
        return date.timeIntervalSince(lastTimestampDate) >= minimumInterval
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
    public var attachments: [AgentMessageAttachmentRef]
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
        self.attachments = message.attachments
        if isLatestAssistantMessage {
            self.expandedContextItems = lastContext?.items ?? []
        } else {
            self.expandedContextItems = []
        }
        if message.role == .assistant, let inspection = message.promptInspection {
            self.turnMetadataSummary = Self.turnMetadataSummary(turnNumber: turnNumber, inspection: inspection)
            self.currentRequest = inspection.currentRequest
            self.promptSnapshotText = nil
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
