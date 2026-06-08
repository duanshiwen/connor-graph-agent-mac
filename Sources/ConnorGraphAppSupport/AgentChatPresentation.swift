import Foundation
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch

public struct AgentChatSessionPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var relativeUpdatedTime: String

    public init(session: AgentSession, now: Date = Date()) {
        self.id = session.id
        self.title = session.title.isEmpty ? "New Chat" : session.title
        self.relativeUpdatedTime = Self.relativeTime(from: session.updatedAt, to: now)
    }

    private static func relativeTime(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }
        return "\(days)d"
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
        "Turn \(turnNumber) · summary \(inspection.includesSummary ? "included" : "not included") · recent \(inspection.recentMessageCount) · ~\(inspection.estimatedPromptTokenCount) tokens · \(budgetStatusText(inspection.promptBudgetStatus))"
    }

    public static func budgetStatusText(_ status: AgentPromptBudgetStatus) -> String {
        switch status {
        case .safe: return "safe"
        case .warning: return "warning"
        case .over: return "over"
        }
    }

    private static func makeRoleLabel(for role: AgentRole) -> String {
        switch role {
        case .user: return "User"
        case .assistant: return "Assistant"
        case .system: return "System"
        }
    }
}
