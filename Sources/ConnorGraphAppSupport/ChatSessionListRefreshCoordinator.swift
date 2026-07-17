import Foundation
import ConnorGraphCore

public struct ChatSessionListRefreshResult: Sendable, Equatable {
    public var visibleSessions: [AgentSession]
    public var allSessions: [AgentSession]

    public init(visibleSessions: [AgentSession], allSessions: [AgentSession]) {
        self.visibleSessions = visibleSessions
        self.allSessions = allSessions
    }
}

public actor ChatSessionListRefreshCoordinator {
    public init() {}

    public func refresh(
        repository: AppChatSessionRepository,
        filter: AgentSessionListFilter,
        preserving existingSessions: [AgentSession] = []
    ) throws -> ChatSessionListRefreshResult {
        let existingByID = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.id, $0) })
        let persistedMessageCounts = try repository.loadSessionMessageCounts()
        let all = try repository.loadSessionMetadata().map { metadata in
            guard let existing = existingByID[metadata.id], !existing.messages.isEmpty else { return metadata }
            guard existing.messages.count == persistedMessageCounts[metadata.id] else {
                return try repository.loadSession(id: metadata.id) ?? metadata
            }
            var merged = metadata
            merged.messages = existing.messages
            return merged
        }
        let visible = Self.filter(all, by: filter)
        return ChatSessionListRefreshResult(visibleSessions: visible, allSessions: all)
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
