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
    public var attachments: [AgentMessageAttachmentRef]

    public init(
        id: String = UUID().uuidString,
        role: AgentRole,
        content: String,
        createdAt: Date = Date(),
        citations: [String] = [],
        contextSnapshot: String? = nil
    ) {
        self.init(
            id: id,
            role: role,
            content: content,
            createdAt: createdAt,
            citations: citations,
            contextSnapshot: contextSnapshot,
            attachments: []
        )
    }

    public init(
        id: String = UUID().uuidString,
        role: AgentRole,
        content: String,
        createdAt: Date = Date(),
        citations: [String] = [],
        contextSnapshot: String? = nil,
        attachments: [AgentMessageAttachmentRef]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.citations = citations
        self.contextSnapshot = contextSnapshot
        self.promptInspection = nil
        self.attachments = attachments
    }

    public init(
        id: String = UUID().uuidString,
        role: AgentRole,
        content: String,
        createdAt: Date = Date(),
        citations: [String] = [],
        contextSnapshot: String? = nil,
        attachments: [AgentMessageAttachmentRef] = [],
        promptInspection: AgentPromptInspectionSnapshot?
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.citations = citations
        self.contextSnapshot = contextSnapshot
        self.promptInspection = promptInspection
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
        case citations
        case contextSnapshot
        case promptInspection
        case attachments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(AgentRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        citations = try container.decodeIfPresent([String].self, forKey: .citations) ?? []
        contextSnapshot = try container.decodeIfPresent(String.self, forKey: .contextSnapshot)
        promptInspection = try container.decodeIfPresent(AgentPromptInspectionSnapshot.self, forKey: .promptInspection)
        attachments = try container.decodeIfPresent([AgentMessageAttachmentRef].self, forKey: .attachments) ?? []
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
    public var governance: AgentSessionGovernanceMetadata

    public init(
        id: String = UUID().uuidString,
        title: String = "New Chat",
        messages: [AgentMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        governance: AgentSessionGovernanceMetadata = .default
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.governance = governance
    }

    public var status: AgentSessionStatus {
        get { governance.status }
        set { governance.status = newValue }
    }

    public var labels: [AgentSessionLabel] {
        get { governance.labels }
        set { governance.labels = newValue }
    }

    public var isArchived: Bool {
        get { governance.isArchived }
        set {
            governance.isArchived = newValue
            if !newValue { governance.archivedAt = nil }
        }
    }

    public var isFlagged: Bool {
        get { governance.isFlagged }
        set { governance.isFlagged = newValue }
    }

    public init(
        id: String = UUID().uuidString,
        title: String = "New Chat",
        messages: [AgentMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.init(
            id: id,
            title: title,
            messages: messages,
            createdAt: createdAt,
            updatedAt: updatedAt,
            governance: .default
        )
    }

    @discardableResult
    public mutating func appendUserMessage(
        _ content: String,
        attachments: [AgentMessageAttachmentRef] = [],
        contextSnapshot: String? = nil
    ) -> AgentMessage {
        let message = AgentMessage(role: .user, content: content, contextSnapshot: contextSnapshot, attachments: attachments)
        messages.append(message)
        updatedAt = message.createdAt
        if title == "New Chat" {
            let titleSource = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? attachments.first?.displayName ?? content
                : content
            title = String(titleSource.prefix(40))
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
