import Foundation
import ConnorGraphCore

public struct ChatSessionDetailLoadSnapshot: Sendable, Equatable {
    public var session: AgentSession
    public var timeline: [AgentEventPresentation]
    public var latestSummary: AgentSessionSummary?
    public var artifactDirectories: AgentSessionArtifactDirectories?

    public init(
        session: AgentSession,
        timeline: [AgentEventPresentation],
        latestSummary: AgentSessionSummary?,
        artifactDirectories: AgentSessionArtifactDirectories?
    ) {
        self.session = session
        self.timeline = timeline
        self.latestSummary = latestSummary
        self.artifactDirectories = artifactDirectories
    }
}

public actor ChatSessionDetailLoadCoordinator {
    public struct Limits: Sendable, Equatable {
        public var recentRunCount: Int
        public var eventsPerRun: Int
        public var recentJournalEventCount: Int

        public init(recentRunCount: Int = 3, eventsPerRun: Int = 200, recentJournalEventCount: Int = 400) {
            self.recentRunCount = recentRunCount
            self.eventsPerRun = eventsPerRun
            self.recentJournalEventCount = recentJournalEventCount
        }
    }

    private let limits: Limits
    private let restorer = AgentEventPresentationRestorer()

    public init(limits: Limits = .init()) {
        self.limits = limits
    }

    public func load(
        repository: AppChatSessionRepository,
        sessionID: String
    ) throws -> ChatSessionDetailLoadSnapshot? {
        guard let session = try repository.loadSession(id: sessionID) else { return nil }
        let timeline = try loadTimeline(repository: repository, sessionID: sessionID)
        return ChatSessionDetailLoadSnapshot(
            session: session,
            timeline: timeline,
            latestSummary: try repository.loadLatestSummary(sessionID: sessionID),
            artifactDirectories: try repository.artifactDirectories(sessionID: sessionID)
        )
    }

    private func loadTimeline(
        repository: AppChatSessionRepository,
        sessionID: String
    ) throws -> [AgentEventPresentation] {
        let cached = try repository.loadActivityTimelineCache(sessionID: sessionID)
        if !cached.isEmpty { return cached }

        let runs = try repository.loadRuns(
            sessionID: sessionID,
            statuses: [.completed, .failed, .cancelled],
            limit: limits.recentRunCount
        )
        for run in runs {
            let events = try repository.loadRunEvents(runID: run.id, limit: limits.eventsPerRun)
            let restored = restorer.presentations(from: events)
            if !restored.isEmpty { return restored }
        }

        let recentEvents = try repository.loadRecentJournalEvents(
            sessionID: sessionID,
            limit: limits.recentJournalEventCount
        )
        guard let latestRunID = recentEvents.first?.runID else { return [] }
        let latestRunEvents = recentEvents
            .filter { $0.runID == latestRunID }
            .sorted { lhs, rhs in
                switch (lhs.sequence, rhs.sequence) {
                case let (left?, right?): return left < right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.createdAt < rhs.createdAt
                }
            }
        return restorer.presentations(from: latestRunEvents)
    }
}
