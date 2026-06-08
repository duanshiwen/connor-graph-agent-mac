import Foundation

public enum AgentRole: String, Codable, Sendable, Equatable {
    case user
    case assistant
    case system
}

public struct AgentMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var role: AgentRole
    public var content: String
    public var createdAt: Date
    public var citations: [String]
    public var contextSnapshot: String?

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
    public mutating func appendAssistantMessage(_ content: String, citations: [String] = [], contextSnapshot: String? = nil) -> AgentMessage {
        let message = AgentMessage(role: .assistant, content: content, citations: citations, contextSnapshot: contextSnapshot)
        messages.append(message)
        updatedAt = message.createdAt
        return message
    }
}
