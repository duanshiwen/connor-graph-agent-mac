import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public enum AppChatSessionRepositoryError: Error, Equatable, CustomStringConvertible {
    case sessionNotFound(String)

    public var description: String {
        switch self {
        case .sessionNotFound(let id): "sessionNotFound: \(id)"
        }
    }
}

public struct AppChatSessionRepository: Sendable {
    public var store: SQLiteGraphKernelStore
    public var storagePaths: AppStoragePaths?
    public var governanceConfig: AppSessionGovernanceConfig

    public init(store: SQLiteGraphKernelStore, storagePaths: AppStoragePaths? = nil, governanceConfig: AppSessionGovernanceConfig = .default) {
        self.store = store
        self.storagePaths = storagePaths
        self.governanceConfig = governanceConfig
    }

    public func loadRecentSessions(limit: Int = 50, includeArchived: Bool = false) throws -> [AgentSession] {
        try store.recentSessions(limit: limit, includeArchived: includeArchived)
    }

    public func loadSessions(filter: AgentSessionListFilter, limit: Int = 100) throws -> [AgentSession] {
        switch filter {
        case .inbox:
            try store.recentSessions(limit: limit, includeArchived: false)
        case .archived:
            try store.sessions(archived: true, limit: limit)
        case .status(let status):
            try store.sessions(status: status, archived: false, limit: limit)
        case .label(let labelID):
            try store.sessions(labelID: labelID, archived: false, limit: limit)
        case .all:
            try store.recentSessions(limit: limit, includeArchived: true)
        }
    }

    public func loadSession(id: String) throws -> AgentSession? {
        try store.session(id: id)
    }

    public func makeNewSession(title: String = "New Chat", now: Date = Date()) throws -> AgentSession {
        let session = AgentSession(id: UUID().uuidString, title: title, messages: [], createdAt: now, updatedAt: now, governance: .default)
        try store.upsertSession(session)
        _ = try storagePaths?.ensureSessionArtifactDirectories(sessionID: session.id)
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
        _ = try storagePaths?.ensureSessionArtifactDirectories(sessionID: session.id)
        return session
    }

    @discardableResult
    public func updateGovernance(sessionID: String, mutate: (inout AgentSessionGovernanceMetadata) throws -> Void) throws -> AgentSession {
        guard var session = try loadSession(id: sessionID) else { throw AppChatSessionRepositoryError.sessionNotFound(sessionID) }
        var governance = session.governance
        try mutate(&governance)
        for label in governance.labels { try governanceConfig.validate(label: label) }
        session.governance = governance
        session.updatedAt = Date()
        try store.upsertSession(session)
        return session
    }

    @discardableResult
    public func setStatus(sessionID: String, status: AgentSessionStatus) throws -> AgentSession {
        try updateGovernance(sessionID: sessionID) { governance in
            governance.status = status
            if status == .archived {
                governance.isArchived = true
                governance.archivedAt = Date()
            }
        }
    }

    @discardableResult
    public func setLabels(sessionID: String, labels: [AgentSessionLabel]) throws -> AgentSession {
        try updateGovernance(sessionID: sessionID) { governance in governance.labels = labels }
    }

    @discardableResult
    public func toggleFlag(sessionID: String) throws -> AgentSession {
        try updateGovernance(sessionID: sessionID) { governance in governance.isFlagged.toggle() }
    }

    @discardableResult
    public func archive(sessionID: String, now: Date = Date()) throws -> AgentSession {
        try updateGovernance(sessionID: sessionID) { governance in
            governance.isArchived = true
            governance.status = .archived
            governance.archivedAt = now
        }
    }

    @discardableResult
    public func restore(sessionID: String) throws -> AgentSession {
        try updateGovernance(sessionID: sessionID) { governance in
            governance.isArchived = false
            governance.status = .todo
            governance.archivedAt = nil
        }
    }

    public func artifactDirectories(sessionID: String) throws -> AgentSessionArtifactDirectories? {
        try storagePaths?.ensureSessionArtifactDirectories(sessionID: sessionID)
    }

    public func loadLatestSummary(sessionID: String) throws -> AgentSessionSummary? { nil }

    @discardableResult
    public func saveSummary(_ summary: AgentSessionSummary) throws -> AgentSessionSummary { summary }

    public func summarizeSession<Provider: LLMProvider>(id: String, using summarizer: AgentSessionSummarizer<Provider>) async throws -> AgentSessionSummary {
        try await summarizer.summarize(session: AgentSession(id: id))
    }
}
