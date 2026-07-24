import Foundation
import ConnorGraphCore

public struct ChatSessionListRefreshResult: Sendable, Equatable {
    public var visibleSessions: [AgentSession]
    public var allSessions: [AgentSession]
    public var nextCursor: String?
    public var messageCounts: [String: Int]
    public var summary: AppChatSessionSummary

    public init(visibleSessions: [AgentSession], allSessions: [AgentSession], nextCursor: String? = nil, messageCounts: [String: Int] = [:], summary: AppChatSessionSummary = .init()) {
        self.visibleSessions = visibleSessions
        self.allSessions = allSessions
        self.nextCursor = nextCursor
        self.messageCounts = messageCounts
        self.summary = summary
    }
}

public actor ChatSessionListRefreshCoordinator {
    public init() {}

    public func refresh(
        repository: AppChatSessionRepository,
        filter: AgentSessionListFilter,
        query: String = "",
        preserving existingSessions: [AgentSession] = []
    ) throws -> ChatSessionListRefreshResult {
        let existingByID = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.id, $0) })
        let page = try repository.loadSessionPage(filter: filter, query: query)
        let visible = page.sessions.map { metadata in
            guard let existing = existingByID[metadata.id], !existing.messages.isEmpty,
                  existing.updatedAt == metadata.updatedAt else { return metadata }
            var merged = metadata
            merged.messages = existing.messages
            return merged
        }
        let all = filter == .all ? visible : try repository.loadSessionPage(filter: .all).sessions
        return ChatSessionListRefreshResult(
            visibleSessions: visible,
            allSessions: all,
            nextCursor: page.nextCursor,
            messageCounts: page.messageCounts,
            summary: try repository.loadSessionSummary()
        )
    }

    private static func filter(_ sessions: [AgentSession], by filter: AgentSessionListFilter) -> [AgentSession] {
        switch filter {
        case .all:
            sessions
        case .status(let status):
            sessions.filter { $0.governance.status == status }
        case .label(let labelID):
            sessions.filter { session in
                session.governance.labels.contains { $0.id == labelID }
            }
        }
    }
}
