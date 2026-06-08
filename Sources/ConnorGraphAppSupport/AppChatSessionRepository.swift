import Foundation
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphStore

public struct AppChatSessionRepository: Sendable {
    public var store: SQLiteGraphStore

    public init(store: SQLiteGraphStore) {
        self.store = store
    }

    public func loadRecentSessions(limit: Int = 50) throws -> [AgentSession] {
        try store.chatSessions(limit: limit)
    }

    public func loadSession(id: String) throws -> AgentSession? {
        try store.chatSession(id: id)
    }

    public func createSession(now: Date = Date()) throws -> AgentSession {
        let session = AgentSession(
            id: UUID().uuidString,
            title: "New Chat",
            messages: [],
            createdAt: now,
            updatedAt: now
        )
        try store.upsert(chatSession: session)
        return session
    }

    @discardableResult
    public func saveTurn(previousMessageCount: Int, response: GraphAgentAskResponse) throws -> AgentSession {
        try store.upsert(chatSession: response.session)
        let newMessages = response.session.messages.dropFirst(previousMessageCount)
        for message in newMessages {
            try store.append(chatMessage: message, sessionID: response.session.id)
        }
        for entry in response.observeLogEntries {
            try store.upsert(observeLogEntry: entry)
        }
        return try store.chatSession(id: response.session.id) ?? response.session
    }
}
