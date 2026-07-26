import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport

@MainActor
final class AIConnectionsRuntimeCoordinator {
    private struct DisplayPreparation: Sendable {
        var state: AppSessionStateSnapshot?
        var settings: AppLLMSettings?
    }

    private let model: AIConnectionsFeatureModel
    private let workspace: ChatWorkspaceCoordinator
    private let sessionRepository: AppChatSessionRepository?
    private let currentSessionID: () -> String
    private let rebuildRuntime: () -> Void
    private var displaySyncTask: Task<Void, Never>?

    init(
        model: AIConnectionsFeatureModel,
        workspace: ChatWorkspaceCoordinator,
        sessionRepository: AppChatSessionRepository?,
        currentSessionID: @escaping () -> String,
        rebuildRuntime: @escaping () -> Void
    ) {
        self.model = model
        self.workspace = workspace
        self.sessionRepository = sessionRepository
        self.currentSessionID = currentSessionID
        self.rebuildRuntime = rebuildRuntime
    }

    var sessionHasOverride: Bool {
        workspace.stateSnapshotsBySessionID[currentSessionID()]?.llmOverride != nil
    }

    func selectModel(_ modelID: String, providerMode: AppLLMProviderMode, connectionID: String?) {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.providerMode = providerMode
        if let connectionID { model.activeConnectionID = connectionID }
        model.selectedModel = modelID

        let sessionID = currentSessionID()
        var state = workspace.stateSnapshotsBySessionID[sessionID] ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.llmOverride = SessionLLMOverride(
            providerMode: providerMode.rawValue,
            model: modelID,
            connectionID: connectionID,
            thinkingLevel: state.llmOverride?.thinkingLevel
        )
        persist(state, sessionID: sessionID)
        rebuildRuntime()
        Task { await model.reloadModelConnections() }
    }

    func selectThinkingLevel(_ level: AppLLMThinkingLevel) {
        model.thinkingLevel = level
        let sessionID = currentSessionID()
        var state = workspace.stateSnapshotsBySessionID[sessionID] ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.llmOverride = SessionLLMOverride(
            providerMode: state.llmOverride?.providerMode ?? model.providerMode.rawValue,
            model: state.llmOverride?.model ?? model.selectedModel,
            baseURLString: state.llmOverride?.baseURLString,
            connectionID: state.llmOverride?.connectionID ?? model.activeConnectionID,
            thinkingLevel: level.rawValue
        )
        persist(state, sessionID: sessionID)
        rebuildRuntime()
    }

    func selectDefaultThinkingLevel(_ level: AppLLMThinkingLevel) {
        model.selectDefaultThinkingLevel(level)
    }

    @discardableResult
    func ensureOverride(sessionID: String) -> SessionLLMOverride? {
        var state = workspace.stateSnapshotsBySessionID[sessionID]
        if state == nil, let loaded = try? sessionRepository?.loadSessionState(sessionID: sessionID) {
            state = loaded
        }
        if let existing = state?.llmOverride,
           !existing.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workspace.stateSnapshotsBySessionID[sessionID] = state ?? AppSessionStateSnapshot(sessionID: sessionID)
            return existing
        }
        return nil
    }

    func syncDisplay(sessionID: String) {
        _ = ensureOverride(sessionID: sessionID)
        if let override = workspace.stateSnapshotsBySessionID[sessionID]?.llmOverride {
            model.selectedModel = override.model
            model.thinkingLevel = AppLLMThinkingLevel.normalized(override.thinkingLevel)
                ?? ((try? model.settingsRepository.loadSettings())?.defaultThinkingLevel ?? model.thinkingLevel)
            if let providerMode = AppLLMProviderMode(rawValue: override.providerMode) {
                model.providerMode = providerMode
            }
            if let connectionID = override.connectionID {
                model.activeConnectionID = connectionID
            }
        } else {
            applyGlobalDisplay()
        }
    }

    func syncCurrentSessionDisplay() {
        syncDisplay(sessionID: currentSessionID())
    }

    func syncDisplayInBackground(sessionID: String) {
        displaySyncTask?.cancel()
        let initialState = workspace.stateSnapshotsBySessionID[sessionID]
        let settingsRepository = model.settingsRepository
        let sessionRepository = sessionRepository
        displaySyncTask = Task { [weak self] in
            let preparation = await Task.detached(priority: .utility) {
                var state = initialState
                if state == nil {
                    state = try? sessionRepository?.loadSessionState(sessionID: sessionID)
                }
                let settings = try? settingsRepository.loadSettings()
                return DisplayPreparation(state: state, settings: settings)
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.currentSessionID() == sessionID else { return }
            if let state = preparation.state {
                self.workspace.stateSnapshotsBySessionID[sessionID] = state
            }
            self.applyDisplay(state: preparation.state, settings: preparation.settings)
        }
    }

    func syncActiveSession(to connection: AppLLMConnectionConfig) {
        let sessionID = currentSessionID()
        let settings = try? model.settingsRepository.loadSettings()
        let thinkingLevel = workspace.stateSnapshotsBySessionID[sessionID]?.llmOverride?.thinkingLevel
            ?? settings?.defaultThinkingLevel.rawValue
        var state = workspace.stateSnapshotsBySessionID[sessionID]
            ?? (try? sessionRepository?.loadSessionState(sessionID: sessionID))
            ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.llmOverride = SessionLLMOverride(
            providerMode: connection.providerMode.rawValue,
            model: connection.effectiveModel,
            baseURLString: nil,
            connectionID: connection.id,
            thinkingLevel: thinkingLevel
        )
        persist(state, sessionID: sessionID)
        model.providerMode = connection.providerMode
        model.selectedModel = connection.effectiveModel
        model.activeConnectionID = connection.id
    }

    func adoptGlobalDefaultForActiveSession() {
        let sessionID = currentSessionID()
        var state = workspace.stateSnapshotsBySessionID[sessionID] ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.llmOverride = nil
        persist(state, sessionID: sessionID)
        applyGlobalDisplay()
    }

    func clearOverride() {
        let sessionID = currentSessionID()
        var state = workspace.stateSnapshotsBySessionID[sessionID] ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.llmOverride = nil
        persist(state, sessionID: sessionID)
        applyGlobalDisplay()
        rebuildRuntime()
        Task { await model.reloadModelConnections() }
    }

    private func applyGlobalDisplay() {
        let settings = try? model.settingsRepository.loadSettings()
        applyGlobalDisplay(settings: settings)
    }

    private func applyDisplay(state: AppSessionStateSnapshot?, settings: AppLLMSettings?) {
        guard let override = state?.llmOverride else {
            applyGlobalDisplay(settings: settings)
            return
        }
        model.selectedModel = override.model
        model.thinkingLevel = AppLLMThinkingLevel.normalized(override.thinkingLevel)
            ?? settings?.defaultThinkingLevel
            ?? model.thinkingLevel
        if let providerMode = AppLLMProviderMode(rawValue: override.providerMode) {
            model.providerMode = providerMode
        }
        if let connectionID = override.connectionID {
            model.activeConnectionID = connectionID
        }
    }

    private func applyGlobalDisplay(settings: AppLLMSettings?) {
        model.selectedModel = settings?.defaultConnection?.effectiveModel ?? ""
        model.thinkingLevel = settings?.defaultThinkingLevel ?? model.thinkingLevel
        model.providerMode = settings?.defaultConnection?.providerMode ?? .openAICompatible
        model.defaultConnectionID = settings?.defaultConnectionID ?? ""
        model.activeConnectionID = settings?.defaultConnectionID ?? ""
    }

    private func persist(_ state: AppSessionStateSnapshot, sessionID: String) {
        var state = state
        state.updatedAt = Date()
        workspace.stateSnapshotsBySessionID[sessionID] = state
        try? sessionRepository?.saveSessionState(state, sessionID: sessionID)
    }
}
