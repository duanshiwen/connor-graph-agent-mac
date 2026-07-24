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
    @ObservationIgnored private var pendingImportedSessions: [String: AgentSession] = [:]
    @ObservationIgnored private var importedSessionFlushTask: Task<Void, Never>?
    @ObservationIgnored private var loadMoreTask: Task<Void, Never>?

    @ObservationIgnored var activeSessionIDProvider: () -> String = { "" }
    @ObservationIgnored var onSelectionWillChange: (String?, String) -> Void = { _, _ in }
    @ObservationIgnored var onSelectionStarted: (String) -> Void = { _ in }
    @ObservationIgnored var onSelectionLoaded: (ChatSessionDetailLoadSnapshot, Int, ContinuousClock.Instant) async -> Void = { _, _, _ in }
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

    func installStartupSessions(
        _ sessions: [AgentSession],
        allSessions: [AgentSession],
        nextCursor: String? = nil,
        messageCounts: [String: Int] = [:],
        summary: AppChatSessionSummary? = nil
    ) {
        guard !isShutdown else { return }
        hasLoadedInitialSessions = true
        model.sessions = sessions
        model.allSessions = allSessions
        model.nextPageCursor = nextCursor
        model.messageCountsBySessionID = messageCounts
        if let summary { model.applySidebarSummary(summary) }
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
            let page = try repository.loadSessionPage(filter: model.filter, query: model.searchQuery)
            var sessions = page.sessions
            if sessions.isEmpty, model.filter == .all {
                sessions = [try repository.createSession()]
            }
            model.sessions = sessions
            model.allSessions = sessions
            model.messageCountsBySessionID = page.messageCounts
            model.nextPageCursor = page.nextCursor
            model.applySidebarSummary(try repository.loadSessionSummary())
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
        model.filter = filter
        reload(restoreWorkspaceMode: false)
    }

    func loadMoreIfNeeded(currentSessionID: String) {
        guard !isShutdown, model.sessions.last?.id == currentSessionID,
              let cursor = model.nextPageCursor, !model.isLoadingNextPage,
              loadMoreTask == nil, let repository else { return }
        let filter = model.filter
        let query = model.searchQuery
        model.isLoadingNextPage = true
        loadMoreTask = Task { [weak self] in
            defer { self?.model.isLoadingNextPage = false; self?.loadMoreTask = nil }
            do {
                let page = try await Task.detached(priority: .utility) {
                    try repository.loadSessionPage(filter: filter, query: query, cursor: cursor)
                }.value
                guard let self, !self.isShutdown, self.model.filter == filter, self.model.searchQuery == query else { return }
                let existing = Set(self.model.sessions.map(\.id))
                let appended = page.sessions.filter { !existing.contains($0.id) }
                self.model.sessions.append(contentsOf: appended)
                if filter == .all { self.model.allSessions = self.model.sessions }
                self.model.messageCountsBySessionID.merge(page.messageCounts) { _, new in new }
                self.model.nextPageCursor = page.nextCursor
            } catch { self?.report(error) }
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
        model.presentedSessionDetailID = nil
        onSelectionStarted(sessionID)
        errorMessage = nil
        let activeBackgroundTaskIDs = Set(model.backgroundTasksBySessionID[sessionID, default: []]
            .filter { $0.status == .queued || $0.status == .running }
            .map(\.id))
        selectionTask = Task(priority: .userInitiated) { [weak self] in
            do {
                guard let self else { return }
                let detailLoader = self.detailLoader
                let detailTask = Task.detached(priority: .userInitiated) {
                    try await detailLoader.load(
                        repository: repository,
                        sessionID: sessionID,
                        activeBackgroundTaskIDs: activeBackgroundTaskIDs
                    )
                }
                let loadedSnapshot = try await withTaskCancellationHandler {
                    try await detailTask.value
                } onCancel: {
                    detailTask.cancel()
                }
                guard let snapshot = loadedSnapshot else {
                    guard self.isCurrent(sessionID: sessionID, generation: generation) else { return }
                    self.model.loadingSessionDetailID = nil
                    self.report("无法加载所选会话。")
                    return
                }
                try Task.checkCancellation()
                guard self.isCurrent(sessionID: sessionID, generation: generation) else { return }
                await self.onSelectionLoaded(snapshot, generation, startedAt)
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
        model.presentedSessionDetailID = sessionID
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
        model.presentedSessionDetailID = sessionID
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
            model.presentedSessionDetailID = isPreparing ? nil : session.id
            if isPreparing {
                pendingNewSessionIDs.insert(session.id)
                onSelectionStarted(session.id)
            }
        } else {
            pendingNewSessionIDs.remove(session.id)
            clearSelection()
        }
        onSessionAdded(session)
        refreshSidebarSummary()
        errorMessage = nil
        return isVisible
    }

    func clearSelection() {
        selectionTask?.cancel()
        selectionGeneration += 1
        model.loadingSessionDetailID = nil
        model.selectedSessionID = nil
        model.presentedSessionDetailID = nil
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
        refreshSidebarSummary()
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
        refreshSidebarSummary()
        return (updated, didRemove)
    }

    func synchronize(_ session: AgentSession) {
        replaceInLists(session)
    }

    /// Coalesces imported sessions before updating the observable list. Import
    /// progress can advance several items at once, so publishing one batch keeps
    /// sidebar navigation independent from import throughput.
    func enqueueImportedSession(_ session: AgentSession) {
        guard !isShutdown else { return }
        pendingImportedSessions[session.id] = session
        scheduleImportedSessionFlush()
    }

    private func scheduleImportedSessionFlush() {
        importedSessionFlushTask?.cancel()
        importedSessionFlushTask = Task(priority: .utility) { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.model.loadingSessionDetailID == nil else {
                self.scheduleImportedSessionFlush()
                return
            }
            self.flushPendingImportedSessions()
        }
    }

    func installImportedSessions(_ importedSessions: [AgentSession]) {
        guard !isShutdown, !importedSessions.isEmpty else { return }
        let importedByID = Dictionary(uniqueKeysWithValues: importedSessions.map { ($0.id, $0) })
        let existingIDs = Set(model.allSessions.map(\.id))
        let newSessions = importedSessions.filter { !existingIDs.contains($0.id) }
        hasLoadedInitialSessions = true
        model.allSessions = model.allSessions.map { importedByID[$0.id] ?? $0 }
        model.allSessions.append(contentsOf: newSessions)
        model.allSessions.sort { $0.updatedAt > $1.updatedAt }
        model.sessions = Self.filter(model.allSessions, by: model.filter)
        for session in newSessions { onSessionAdded(session) }
        onSessionsChanged(model.allSessions)
        refreshSidebarSummary()
        errorMessage = nil
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        selectionTask?.cancel()
        selectionTask = nil
        selectionGeneration += 1
        pendingNewSessionIDs.removeAll()
        importedSessionFlushTask?.cancel()
        importedSessionFlushTask = nil
        pendingImportedSessions.removeAll()
        loadMoreTask?.cancel()
        loadMoreTask = nil
        model.isLoadingNextPage = false
        model.loadingSessionDetailID = nil
        model.presentedSessionDetailID = nil
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

    private func flushPendingImportedSessions() {
        importedSessionFlushTask = nil
        let sessions = Array(pendingImportedSessions.values)
        pendingImportedSessions.removeAll()
        installImportedSessions(sessions)
    }

    private func refreshSidebarSummary() {
        guard let repository, let summary = try? repository.loadSessionSummary() else { return }
        model.applySidebarSummary(summary)
    }

    private func report(_ error: Error) { report(String(describing: error)) }
    private func report(_ message: String) {
        errorMessage = message
        onError(message)
    }
}
