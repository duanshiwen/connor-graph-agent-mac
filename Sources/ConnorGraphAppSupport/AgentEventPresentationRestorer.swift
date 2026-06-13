import Foundation
import ConnorGraphAgent

public struct AgentEventPresentationRestorer: Sendable {
    public init() {}

    public func presentations(from persistedEvents: [PersistedAgentEvent]) -> [AgentEventPresentation] {
        let replayer = AgentEventReplayer()
        let presenter = AgentEventPresenter()
        let replaySource = persistedEvents.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            switch (lhs.sequence, rhs.sequence) {
            case let (left?, right?): return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.id < rhs.id
            }
        }
        return replaySource.compactMap { persistedEvent in
            try? replayer.replay(persistedEvent)
        }.map { event in
            presenter.presentation(for: event)
        }
    }
}
