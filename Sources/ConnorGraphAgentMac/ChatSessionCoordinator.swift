import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
@Observable
final class ChatSessionCoordinator {
    let model: ChatSessionListModel
    private(set) var hasLoadedInitialSessions = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let repository: AppChatSessionRepository?
    @ObservationIgnored private let detailLoader = ChatSessionDetailLoadCoordinator()
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var selectionGeneration = 0
    @ObservationIgnored private var pendingNewSessionIDs: Set<String> = []
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored private var filterChangeGeneration = 0

    @ObservationIgnored var activeSessionIDProvider: () -> String = { "" }
    @ObservationIgnored var onSelectionWillChange: (String?, String) -> Void = { _, _ in }
    @ObservationIgnored var onSelectionStarted: (String) -> Void = { _ in }
    @ObservationIgnored var onSelectionLoaded: (ChatSessionDetailLoadSnapshot, Int, ContinuousClock.Instant) -> Void = { _, _, _ in }
    @ObservationIgnored var onReloadSelectedSession: (AgentSession, Bool) throws -> Void = { _, _ in }
    @ObservationIgnored var onSelectionCleared: () -> Void = {}
    @ObservationIgnored var onSessionsChanged: ([AgentSession]) -> Void = { _ in }
    @ObservationIgnored var onSessionAdded: (AgentSession) -> Void = { _ in }
    @ObservationIgnored var onError: (String) -> Void = { _ in }

    init(model: ChatSessionListModel, repository: AppChatSessionRepository?) {
        self.model = model
        self.repository = repository
    }

    var isLoadingSelectedDetail: Bool {
        guard let selected = model.selectedSessionID else { return false }
        return model.loadingSessionDetailID == selected
    }

    func installStartupSessions(_ sessions: [AgentSession], allSessions: [AgentSession]) {
        guard !isShutdown else { return }
        hasLoadedInitialSessions = true
        model.sessions = sessions
        model.allSessions = allSessions
        onSessionsChanged(allSessions)
    }

    func reloadIfNeeded(restoreWorkspaceMode: Bool = true) {
        guard !isShutdown, !hasLoadedInitialSessions else { return }
        reload(restoreWorkspaceMode: restoreWorkspaceMode)
    }

    func reload(restoreWorkspaceMode: Bool = true) {
        guard !isShutdown else { return }
        hasLoadedInitialSessions = true
        guard let repository else { return }
        do {
            var sessions = try repository.loadSessions(filter: model.filter)
            if sessions.isEmpty, model.filter == .all {
                sessions = [try repository.createSession()]
            }
            model.sessions = sessions
            model.allSessions = try repository.loadSessions(filter: .all)
            onSessionsChanged(model.allSessions)
            let selectedID = selectedSessionIDVisible(in: sessions)
            model.selectedSessionID = selectedID
            if let selectedID, let session = try repository.loadSession(id: selectedID) {
                try onReloadSelectedSession(session, restoreWorkspaceMode)
            } else {
                clearSelection()
            }
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    func setFilter(_ filter: AgentSessionListFilter, restoreWorkspaceMode: Bool = true) {
        guard !isShutdown, model.filter != filter else { return }
        _ = restoreWorkspaceMode
        filterChangeGeneration += 1
        let generation = filterChangeGeneration
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let measured = AppPerformanceLog.measure {
            model.filter = filter
            let projectedSessions = Self.filter(model.allSessions, by: filter)
            model.sessions = projectedSessions
            reconcileSelection(visibleSessions: projectedSessions)
        }
        AppPerformanceLog.sidebarNavigationLogger.info(
            "sidebar.filter.commit filter=\(String(describing: filter), privacy: .public) visible=\(self.model.sessions.count, privacy: .public) duration=\(measured.milliseconds, privacy: .public)ms"
        )
        DispatchQueue.main.async { [weak self] in
            guard let self, self.filterChangeGeneration == generation, self.model.filter == filter else { return }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            AppPerformanceLog.sidebarNavigationLogger.info(
                "sidebar.filter.firstMainTurn filter=\(String(describing: filter), privacy: .public) visible=\(self.model.sessions.count, privacy: .public) duration=\(elapsed, privacy: .public)ms"
            )
        }
    }

    func select(_ sessionID: String) {
        guard !isShutdown, let repository else { return }
        if pendingNewSessionIDs.contains(sessionID) { return }
        if model.selectedSessionID == sessionID,
           model.loadingSessionDetailID == nil,
           activeSessionIDProvider() == sessionID { return }
        let previous = model.selectedSessionID
        onSelectionWillChange(previous, sessionID)
        selectionTask?.cancel()
        selectionGeneration += 1
        let generation = selectionGeneration
        let startedAt = ContinuousClock.now
        model.selectedSessionID = sessionID
        model.loadingSessionDetailID = sessionID
        onSelectionStarted(sessionID)
        errorMessage = nil
        let activeBackgroundTaskIDs = Set(model.backgroundTasksBySessionID[sessionID, default: []]
            .filter { $0.status == .queued || $0.status == .running }
            .map(\.id))
        selectionTask = Task(priority: .userInitiated) { [weak self] in
            do {
                guard let snapshot = try await self?.detailLoader.load(
                    repository: repository,
                    sessionID: sessionID,
                    activeBackgroundTaskIDs: activeBackgroundTaskIDs
                ) else {
                    guard let self, self.isCurrent(sessionID: sessionID, generation: generation) else { return }
                    self.model.loadingSessionDetailID = nil
                    self.report("无法加载所选会话。")
                    return
                }
                try Task.checkCancellation()
                guard let self, self.isCurrent(sessionID: sessionID, generation: generation) else { return }
                self.onSelectionLoaded(snapshot, generation, startedAt)
                if self.isCurrent(sessionID: sessionID, generation: generation) {
                    self.model.loadingSessionDetailID = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.isCurrent(sessionID: sessionID, generation: generation) else { return }
                self.model.loadingSessionDetailID = nil
                self.report(error)
            }
        }
    }

    func adoptDirectSelection(_ sessionID: String) {
        guard !isShutdown else { return }
        selectionTask?.cancel()
        selectionGeneration += 1
        model.loadingSessionDetailID = nil
        model.selectedSessionID = sessionID
    }

    /// Installs a newly persisted session without synchronously reloading every
    /// session (and the selected session detail) from SQLite. New sessions are
    /// already complete value snapshots, so a full repository round-trip adds
    /// latency without adding correctness.
    @discardableResult
    func adoptNewSession(_ session: AgentSession) -> Bool {
        adoptNewSession(session, isPreparing: false)
    }

    /// Publishes a new session before persistence/runtime construction finishes.
    /// The selected row changes immediately while the existing chat loading view
    /// replaces stale detail content until `completeNewSessionPreparation` runs.
    @discardableResult
    func adoptPreparingNewSession(_ session: AgentSession) -> Bool {
        adoptNewSession(session, isPreparing: true)
    }

    func completeNewSessionPreparation(sessionID: String) {
        pendingNewSessionIDs.remove(sessionID)
        guard model.selectedSessionID == sessionID,
              model.loadingSessionDetailID == sessionID else { return }
        model.loadingSessionDetailID = nil
    }

    func discardPreparingNewSession(sessionID: String) {
        pendingNewSessionIDs.remove(sessionID)
        model.allSessions.removeAll { $0.id == sessionID }
        model.sessions.removeAll { $0.id == sessionID }
        if model.selectedSessionID == sessionID {
            clearSelection()
        }
        onSessionsChanged(model.allSessions)
    }

    private func adoptNewSession(_ session: AgentSession, isPreparing: Bool) -> Bool {
        guard !isShutdown else { return false }
        hasLoadedInitialSessions = true

        model.allSessions.removeAll { $0.id == session.id }
        model.allSessions.insert(session, at: 0)
        model.sessions = Self.filter(model.allSessions, by: model.filter)
        let isVisible = model.sessions.contains { $0.id == session.id }
        if isVisible {
            selectionTask?.cancel()
            selectionGeneration += 1
            model.selectedSessionID = session.id
            model.loadingSessionDetailID = isPreparing ? session.id : nil
            if isPreparing {
                pendingNewSessionIDs.insert(session.id)
                onSelectionStarted(session.id)
            }
        } else {
            pendingNewSessionIDs.remove(session.id)
            clearSelection()
        }
        onSessionAdded(session)
        errorMessage = nil
        return isVisible
    }

    func clearSelection() {
        selectionTask?.cancel()
        selectionGeneration += 1
        model.loadingSessionDetailID = nil
        model.selectedSessionID = nil
        onSelectionCleared()
    }

    func rename(_ sessionID: String, title: String) -> AgentSession? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let repository else { return nil }
        do {
            let updated = try repository.renameSession(sessionID: sessionID, title: trimmed)
            replaceInLists(updated)
            errorMessage = nil
            return updated
        } catch {
            report(error)
            return nil
        }
    }

    func setStatus(_ sessionID: String, status: AgentSessionStatus) throws -> (AgentSession, AgentSessionStatus?)? {
        guard let repository else { return nil }
        let previous = try repository.loadSession(id: sessionID)?.governance.status
        let updated = try repository.setStatus(sessionID: sessionID, status: status)
        replaceInLists(updated)
        return (updated, previous)
    }

    func toggleLabel(_ sessionID: String, labelID: String) throws -> (AgentSession, didRemove: Bool)? {
        guard let repository, let session = try repository.loadSession(id: sessionID) else { return nil }
        var labels = session.governance.labels
        let didRemove: Bool
        if labels.contains(where: { $0.id == labelID }) {
            labels.removeAll { $0.id == labelID }
            didRemove = true
        } else {
            labels.append(AgentSessionLabel(id: labelID))
            didRemove = false
        }
        let updated = try repository.setLabels(sessionID: sessionID, labels: labels)
        replaceInLists(updated)
        return (updated, didRemove)
    }

    func synchronize(_ session: AgentSession) {
        replaceInLists(session)
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        selectionTask?.cancel()
        selectionTask = nil
        selectionGeneration += 1
        pendingNewSessionIDs.removeAll()
        model.loadingSessionDetailID = nil
    }

    static func filter(_ sessions: [AgentSession], by filter: AgentSessionListFilter) -> [AgentSession] {
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

    private func reconcileSelection(visibleSessions: [AgentSession]) {
        if let selectedSessionID = model.selectedSessionID {
            if !visibleSessions.contains(where: { $0.id == selectedSessionID }) {
                clearSelection()
            }
            return
        }
        if model.filter == .all, let firstSessionID = visibleSessions.first?.id {
            select(firstSessionID)
        }
    }

    private func selectedSessionIDVisible(in sessions: [AgentSession]) -> String? {
        if let selected = model.selectedSessionID {
            return sessions.contains(where: { $0.id == selected }) ? selected : nil
        }
        return model.filter == .all ? sessions.first?.id : nil
    }

    private func isCurrent(sessionID: String, generation: Int) -> Bool {
        selectionGeneration == generation
            && model.selectedSessionID == sessionID
            && model.loadingSessionDetailID == sessionID
    }

    private func replaceInLists(_ session: AgentSession) {
        if let index = model.sessions.firstIndex(where: { $0.id == session.id }) { model.sessions[index] = session }
        if let index = model.allSessions.firstIndex(where: { $0.id == session.id }) { model.allSessions[index] = session }
        onSessionsChanged(model.allSessions)
    }

    private func report(_ error: Error) { report(String(describing: error)) }
    private func report(_ message: String) {
        errorMessage = message
        onError(message)
    }
}
