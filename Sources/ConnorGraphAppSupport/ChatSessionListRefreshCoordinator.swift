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
        filter: AgentSessionListFilter
    ) throws -> ChatSessionListRefreshResult {
        let visible = try repository.loadSessions(filter: filter)
        let all = filter == .all ? visible : try repository.loadSessions(filter: .all)
        return ChatSessionListRefreshResult(visibleSessions: visible, allSessions: all)
    }
}
