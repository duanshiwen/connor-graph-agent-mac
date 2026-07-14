import Foundation
import ConnorGraphCore
import ConnorGraphAppSupport

struct InitialSessionContentSnapshot: Sendable {
    let sessions: [AgentSession]
    let allSessions: [AgentSession]
    let selectedSession: AgentSession?
    let state: AppSessionStateSnapshot?
    let records: [AppSessionRecord]
    let browserState: AppBrowserStateSnapshot?
    let backgroundTasks: [AppSessionBackgroundTask]
    let timeline: [AgentEventPresentation]
    let latestSummary: AgentSessionSummary?
    let artifactDirectories: AgentSessionArtifactDirectories?
}

struct AppInteractiveBootstrapSnapshot: Sendable {
    let llmSettings: StartupDomainResult<AppLLMSettings>
    let runtimeSettings: StartupDomainResult<AgentRuntimeSettings>
    let sessionContent: StartupDomainResult<InitialSessionContentSnapshot>
}

actor AppInteractiveBootstrapActor {
    func load(paths: AppStoragePaths, repository: AppGraphRepository, governanceConfig: AppSessionGovernanceConfig) async -> AppInteractiveBootstrapSnapshot {
        async let llmSettings = Self.loadLLMSettings()
        async let runtimeSettings = Self.loadRuntimeSettings(paths: paths)
        async let sessionContent = Self.loadSessionContent(paths: paths, repository: repository, governanceConfig: governanceConfig)
        return await AppInteractiveBootstrapSnapshot(
            llmSettings: llmSettings,
            runtimeSettings: runtimeSettings,
            sessionContent: sessionContent
        )
    }

    private nonisolated static func loadLLMSettings() -> StartupDomainResult<AppLLMSettings> {
        do { return .success(try AppLLMSettingsRepository().loadSettings()) }
        catch { return .failure(error) }
    }

    private nonisolated static func loadRuntimeSettings(paths: AppStoragePaths) -> StartupDomainResult<AgentRuntimeSettings> {
        do { return .success(try AppRuntimeSettingsRepository(configDirectory: paths.configDirectory).loadOrCreateDefault()) }
        catch { return .failure(error) }
    }

    private nonisolated static func loadSessionContent(
        paths: AppStoragePaths,
        repository: AppGraphRepository,
        governanceConfig: AppSessionGovernanceConfig
    ) -> StartupDomainResult<InitialSessionContentSnapshot> {
        do {
            let sessionsRepository = AppChatSessionRepository(store: repository.store, storagePaths: paths, governanceConfig: governanceConfig)
            var sessions = try sessionsRepository.loadSessions(filter: .all)
            if sessions.isEmpty {
                sessions = [try sessionsRepository.createSession()]
            }
            let allSessions = try sessionsRepository.loadSessions(filter: .all)
            guard let selectedSession = sessions.first.flatMap({ try? sessionsRepository.loadSession(id: $0.id) }) else {
                return .success(InitialSessionContentSnapshot(
                    sessions: sessions,
                    allSessions: allSessions,
                    selectedSession: nil,
                    state: nil,
                    records: [],
                    browserState: nil,
                    backgroundTasks: [],
                    timeline: [],
                    latestSummary: nil,
                    artifactDirectories: nil
                ))
            }
            let sessionID = selectedSession.id
            _ = try sessionsRepository.artifactDirectories(sessionID: sessionID)
            let state: AppSessionStateSnapshot
            if let existing = try sessionsRepository.loadSessionState(sessionID: sessionID) {
                state = existing
            } else {
                state = AppSessionStateSnapshot(sessionID: sessionID, updatedAt: Date())
                try sessionsRepository.saveSessionState(state, sessionID: sessionID)
            }
            let records = try sessionsRepository.loadSessionRecords(sessionID: sessionID, limit: nil)
            let browserState = try sessionsRepository.loadBrowserState(sessionID: sessionID)
            _ = try sessionsRepository.refreshSessionManifest(sessionID: sessionID)
            let backgroundTasks = try interruptPersistedActiveTasks(repository: sessionsRepository, sessionID: sessionID)
            let timeline = try loadLatestTimeline(repository: sessionsRepository, sessionID: sessionID)
            return .success(InitialSessionContentSnapshot(
                sessions: sessions,
                allSessions: allSessions,
                selectedSession: selectedSession,
                state: state,
                records: records,
                browserState: browserState,
                backgroundTasks: backgroundTasks,
                timeline: timeline,
                latestSummary: try sessionsRepository.loadLatestSummary(sessionID: sessionID),
                artifactDirectories: try sessionsRepository.artifactDirectories(sessionID: sessionID)
            ))
        } catch { return .failure(error) }
    }

    private nonisolated static func interruptPersistedActiveTasks(
        repository: AppChatSessionRepository,
        sessionID: String
    ) throws -> [AppSessionBackgroundTask] {
        var tasks = try repository.loadBackgroundTasks(sessionID: sessionID)
            .map(AppSessionBackgroundTask.init(persisted:))
        for index in tasks.indices where tasks[index].status == .queued || tasks[index].status == .running {
            tasks[index].status = .interrupted
            tasks[index].updatedAt = Date()
            tasks[index].errorMessage = "应用重启或会话恢复后，旧后台任务不会自动继续执行。"
            try repository.saveBackgroundTask(tasks[index].persisted)
        }
        return tasks
    }

    private nonisolated static func loadLatestTimeline(
        repository: AppChatSessionRepository,
        sessionID: String
    ) throws -> [AgentEventPresentation] {
        let cached = try repository.loadActivityTimelineCache(sessionID: sessionID)
        if !cached.isEmpty { return cached }
        let restorer = AgentEventPresentationRestorer()
        let runs = try repository.loadRuns(sessionID: sessionID, statuses: [.completed, .failed, .cancelled], limit: 3)
        for run in runs {
            let timeline = restorer.presentations(from: try repository.loadRunEvents(runID: run.id, limit: 200))
            if !timeline.isEmpty { return timeline }
        }
        return []
    }
}
