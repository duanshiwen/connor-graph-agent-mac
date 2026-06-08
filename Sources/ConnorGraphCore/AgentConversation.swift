import Foundation

public enum AgentRole: String, Codable, Sendable, Equatable {
    case user
    case assistant
    case system
}

public enum AgentPromptBudgetStatus: String, Codable, Sendable, Equatable {
    case safe
    case warning
    case over
}

public struct AgentPromptInspectionSnapshot: Codable, Sendable, Equatable {
    public var includesSummary: Bool
    public var recentMessageCount: Int
    public var currentRequest: String
    public var renderedPrompt: String?
    public var renderedPromptCharacterCount: Int
    public var estimatedPromptTokenCount: Int
    public var promptBudgetStatus: AgentPromptBudgetStatus

    public init(
        includesSummary: Bool,
        recentMessageCount: Int,
        currentRequest: String,
        renderedPrompt: String? = nil,
        renderedPromptCharacterCount: Int = 0,
        estimatedPromptTokenCount: Int = 0,
        promptBudgetStatus: AgentPromptBudgetStatus = .safe
    ) {
        self.includesSummary = includesSummary
        self.recentMessageCount = recentMessageCount
        self.currentRequest = currentRequest
        self.renderedPrompt = renderedPrompt
        self.renderedPromptCharacterCount = renderedPromptCharacterCount
        self.estimatedPromptTokenCount = estimatedPromptTokenCount
        self.promptBudgetStatus = promptBudgetStatus
    }
}

public struct AgentMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var role: AgentRole
    public var content: String
    public var createdAt: Date
    public var citations: [String]
    public var contextSnapshot: String?
    public var promptInspection: AgentPromptInspectionSnapshot?

    public init(
        id: String = UUID().uuidString,
        role: AgentRole,
        content: String,
        createdAt: Date = Date(),
        citations: [String] = [],
        contextSnapshot: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.citations = citations
        self.contextSnapshot = contextSnapshot
        self.promptInspection = nil
    }

    public init(
        id: String = UUID().uuidString,
        role: AgentRole,
        content: String,
        createdAt: Date = Date(),
        citations: [String] = [],
        contextSnapshot: String? = nil,
        promptInspection: AgentPromptInspectionSnapshot?
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.citations = citations
        self.contextSnapshot = contextSnapshot
        self.promptInspection = promptInspection
    }
}

public struct AgentSessionSummaryFreshness: Sendable, Equatable {
    public var coveredMessageCount: Int
    public var currentMessageCount: Int
    public var uncoveredMessageCount: Int
    public var isFresh: Bool

    public init(coveredMessageCount: Int, currentMessageCount: Int) {
        self.coveredMessageCount = coveredMessageCount
        self.currentMessageCount = currentMessageCount
        self.uncoveredMessageCount = max(0, currentMessageCount - coveredMessageCount)
        self.isFresh = uncoveredMessageCount == 0
    }
}

public struct AgentSessionSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionID: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sourceMessageCount: Int
    public var lastMessageID: String?

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        sourceMessageCount: Int,
        lastMessageID: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.sourceMessageCount = sourceMessageCount
        self.lastMessageID = lastMessageID
    }

    public func freshness(for session: AgentSession) -> AgentSessionSummaryFreshness {
        AgentSessionSummaryFreshness(
            coveredMessageCount: sourceMessageCount,
            currentMessageCount: session.messages.count
        )
    }
}

public struct AgentSession: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var messages: [AgentMessage]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String = "New Chat",
        messages: [AgentMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    @discardableResult
    public mutating func appendUserMessage(_ content: String) -> AgentMessage {
        let message = AgentMessage(role: .user, content: content)
        messages.append(message)
        updatedAt = message.createdAt
        if title == "New Chat" {
            title = String(content.prefix(40))
        }
        return message
    }

    @discardableResult
    public mutating func appendAssistantMessage(
        _ content: String,
        citations: [String] = [],
        contextSnapshot: String? = nil,
        promptInspection: AgentPromptInspectionSnapshot? = nil
    ) -> AgentMessage {
        let message = AgentMessage(
            role: .assistant,
            content: content,
            citations: citations,
            contextSnapshot: contextSnapshot,
            promptInspection: promptInspection
        )
        messages.append(message)
        updatedAt = message.createdAt
        return message
    }
}
