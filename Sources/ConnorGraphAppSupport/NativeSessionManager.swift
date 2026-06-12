import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory

public protocol AgentPendingApprovalRepository: Sendable {
    func upsert(pendingApproval approval: AgentPendingApproval) throws
}

public enum NativeSessionManagerError: Error, Sendable, Equatable, LocalizedError {
    case noUserMessageToRetry

    public var errorDescription: String? {
        switch self {
        case .noUserMessageToRetry: "No user message is available to retry."
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
        pendingApprovalRepository: (any AgentPendingApprovalRepository)? = nil
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
    public mutating func submit(_ prompt: String, sessionSummary: AgentSessionSummary?) async throws -> AgentLoopChatResponse {
        let recentMessages = Array(session.messages.suffix(max(0, recentMessageLimit)))
        let userMessage = session.appendUserMessage(prompt)
        try persistSession()
        try persistMemoryStagingAfterUserMessage(userMessage)

        let request = AgentChatRequest(
            sessionID: session.id,
            groupID: groupID,
            userMessage: prompt,
            sessionSummary: sessionSummary,
            recentMessages: recentMessages,
            permissionMode: permissionMode
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

                if case .textComplete(let payload) = event {
                    assistantMessage = session.appendAssistantMessage(
                        payload.text,
                        citations: payload.citations,
                        contextSnapshot: payload.contextSnapshot
                    )
                    try persistSession()
                    if let assistantMessage {
                        try persistMemoryStagingAfterAssistantMessage(assistantMessage)
                    }
                }
            }

            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = Date()
            var completedRun = run
            completedRun.status = .completed
            completedRun.completedAt = runtimeState.lastCompletedAt
            try sessionRepository.saveRun(completedRun)
        if eventRecorder == nil {
            try sessionRepository.appendJournalEvent(
                    runID: run.id,
                    sessionID: session.id,
                    kind: .runCompleted,
                    action: "run_completed",
                    message: "Session run completed"
                )
        }
            return AgentLoopChatResponse(
                session: session,
                events: collectedEvents,
                eventPresentations: collectedPresentations,
                assistantMessage: assistantMessage
            )
        } catch {
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = Date()
            runtimeState.lastFailureMessage = String(describing: error)
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

    private func persistMemoryStagingAfterAssistantMessage(_ message: AgentMessage) throws {
        guard let memoryStagingRepository else { return }
        let existingBuffer = try memoryStagingRepository.loadBuffer(sessionID: session.id)
        let result = memoryIngestionService.ingestAssistantMessage(
            message,
            sessionID: session.id,
            into: existingBuffer ?? MemoryStagingBuffer(sessionID: session.id)
        )
        try memoryStagingRepository.saveBuffer(result.buffer)
    }
}
