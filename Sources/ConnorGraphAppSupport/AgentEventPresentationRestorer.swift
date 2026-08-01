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
            guard let event = try? replayer.replay(persistedEvent) else { return nil }
            var presentation = presenter.presentation(for: event)
            // Keep these assignments explicit so every event kind preserves the
            // persistence envelope timestamp even as presenter cases evolve.
            presentation.id = persistedEvent.id
            presentation.occurredAt = persistedEvent.createdAt
            return presentation
        }
    }
}
