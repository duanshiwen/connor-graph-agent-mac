import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public struct AppChatSessionRepository: Sendable {
    public var store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func loadRecentSessions(limit: Int = 50) throws -> [AgentSession] {
        try store.recentSessions(limit: limit)
    }

    public func loadSession(id: String) throws -> AgentSession? {
        try store.session(id: id)
    }

    public func makeNewSession(title: String = "New Chat", now: Date = Date()) throws -> AgentSession {
        let session = AgentSession(id: UUID().uuidString, title: title, messages: [], createdAt: now, updatedAt: now)
        try store.upsertSession(session)
        return session
    }

    public func createSession(title: String = "New Chat", now: Date = Date()) throws -> AgentSession {
        try makeNewSession(title: title, now: now)
    }

    @discardableResult
    public func saveTurn(previousMessageCount: Int, response: GraphAgentAskResponse) throws -> AgentSession {
        try store.upsertSession(response.session)
        return response.session
    }

    @discardableResult
    public func saveSession(_ session: AgentSession, previousMessageCount: Int = 0) throws -> AgentSession {
        try store.upsertSession(session)
        return session
    }

    public func loadLatestSummary(sessionID: String) throws -> AgentSessionSummary? { nil }

    @discardableResult
    public func saveSummary(_ summary: AgentSessionSummary) throws -> AgentSessionSummary { summary }

    public func summarizeSession<Provider: LLMProvider>(id: String, using summarizer: AgentSessionSummarizer<Provider>) async throws -> AgentSessionSummary {
        try await summarizer.summarize(session: AgentSession(id: id))
    }
}
