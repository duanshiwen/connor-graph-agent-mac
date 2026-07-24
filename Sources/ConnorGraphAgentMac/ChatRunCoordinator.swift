import Foundation
import Observation
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Observable
final class ChatRunCoordinator {
    let model: ChatRunModel
    private(set) var fallbackSession: AgentSession
    private(set) var manager: NativeSessionManager?
    private(set) var runtimeFactory: AppGraphAgentRuntimeFactory?
    private var runIDsBySessionID: [String: String] = [:]
    private var backendsBySessionID: [String: AnyAgentBackend] = [:]
    private var backendsByRunID: [String: AnyAgentBackend] = [:]
    private var pendingCancellationReasons: [String: String] = [:]
    private var timelinesBySessionID: [String: [AgentEventPresentation]] = [:]
    private var timelinesByProcessKey: [String: [AgentEventPresentation]] = [:]
    private var isShutdown = false
    private var generation = 0
    private(set) var managerRevision = 0

    @ObservationIgnored var selectedSessionID: () -> String? = { nil }
    @ObservationIgnored var onTimelineChanged: (String, [AgentEventPresentation]) -> Void = { _, _ in }
    @ObservationIgnored var onSubmittingChanged: () -> Void = {}

    init(model: ChatRunModel, fallbackSession: AgentSession) {
        self.model = model
        self.fallbackSession = fallbackSession
    }

    var activeSession: AgentSession { manager?.session ?? fallbackSession }
    var activeTranscript: [AgentMessage] { manager?.session.messages ?? fallbackSession.messages }
    var isActive: Bool { !model.submittingSessionIDs.isEmpty }

    func replaceTranscript(_ messages: [AgentMessage]) {
        let previous = model.transcript
        model.transcript = messages
        model.transcriptRevision += 1
        releaseOffMain(previous)
    }

    func configureTranscriptPagination(totalCount: Int, nextBeforePosition: Int?) {
        model.totalTranscriptMessageCount = totalCount
        model.nextMessageBeforePosition = nextBeforePosition
    }

    @discardableResult
    func prependTranscript(_ messages: [AgentMessage], nextBeforePosition: Int?) -> Int {
        let existingIDs = Set(model.transcript.map(\.id))
        let prepended = messages.filter { !existingIDs.contains($0.id) }
        guard !prepended.isEmpty else {
            model.nextMessageBeforePosition = nextBeforePosition
            return 0
        }
        model.transcript.insert(contentsOf: prepended, at: 0)
        model.transcriptRevision += 1
        model.nextMessageBeforePosition = nextBeforePosition
        return prepended.count
    }

    func prepareSelection(sessionID: String) {
        replaceTranscript([])
        configureTranscriptPagination(totalCount: 0, nextBeforePosition: nil)
        replaceVisibleTimeline(timeline(sessionID: sessionID) ?? [])
        model.latestSummary = nil
        model.summaryMessage = nil
        model.lastContext = nil
        model.lastPromptInspection = nil
        refreshSelectedSubmittingState()
    }

    func applySelectedSnapshot(
        session: AgentSession,
        manager: NativeSessionManager?,
        timeline: [AgentEventPresentation],
        summary: AgentSessionSummary?
    ) {
        installManager(manager, fallbackSession: session)
        replaceTranscript(session.messages)
        setTimeline(timeline, sessionID: session.id)
        model.latestSummary = summary
        model.summaryMessage = nil
        model.lastContext = nil
        model.lastPromptInspection = nil
        refreshSelectedSubmittingState()
    }

    func applyPresentation(timeline: [AgentEventPresentation], summary: AgentSessionSummary?, sessionID: String) {
        setTimeline(timeline, sessionID: sessionID)
        model.latestSummary = summary
        model.summaryMessage = nil
        model.lastContext = nil
        model.lastPromptInspection = nil
    }

    func clearSelectedRuntime() {
        installManager(nil)
        replaceTranscript([])
        configureTranscriptPagination(totalCount: 0, nextBeforePosition: nil)
        replaceVisibleTimeline([])
        model.latestSummary = nil
        model.summaryMessage = nil
        model.lastContext = nil
        model.lastPromptInspection = nil
    }

    func prepareNewSession(_ session: AgentSession, manager: NativeSessionManager?) {
        installManager(manager, fallbackSession: session)
        replaceTranscript([])
        setTimeline([], sessionID: session.id)
        model.latestSummary = nil
        model.summaryMessage = nil
        model.lastContext = nil
        model.lastPromptInspection = nil
        refreshSelectedSubmittingState()
    }

    func applyOptimisticTranscript(_ messages: [AgentMessage], sessionID: String) {
        guard selectedSessionID() == sessionID else { return }
        replaceTranscript(messages)
        model.lastContext = nil
        model.lastPromptInspection = nil
    }

    @discardableResult
    func applyCompletedRun(
        manager: NativeSessionManager,
        session: AgentSession,
        summary: AgentSessionSummary?,
        submittedManagerRevision: Int? = nil
    ) -> Bool {
        let shouldRestoreSubmittedManager = submittedManagerRevision.map { $0 == managerRevision } ?? true
        if shouldRestoreSubmittedManager {
            installManager(manager, fallbackSession: session)
        } else {
            fallbackSession = session
        }
        replaceTranscript(manager.session.messages)
        replaceVisibleTimeline(manager.eventPresentations)
        model.latestSummary = summary
        model.lastContext = nil
        model.lastPromptInspection = nil
        return shouldRestoreSubmittedManager
    }

    @discardableResult
    func applyRecoveredRun(
        manager: NativeSessionManager,
        session: AgentSession,
        transcript: [AgentMessage],
        submittedManagerRevision: Int? = nil
    ) -> Bool {
        let shouldRestoreSubmittedManager = submittedManagerRevision.map { $0 == managerRevision } ?? true
        if shouldRestoreSubmittedManager {
            installManager(manager, fallbackSession: session)
        } else {
            fallbackSession = session
        }
        replaceTranscript(transcript)
        return shouldRestoreSubmittedManager
    }

    func installRuntimeFactory(_ factory: AppGraphAgentRuntimeFactory?) { runtimeFactory = factory }

    func makeManager(
        for session: AgentSession,
        permissionMode: AgentPermissionMode = .askToWrite,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration(),
        sessionWorkspace: AppSessionWorkspaceReference? = nil,
        sessionLLMOverride: SessionLLMOverride? = nil,
        remoteKnowledgeBaseIDs: [String]? = nil,
        allowedMCPToolNames: [String]? = nil
    ) -> NativeSessionManager? {
        runtimeFactory?.makeNativeSessionManager(
            session: session,
            permissionMode: permissionMode,
            configuration: configuration,
            sessionWorkspace: sessionWorkspace,
            sessionLLMOverride: sessionLLMOverride,
            remoteKnowledgeBaseIDs: remoteKnowledgeBaseIDs,
            allowedMCPToolNames: allowedMCPToolNames
        )
    }

    func makeAgentModelProvider(sessionLLMOverride: SessionLLMOverride?) -> AnyAgentModelProvider? {
        runtimeFactory?.makeAgentModelProvider(sessionLLMOverride: sessionLLMOverride)
    }

    func installManager(_ manager: NativeSessionManager?, fallbackSession: AgentSession? = nil) {
        guard !isShutdown else { return }
        if let fallbackSession { self.fallbackSession = fallbackSession }
        self.manager = manager
        managerRevision &+= 1
    }

    func updateFallbackSession(_ session: AgentSession) { guard !isShutdown else { return }; fallbackSession = session }
    func mutateManager(_ mutation: (inout NativeSessionManager) -> Void) {
        guard !isShutdown, var manager else { return }
        mutation(&manager)
        self.manager = manager
        managerRevision &+= 1
    }

    func begin(sessionID: String, backend: AnyAgentBackend) -> Bool {
        guard !isShutdown, !model.submittingSessionIDs.contains(sessionID) else { return false }
        backendsBySessionID[sessionID] = backend
        timelinesBySessionID[sessionID] = []
        timelinesByProcessKey = timelinesByProcessKey.filter { !$0.key.hasPrefix("\(sessionID):") }
        if selectedSessionID() == sessionID { replaceVisibleTimeline([]) }
        model.submittingSessionIDs.insert(sessionID)
        runIDsBySessionID.removeValue(forKey: sessionID)
        refreshSelectedSubmittingState()
        return true
    }

    func registerRun(sessionID: String, runID: String, backend: AnyAgentBackend) -> String? {
        guard !isShutdown, model.submittingSessionIDs.contains(sessionID) else { return nil }
        runIDsBySessionID[sessionID] = runID
        backendsByRunID[runID] = backend
        backendsBySessionID[sessionID] = backend
        return pendingCancellationReasons[sessionID]
    }

    func appendEvent(_ presentation: AgentEventPresentation, sessionID: String) {
        guard !isShutdown else { return }
        var timeline = timelinesBySessionID[sessionID] ?? []
        timeline.append(presentation)
        setTimeline(timeline, sessionID: sessionID)
    }

    func setTimeline(_ timeline: [AgentEventPresentation], sessionID: String) {
        guard !isShutdown else { return }
        timelinesBySessionID[sessionID] = timeline
        if selectedSessionID() == sessionID { replaceVisibleTimeline(timeline) }
        onTimelineChanged(sessionID, timeline)
    }

    func timeline(sessionID: String) -> [AgentEventPresentation]? { timelinesBySessionID[sessionID] }
    func selectedOrStoredTimeline(sessionID: String) -> [AgentEventPresentation] { timelinesBySessionID[sessionID] ?? model.eventTimeline }

    func cachedProcessTimeline(key: String) -> [AgentEventPresentation]? { timelinesByProcessKey[key] }
    func cacheProcessTimeline(_ timeline: [AgentEventPresentation], key: String) { timelinesByProcessKey[key] = timeline }
    func clearProcessTimelines() { timelinesByProcessKey.removeAll(keepingCapacity: true) }
    func clearProcessTimelines(sessionID: String) { timelinesByProcessKey = timelinesByProcessKey.filter { !$0.key.hasPrefix("\(sessionID):") } }

    private func replaceVisibleTimeline(_ timeline: [AgentEventPresentation]) {
        let previous = model.eventTimeline
        model.eventTimeline = timeline
        releaseOffMain(previous)
    }

    private func releaseOffMain<Value: Sendable>(_ value: Value) {
        Task.detached(priority: .background) {
            _fixLifetime(value)
        }
    }

    func backend(for approval: AgentPendingApproval) -> AnyAgentBackend? {
        backendsByRunID[approval.runID] ?? backendsBySessionID[approval.sessionID] ?? manager?.backend
    }

    enum CancellationRequest {
        case queued(reason: String)
        case alreadyQueued
        case active(sessionID: String, runID: String, reason: String, backend: AnyAgentBackend?)
        case unavailable
    }

    func requestCancellation(sessionID: String, reason: String) -> CancellationRequest {
        guard model.submittingSessionIDs.contains(sessionID) else { return .unavailable }
        guard let runID = runIDsBySessionID[sessionID] else {
            guard pendingCancellationReasons[sessionID] == nil else { return .alreadyQueued }
            pendingCancellationReasons[sessionID] = reason
            return .queued(reason: reason)
        }
        return .active(sessionID: sessionID, runID: runID, reason: reason, backend: backendsByRunID[runID] ?? backendsBySessionID[sessionID])
    }

    func cancelActive(sessionID: String, runID: String, reason: String, backend: AnyAgentBackend?) {
        backend?.abort(runID: runID)
        if backend == nil, selectedSessionID() == sessionID { mutateManager { $0.cancel(runID: runID, reason: reason) } }
        pendingCancellationReasons.removeValue(forKey: sessionID)
        finish(sessionID: sessionID)
    }

    func pendingCancellationReason(sessionID: String) -> String? { pendingCancellationReasons[sessionID] }
    func clearPendingCancellation(sessionID: String) { pendingCancellationReasons.removeValue(forKey: sessionID) }

    func finish(sessionID: String) {
        backendsBySessionID.removeValue(forKey: sessionID)
        if let runID = runIDsBySessionID[sessionID] { backendsByRunID.removeValue(forKey: runID) }
        model.submittingSessionIDs.remove(sessionID)
        runIDsBySessionID.removeValue(forKey: sessionID)
        refreshSelectedSubmittingState()
    }

    func removeSession(_ sessionID: String) {
        if let runID = runIDsBySessionID[sessionID] { backendsByRunID[runID]?.abort(runID: runID) }
        finish(sessionID: sessionID)
        pendingCancellationReasons.removeValue(forKey: sessionID)
        timelinesBySessionID.removeValue(forKey: sessionID)
        clearProcessTimelines(sessionID: sessionID)
    }

    func refreshSelectedSubmittingState() {
        model.isSubmitting = selectedSessionID().map { model.submittingSessionIDs.contains($0) } ?? false
        onSubmittingChanged()
    }

    func summarize(
        sessionID: String,
        repository: AppChatSessionRepository,
        provider: AnyLLMProvider,
        successMessage: String
    ) async throws {
        guard !isShutdown else { return }
        let currentGeneration = generation
        model.isSummarizing = true
        defer { if generation == currentGeneration { model.isSummarizing = false } }
        let summarizer = AgentSessionSummarizer(provider: provider)
        let summary = try await repository.summarizeSession(id: sessionID, using: summarizer)
        try Task.checkCancellation()
        guard !isShutdown, generation == currentGeneration else { return }
        model.latestSummary = summary
        model.summaryMessage = successMessage
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        generation += 1
        for (sessionID, runID) in runIDsBySessionID {
            (backendsByRunID[runID] ?? backendsBySessionID[sessionID])?.abort(runID: runID)
        }
        runIDsBySessionID.removeAll(); backendsByRunID.removeAll(); backendsBySessionID.removeAll(); pendingCancellationReasons.removeAll()
        model.submittingSessionIDs.removeAll(); model.isSubmitting = false
        manager = nil
        managerRevision &+= 1
        onSubmittingChanged()
    }
}
