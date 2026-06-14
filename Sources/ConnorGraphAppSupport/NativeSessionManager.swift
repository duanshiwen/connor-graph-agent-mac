import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory

public protocol AgentPendingApprovalRepository: Sendable {
    func upsert(pendingApproval approval: AgentPendingApproval) throws
}

public enum NativeSessionManagerError: Error, Sendable, Equatable, LocalizedError {
    case noUserMessageToRetry
    case runCancelled(String)

    public var errorDescription: String? {
        switch self {
        case .noUserMessageToRetry:
            "No user message is available to retry."
        case .runCancelled(let reason):
            reason
        }
    }
}

public struct NativeSessionRuntimeState: Codable, Sendable, Equatable {
    public var isProcessing: Bool
    public var activeRunID: String?
    public var queuedRunIDs: [String]
    public var lastRunID: String?
    public var lastStartedAt: Date?
    public var lastCompletedAt: Date?
    public var lastFailureMessage: String?
    public var cancellationReason: String?
    public var pendingApprovalCount: Int
    public var pendingPlanCount: Int

    public init(
        isProcessing: Bool = false,
        activeRunID: String? = nil,
        queuedRunIDs: [String] = [],
        lastRunID: String? = nil,
        lastStartedAt: Date? = nil,
        lastCompletedAt: Date? = nil,
        lastFailureMessage: String? = nil,
        cancellationReason: String? = nil,
        pendingApprovalCount: Int = 0,
        pendingPlanCount: Int = 0
    ) {
        self.isProcessing = isProcessing
        self.activeRunID = activeRunID
        self.queuedRunIDs = queuedRunIDs
        self.lastRunID = lastRunID
        self.lastStartedAt = lastStartedAt
        self.lastCompletedAt = lastCompletedAt
        self.lastFailureMessage = lastFailureMessage
        self.cancellationReason = cancellationReason
        self.pendingApprovalCount = pendingApprovalCount
        self.pendingPlanCount = pendingPlanCount
    }
}

public struct NativeSessionManager: Sendable {
    public var backend: AnyAgentBackend
    public var sessionRepository: AppChatSessionRepository
    public private(set) var session: AgentSession
    public private(set) var events: [AgentEvent]
    public private(set) var eventPresentations: [AgentEventPresentation]
    public private(set) var runtimeState: NativeSessionRuntimeState
    public var groupID: String
    public var permissionMode: AgentPermissionMode
    public var recentMessageLimit: Int

    // MARK: - Context Compression

    /// Persisted anchor state for context compression (loaded from Session Capsule).
    public private(set) var anchorState: SessionAnchorState?
    /// Model's context window size in tokens (for percentage-based budget).
    public var contextWindowSize: Int
    /// Compression pipeline (type-erased).  Nil when compression is disabled.
    private let compressionProvider: AnyLLMProvider?
    /// Recent message keep count for compression (default 7).
    public var compressionRecentMessageKeepCount: Int = 7

    private let presenter: AgentEventPresenter
    private let memoryIngestionService: MemoryIngestionService
    private let memoryStagingRepository: AppMemoryStagingBufferRepository?
    private let eventRecorder: AgentEventRecorder?
    private let pendingApprovalRepository: (any AgentPendingApprovalRepository)?

    public init<Backend: AgentBackend>(
        backend: Backend,
        sessionRepository: AppChatSessionRepository,
        session: AgentSession = AgentSession(),
        groupID: String = "default",
        permissionMode: AgentPermissionMode = .askToWrite,
        recentMessageLimit: Int = 6,
        memoryStagingRepository: AppMemoryStagingBufferRepository? = nil,
        memoryIngestionService: MemoryIngestionService = MemoryIngestionService(),
        eventRecorder: AgentEventRecorder? = nil,
        pendingApprovalRepository: (any AgentPendingApprovalRepository)? = nil,
        compressionProvider: AnyLLMProvider? = nil,
        contextWindowSize: Int = 200_000,
        anchorState: SessionAnchorState? = nil
    ) {
        self.backend = AnyAgentBackend(backend)
        self.sessionRepository = sessionRepository
        self.session = session
        self.events = []
        self.eventPresentations = []
        self.runtimeState = NativeSessionRuntimeState()
        self.groupID = groupID
        self.permissionMode = permissionMode
        self.recentMessageLimit = recentMessageLimit
        self.presenter = AgentEventPresenter()
        self.memoryStagingRepository = memoryStagingRepository
        self.memoryIngestionService = memoryIngestionService
        self.eventRecorder = eventRecorder
        self.pendingApprovalRepository = pendingApprovalRepository
        self.compressionProvider = compressionProvider
        self.contextWindowSize = contextWindowSize
        self.anchorState = anchorState
    }

    public init<Provider: AgentModelProvider>(
        loopController: AgentLoopController<Provider>,
        sessionRepository: AppChatSessionRepository,
        session: AgentSession = AgentSession(),
        groupID: String = "default",
        memoryStagingRepository: AppMemoryStagingBufferRepository? = nil,
        memoryIngestionService: MemoryIngestionService = MemoryIngestionService()
    ) {
        self.init(
            backend: AgentLoopBackend(loopController: loopController),
            sessionRepository: sessionRepository,
            session: session,
            groupID: groupID,
            permissionMode: loopController.configuration.permissionMode,
            memoryStagingRepository: memoryStagingRepository,
            memoryIngestionService: memoryIngestionService
        )
    }

    @discardableResult
    public mutating func submit(_ prompt: String) async throws -> AgentLoopChatResponse {
        try await submit(prompt, sessionSummary: nil)
    }

    @discardableResult
    public mutating func submit(
        _ prompt: String,
        sessionSummary: AgentSessionSummary?,
        displayPrompt: String? = nil,
        attachments: [AgentMessageAttachmentRef] = [],
        attachmentContextPlan: AttachmentContextPlan = AttachmentContextPlan(),
        onRunStarted: (@MainActor @Sendable (String) -> Void)? = nil,
        onEventPresentation: (@MainActor @Sendable (AgentEventPresentation) -> Void)? = nil
    ) async throws -> AgentLoopChatResponse {
        // MARK: - Context Compression Check
        // Check if cumulative tokens exceed the percentage-based threshold.\        // If so, compress older messages into the anchor state.
        try await maybeCompressContext()

        let recentMessages = Array(session.messages.suffix(max(0, recentMessageLimit)))
        let userMessage = session.appendUserMessage(displayPrompt ?? prompt, attachments: attachments)
        try persistSession()
        try persistMemoryStagingAfterUserMessage(userMessage)

        let request = AgentChatRequest(
            sessionID: session.id,
            groupID: groupID,
            userMessage: prompt,
            sessionSummary: sessionSummary,
            recentMessages: recentMessages,
            permissionMode: permissionMode,
            attachmentRefs: attachments,
            attachmentContextPlan: attachmentContextPlan,
            anchorState: anchorState
        )
        let now = Date()
        var run = AgentRun(
            id: request.runID,
            sessionID: session.id,
            groupID: groupID,
            status: .queued,
            startedAt: now,
            metadata: ["user_message_id": userMessage.id, "queue": "single-session"]
        )
        try sessionRepository.saveRun(run)
        if eventRecorder == nil {
            try sessionRepository.appendJournalEvent(
                runID: run.id,
                sessionID: session.id,
                kind: .runStarted,
                action: "message_persisted",
                message: "User message persisted before backend execution",
                metadata: ["message_id": userMessage.id]
            )
        }
        if eventRecorder == nil {
        try sessionRepository.appendJournalEvent(
                runID: run.id,
                sessionID: session.id,
                kind: .runStarted,
                action: "run_queued",
                message: "Session run queued",
                metadata: ["user_message_id": userMessage.id]
            )
        }
        runtimeState.queuedRunIDs.append(run.id)
        if let onRunStarted {
            await onRunStarted(run.id)
        }
        do {
            try throwIfRunCancelled(runID: run.id)
        } catch NativeSessionManagerError.runCancelled(let reason) {
            runtimeState.queuedRunIDs.removeAll { $0 == run.id }
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastRunID = run.id
            runtimeState.lastCompletedAt = Date()
            runtimeState.cancellationReason = reason
            _ = try appendTerminationMessage(
                "操作已终止：\(reason)",
                runID: run.id
            )
            throw NativeSessionManagerError.runCancelled(reason)
        }
        run.status = .running
        try sessionRepository.saveRun(run)
        if eventRecorder == nil {
        try sessionRepository.appendJournalEvent(
                runID: run.id,
                sessionID: session.id,
                kind: .runStarted,
                action: "run_started",
                message: "Session run started",
                metadata: ["user_message_id": userMessage.id]
            )
        }
        runtimeState.queuedRunIDs.removeAll { $0 == run.id }
        runtimeState.isProcessing = true
        runtimeState.activeRunID = request.runID
        runtimeState.lastRunID = request.runID
        runtimeState.lastStartedAt = now
        runtimeState.lastCompletedAt = nil
        runtimeState.lastFailureMessage = nil
        runtimeState.cancellationReason = nil

        var collectedEvents: [AgentEvent] = []
        var collectedPresentations: [AgentEventPresentation] = []
        var assistantMessage: AgentMessage?

        do {
            for try await event in backend.chat(request) {
                try throwIfRunCancelled(runID: run.id)
                collectedEvents.append(event)
                events.append(event)

                try recordBackendEvent(event, sequence: collectedEvents.count - 1)
                try recordPendingApprovalIfNeeded(event)
                if case .permissionRequested = event {
                    runtimeState.pendingApprovalCount += 1
                    var waitingRun = run
                    waitingRun.status = .waitingForApproval
                    try sessionRepository.saveRun(waitingRun)
        if eventRecorder == nil {
                    try sessionRepository.appendJournalEvent(
                            runID: run.id,
                            sessionID: session.id,
                            kind: .permissionRequested,
                            action: "run_waiting_for_approval",
                            message: "Run is waiting for approval"
                        )
        }
                }

                let presentation = presenter.presentation(for: event)
                collectedPresentations.append(presentation)
                eventPresentations.append(presentation)
                if let onEventPresentation {
                    await onEventPresentation(presentation)
                }

                if case .textComplete(let payload) = event {
                    assistantMessage = session.appendAssistantMessage(
                        payload.text,
                        citations: payload.citations,
                        contextSnapshot: payload.contextSnapshot
                    )
                    try persistSession()
                    if let assistantMessage {
                        try persistMemoryStagingAfterAssistantMessage(assistantMessage, runID: run.id)
                    }
                }
            }

            try throwIfRunCancelled(runID: run.id)
            let runFailure = collectedEvents.compactMap { event -> AgentRunFailure? in
                if case .runFailed(let failure) = event { return failure }
                return nil
            }.last
            if assistantMessage == nil, let runFailure {
                assistantMessage = try appendTerminationMessage(
                    "操作已终止：\(runFailure.message)",
                    runID: run.id
                )
            }
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = Date()
            var completedRun = run
            completedRun.status = runFailure == nil ? .completed : .failed
            completedRun.completedAt = runtimeState.lastCompletedAt
            if let runFailure {
                completedRun.metadata["failure"] = runFailure.message
                runtimeState.lastFailureMessage = runFailure.message
            }
            try sessionRepository.saveRun(completedRun)
        if eventRecorder == nil {
            try sessionRepository.appendJournalEvent(
                    runID: run.id,
                    sessionID: session.id,
                    kind: runFailure == nil ? .runCompleted : .runFailed,
                    action: runFailure == nil ? "run_completed" : "run_failed",
                    message: runFailure == nil ? "Session run completed" : (runFailure?.message ?? "Session run failed")
                )
        }
            return AgentLoopChatResponse(
                session: session,
                events: collectedEvents,
                eventPresentations: collectedPresentations,
                assistantMessage: assistantMessage
            )
        } catch NativeSessionManagerError.runCancelled(let reason) {
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = Date()
            runtimeState.cancellationReason = reason
            if var cancelledRun = try? sessionRepository.loadRun(id: run.id) {
                cancelledRun.status = .cancelled
                cancelledRun.completedAt = cancelledRun.completedAt ?? runtimeState.lastCompletedAt
                cancelledRun.metadata["cancellation_reason"] = cancelledRun.metadata["cancellation_reason"] ?? reason
                try? sessionRepository.saveRun(cancelledRun)
            }
            _ = try appendTerminationMessage(
                "操作已终止：\(reason)",
                runID: run.id
            )
            try persistSession()
            throw NativeSessionManagerError.runCancelled(reason)
        } catch {
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = Date()
            runtimeState.lastFailureMessage = String(describing: error)
            if let existingRun = try? sessionRepository.loadRun(id: run.id), existingRun.status == .cancelled {
                let reason = existingRun.metadata["cancellation_reason"] ?? "cancelled by user"
                runtimeState.cancellationReason = reason
                _ = try appendTerminationMessage(
                    "操作已终止：\(reason)",
                    runID: run.id
                )
                try persistSession()
                throw NativeSessionManagerError.runCancelled(reason)
            }
            var failedRun = run
            failedRun.status = .failed
            failedRun.completedAt = runtimeState.lastCompletedAt
            failedRun.metadata["failure"] = String(describing: error)
            try sessionRepository.saveRun(failedRun)
        if eventRecorder == nil {
            try sessionRepository.appendJournalEvent(
                    runID: run.id,
                    sessionID: session.id,
                    kind: .runFailed,
                    action: "run_failed",
                    message: String(describing: error)
                )
        }
            // Connor owns session state. A backend failure must not roll back the user's input.
            _ = try appendTerminationMessage(
                "操作已终止：\(String(describing: error))",
                runID: run.id
            )
            try persistSession()
            throw error
        }
    }

    @discardableResult
    public mutating func retryLastUserMessage() async throws -> AgentLoopChatResponse {
        guard let prompt = session.messages.last(where: { $0.role == .user })?.content else {
            throw NativeSessionManagerError.noUserMessageToRetry
        }
        return try await submit(prompt, sessionSummary: nil)
    }

    public mutating func cancelActiveRun(reason: String = "cancelled by user") {
        guard let runID = runtimeState.activeRunID else { return }
        cancel(runID: runID, reason: reason)
    }

    public mutating func cancel(runID: String, reason: String = "cancelled by user") {
        runtimeState.cancellationReason = reason
        runtimeState.queuedRunIDs.removeAll { $0 == runID }
        let completedAt = Date()
        if runtimeState.activeRunID == runID {
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = completedAt
        }
        runtimeState.lastRunID = runID
        if var run = try? sessionRepository.loadRun(id: runID) {
            run.status = .cancelled
            run.completedAt = completedAt
            run.metadata["cancellation_reason"] = reason
            try? sessionRepository.saveRun(run)
            try? sessionRepository.appendJournalEvent(
                runID: runID,
                sessionID: run.sessionID,
                kind: .runFailed,
                action: "run_cancelled",
                message: reason
            )
        }
        backend.abort(runID: runID)
    }

    public mutating func hydrateRuntimeState(now: Date = Date()) throws -> SessionOSRestoreSnapshot {
        let snapshot = try sessionRepository.restoreSnapshot(sessionID: session.id, now: now)
        runtimeState.activeRunID = snapshot.activeRuns.first(where: { $0.status == .running || $0.status == .waitingForApproval })?.id
        runtimeState.queuedRunIDs = snapshot.activeRuns.filter { $0.status == .queued || $0.status == .pending }.map(\.id)
        runtimeState.isProcessing = runtimeState.activeRunID != nil
        runtimeState.pendingApprovalCount = snapshot.pendingApprovalCount
        runtimeState.pendingPlanCount = snapshot.pendingPlans.count
        runtimeState.lastRunID = runtimeState.activeRunID ?? runtimeState.queuedRunIDs.first ?? runtimeState.lastRunID
        return snapshot
    }

    private func persistSession() throws {
        try sessionRepository.saveSession(session)
    }

    // MARK: - Context Compression

    /// Check if context compression should be triggered.
    /// If so, compress older messages into the anchor state.
    private mutating func maybeCompressContext() async throws {
        guard let provider = compressionProvider else { return }

        let tokenCount = SessionTokenCounter().estimate(messages: session.messages)
        let budget = SessionContextBudget(contextWindowSize: contextWindowSize)
        let status = budget.status(tokenCount: tokenCount.totalTokenCount)

        guard status >= .shouldCompress else { return }

        let pipeline = ContextCompressionPipeline(
            provider: provider,
            recentMessageKeepCount: compressionRecentMessageKeepCount
        )
        let compressed = try await pipeline.compress(
            messages: session.messages,
            existingAnchor: anchorState
        )
        anchorState = compressed.anchor
        // Persist anchor state to the session capsule
        try persistAnchorState()
    }

    /// Update anchor state externally (e.g., when loading from Session Capsule).
    public mutating func setAnchorState(_ anchor: SessionAnchorState?) {
        self.anchorState = anchor
    }

    private func persistAnchorState() throws {
        var snapshot = (try? sessionRepository.loadSessionState(sessionID: session.id))
            ?? AppSessionStateSnapshot(sessionID: session.id)
        snapshot.anchorState = anchorState
        snapshot.updatedAt = Date()
        try sessionRepository.saveSessionState(snapshot, sessionID: session.id)
    }

    @discardableResult
    private mutating func appendTerminationMessage(_ content: String, runID: String) throws -> AgentMessage {
        if let last = session.messages.last,
           last.role == .assistant,
           last.content.hasPrefix("操作已终止：") {
            try persistSession()
            return last
        }
        let message = session.appendAssistantMessage(content)
        try persistSession()
        try persistMemoryStagingAfterAssistantMessage(message, runID: runID)
        return message
    }

    private func throwIfRunCancelled(runID: String) throws {
        guard let run = try? sessionRepository.loadRun(id: runID), run.status == .cancelled else { return }
        throw NativeSessionManagerError.runCancelled(run.metadata["cancellation_reason"] ?? "cancelled by user")
    }

    private func recordBackendEvent(_ event: AgentEvent, sequence: Int) throws {
        guard let eventRecorder else { return }
        switch event {
        case .runStarted(let payload):
            try eventRecorder.recordRun(payload.run)
        case .runCompleted(let payload):
            try eventRecorder.recordRun(payload.run)
        default:
            break
        }
        try eventRecorder.record(event, sequence: sequence)
    }

    private func recordPendingApprovalIfNeeded(_ event: AgentEvent) throws {
        guard case .permissionRequested(let request) = event else { return }
        let approval = AgentPendingApproval(
            requestID: request.id,
            runID: request.runID,
            sessionID: request.sessionID,
            capability: request.capability,
            toolName: request.toolName,
            payloadJSON: request.payloadJSON
        )
        try pendingApprovalRepository?.upsert(pendingApproval: approval)
        try sessionRepository.savePendingApproval(approval)
    }

    private func persistMemoryStagingAfterUserMessage(_ message: AgentMessage) throws {
        guard let memoryStagingRepository else { return }
        let existingBuffer = try memoryStagingRepository.loadBuffer(sessionID: session.id)
        let result = memoryIngestionService.ingestUserMessage(
            message,
            sessionID: session.id,
            into: existingBuffer
        )
        try memoryStagingRepository.saveBuffer(result.buffer)
    }

    private func persistMemoryStagingAfterAssistantMessage(_ message: AgentMessage, runID: String? = nil) throws {
        guard let memoryStagingRepository else { return }
        let existingBuffer = try memoryStagingRepository.loadBuffer(sessionID: session.id)
        let result = memoryIngestionService.ingestAssistantMessage(
            message,
            sessionID: session.id,
            into: existingBuffer ?? MemoryStagingBuffer(sessionID: session.id)
        )
        try memoryStagingRepository.saveBuffer(result.buffer)
        try recordMemoryFeedbackSignals(from: result, runID: runID)
    }

    private func recordMemoryFeedbackSignals(from result: MemoryIngestionResult, runID: String?) throws {
        guard !result.triggerReasons.isEmpty else { return }
        let signals = AgentGraphMemoryFeedbackSignal.signals(from: result, runID: runID, sessionID: session.id)
        for signal in signals {
            try sessionRepository.appendJournalEvent(
                runID: runID ?? "memory-feedback-\(session.id)",
                sessionID: session.id,
                kind: .graphMemoryProposed,
                action: "memory_feedback_signal",
                message: signal.rationale,
                metadata: [
                    "signal_id": signal.id,
                    "trigger": signal.trigger.rawValue,
                    "candidate_kind": signal.candidateKind,
                    "importance": "\(signal.importance)",
                    "confidence": "\(signal.confidence)",
                    "source_buffer_id": signal.metadata["source_buffer_id"] ?? result.buffer.id,
                    "pending_bundle_count": signal.metadata["pending_bundle_count"] ?? "\(result.buffer.pendingBundles.count)"
                ]
            )
        }
    }
}
