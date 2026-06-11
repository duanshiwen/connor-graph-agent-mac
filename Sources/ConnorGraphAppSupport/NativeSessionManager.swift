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
    public var lastRunID: String?
    public var lastStartedAt: Date?
    public var lastCompletedAt: Date?
    public var lastFailureMessage: String?
    public var cancellationReason: String?

    public init(
        isProcessing: Bool = false,
        activeRunID: String? = nil,
        lastRunID: String? = nil,
        lastStartedAt: Date? = nil,
        lastCompletedAt: Date? = nil,
        lastFailureMessage: String? = nil,
        cancellationReason: String? = nil
    ) {
        self.isProcessing = isProcessing
        self.activeRunID = activeRunID
        self.lastRunID = lastRunID
        self.lastStartedAt = lastStartedAt
        self.lastCompletedAt = lastCompletedAt
        self.lastFailureMessage = lastFailureMessage
        self.cancellationReason = cancellationReason
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
        let userMessage = session.appendUserMessage(prompt)
        try persistSession()
        try persistMemoryStagingAfterUserMessage(userMessage)

        let request = AgentChatRequest(
            sessionID: session.id,
            groupID: groupID,
            userMessage: prompt,
            permissionMode: permissionMode
        )
        runtimeState.isProcessing = true
        runtimeState.activeRunID = request.runID
        runtimeState.lastRunID = request.runID
        runtimeState.lastStartedAt = Date()
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
        return try await submit(prompt)
    }

    public mutating func cancelActiveRun(reason: String = "cancelled by user") {
        guard let runID = runtimeState.activeRunID else { return }
        cancel(runID: runID, reason: reason)
    }

    public mutating func cancel(runID: String, reason: String = "cancelled by user") {
        runtimeState.cancellationReason = reason
        if runtimeState.activeRunID == runID {
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = Date()
        }
        runtimeState.lastRunID = runID
        backend.abort(runID: runID)
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
        guard let pendingApprovalRepository,
              case .permissionRequested(let request) = event
        else { return }
        let approval = AgentPendingApproval(
            requestID: request.id,
            runID: request.runID,
            sessionID: request.sessionID,
            capability: request.capability,
            toolName: request.toolName,
            payloadJSON: request.payloadJSON
        )
        try pendingApprovalRepository.upsert(pendingApproval: approval)
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
