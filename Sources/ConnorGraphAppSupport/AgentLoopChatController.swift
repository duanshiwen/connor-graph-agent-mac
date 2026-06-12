import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory

public struct AgentLoopChatResponse: Sendable, Equatable {
    public var session: AgentSession
    public var events: [AgentEvent]
    public var eventPresentations: [AgentEventPresentation]
    public var assistantMessage: AgentMessage?

    public init(session: AgentSession, events: [AgentEvent], eventPresentations: [AgentEventPresentation], assistantMessage: AgentMessage?) {
        self.session = session
        self.events = events
        self.eventPresentations = eventPresentations
        self.assistantMessage = assistantMessage
    }
}

public struct AgentLoopChatController<Provider: AgentModelProvider>: Sendable {
    public var loopController: AgentLoopController<Provider>
    public private(set) var session: AgentSession
    public private(set) var transcript: [AgentMessage]
    public private(set) var events: [AgentEvent]
    public private(set) var eventPresentations: [AgentEventPresentation]
    public var groupID: String
    public var recentMessageLimit: Int

    private let presenter: AgentEventPresenter
    private let memoryIngestionService: MemoryIngestionService
    private let memoryStagingRepository: AppMemoryStagingBufferRepository?

    public init(
        loopController: AgentLoopController<Provider>,
        session: AgentSession = AgentSession(),
        groupID: String = "default",
        recentMessageLimit: Int = 6,
        memoryStagingRepository: AppMemoryStagingBufferRepository? = nil,
        memoryIngestionService: MemoryIngestionService = MemoryIngestionService()
    ) {
        self.loopController = loopController
        self.session = session
        self.transcript = session.messages
        self.events = []
        self.eventPresentations = []
        self.groupID = groupID
        self.recentMessageLimit = recentMessageLimit
        self.presenter = AgentEventPresenter()
        self.memoryStagingRepository = memoryStagingRepository
        self.memoryIngestionService = memoryIngestionService
    }

    @discardableResult
    public mutating func submit(_ prompt: String) async throws -> AgentLoopChatResponse {
        let recentMessages = Array(session.messages.suffix(max(0, recentMessageLimit)))
        let userMessage = session.appendUserMessage(prompt)
        transcript = session.messages
        try persistMemoryStagingAfterUserMessage(userMessage)
        let request = AgentChatRequest(
            sessionID: session.id,
            groupID: groupID,
            userMessage: prompt,
            recentMessages: recentMessages,
            permissionMode: loopController.configuration.permissionMode
        )

        var collectedEvents: [AgentEvent] = []
        var collectedPresentations: [AgentEventPresentation] = []
        var assistantMessage: AgentMessage?

        do {
            for try await event in loopController.run(request) {
                collectedEvents.append(event)
                let presentation = presenter.presentation(for: event)
                collectedPresentations.append(presentation)
                events.append(event)
                eventPresentations.append(presentation)
                if case .textComplete(let payload) = event {
                    assistantMessage = session.appendAssistantMessage(
                        payload.text,
                        citations: payload.citations,
                        contextSnapshot: payload.contextSnapshot
                    )
                    transcript = session.messages
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
            if session.messages.last?.id == userMessage.id {
                // Preserve the user's submitted message for recoverability and audit visibility.
                transcript = session.messages
            }
            throw error
        }
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
