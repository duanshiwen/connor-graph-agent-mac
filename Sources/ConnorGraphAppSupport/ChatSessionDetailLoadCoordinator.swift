import Foundation
import ConnorGraphCore
import ConnorGraphStore

public struct ChatSessionDetailLoadSnapshot: Sendable, Equatable {
    public var session: AgentSession
    public var timeline: [AgentEventPresentation]
    public var latestSummary: AgentSessionSummary?
    public var artifactDirectories: AgentSessionArtifactDirectories?
    public var sessionState: AppSessionStateSnapshot?
    public var sessionRecords: [AppSessionRecord]
    public var browserState: AppBrowserStateSnapshot?
    public var backgroundTasks: [PersistedSessionBackgroundTask]

    public init(
        session: AgentSession,
        timeline: [AgentEventPresentation],
        latestSummary: AgentSessionSummary?,
        artifactDirectories: AgentSessionArtifactDirectories?,
        sessionState: AppSessionStateSnapshot? = nil,
        sessionRecords: [AppSessionRecord] = [],
        browserState: AppBrowserStateSnapshot? = nil,
        backgroundTasks: [PersistedSessionBackgroundTask] = []
    ) {
        self.session = session
        self.timeline = timeline
        self.latestSummary = latestSummary
        self.artifactDirectories = artifactDirectories
        self.sessionState = sessionState
        self.sessionRecords = sessionRecords
        self.browserState = browserState
        self.backgroundTasks = backgroundTasks
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
        sessionID: String,
        activeBackgroundTaskIDs: Set<String> = []
    ) throws -> ChatSessionDetailLoadSnapshot? {
        guard let session = try repository.loadSession(id: sessionID) else { return nil }
        let timeline = try loadTimeline(repository: repository, sessionID: sessionID)
        let backgroundTasks = try reconcileBackgroundTasks(
            repository: repository,
            sessionID: sessionID,
            activeIDs: activeBackgroundTaskIDs
        )
        return ChatSessionDetailLoadSnapshot(
            session: session,
            timeline: timeline,
            latestSummary: try repository.loadLatestSummary(sessionID: sessionID),
            artifactDirectories: try repository.artifactDirectories(sessionID: sessionID),
            sessionState: try repository.loadSessionState(sessionID: sessionID),
            sessionRecords: try repository.loadSessionRecords(sessionID: sessionID, limit: nil),
            browserState: try repository.loadBrowserState(sessionID: sessionID),
            backgroundTasks: backgroundTasks
        )
    }

    private func reconcileBackgroundTasks(
        repository: AppChatSessionRepository,
        sessionID: String,
        activeIDs: Set<String>
    ) throws -> [PersistedSessionBackgroundTask] {
        var tasks = try repository.loadBackgroundTasks(sessionID: sessionID)
        for index in tasks.indices
        where (tasks[index].status == .queued || tasks[index].status == .running)
            && !activeIDs.contains(tasks[index].id) {
            tasks[index].status = .interrupted
            tasks[index].updatedAt = Date()
            tasks[index].errorMessage = "应用重启或会话恢复后，旧后台任务不会自动继续执行。"
            try repository.saveBackgroundTask(tasks[index])
        }
        return tasks
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
