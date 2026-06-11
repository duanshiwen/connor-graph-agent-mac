import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory

public struct NativeSessionManager: Sendable {
    public var backend: AnyAgentBackend
    public var sessionRepository: AppChatSessionRepository
    public private(set) var session: AgentSession
    public private(set) var events: [AgentEvent]
    public private(set) var eventPresentations: [AgentEventPresentation]
    public var groupID: String
    public var permissionMode: AgentPermissionMode

    private let presenter: AgentEventPresenter
    private let memoryIngestionService: MemoryIngestionService
    private let memoryStagingRepository: AppMemoryStagingBufferRepository?
    private let eventRecorder: AgentEventRecorder?

    public init<Backend: AgentBackend>(
        backend: Backend,
        sessionRepository: AppChatSessionRepository,
        session: AgentSession = AgentSession(),
        groupID: String = "default",
        permissionMode: AgentPermissionMode = .askToWrite,
        memoryStagingRepository: AppMemoryStagingBufferRepository? = nil,
        memoryIngestionService: MemoryIngestionService = MemoryIngestionService(),
        eventRecorder: AgentEventRecorder? = nil
    ) {
        self.backend = AnyAgentBackend(backend)
        self.sessionRepository = sessionRepository
        self.session = session
        self.events = []
        self.eventPresentations = []
        self.groupID = groupID
        self.permissionMode = permissionMode
        self.presenter = AgentEventPresenter()
        self.memoryStagingRepository = memoryStagingRepository
        self.memoryIngestionService = memoryIngestionService
        self.eventRecorder = eventRecorder
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

        var collectedEvents: [AgentEvent] = []
        var collectedPresentations: [AgentEventPresentation] = []
        var assistantMessage: AgentMessage?

        do {
            for try await event in backend.chat(request) {
                collectedEvents.append(event)
                events.append(event)

                try recordBackendEvent(event, sequence: collectedEvents.count - 1)

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

            return AgentLoopChatResponse(
                session: session,
                events: collectedEvents,
                eventPresentations: collectedPresentations,
                assistantMessage: assistantMessage
            )
        } catch {
            // Connor owns session state. A backend failure must not roll back the user's input.
            try persistSession()
            throw error
        }
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
