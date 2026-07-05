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
    private let memoryOSRepository: AppMemoryOSRepository?
    private let memoryOSIngestionService: MemoryOSIngestionService
    private let memoryOSFacade: AppMemoryOSFacade?
    private let memoryOSIngestionWriter: MemoryOSIngestionWriter?

    public init(
        loopController: AgentLoopController<Provider>,
        session: AgentSession = AgentSession(),
        groupID: String = "default",
        recentMessageLimit: Int = 6,
        memoryOSRepository: AppMemoryOSRepository? = nil,
        memoryOSIngestionService: MemoryOSIngestionService = MemoryOSIngestionService(),
        memoryOSFacade: AppMemoryOSFacade? = nil
    ) {
        self.loopController = loopController
        self.session = session
        self.transcript = session.messages
        self.events = []
        self.eventPresentations = []
        self.groupID = groupID
        self.recentMessageLimit = recentMessageLimit
        self.presenter = AgentEventPresenter()
        self.memoryOSRepository = memoryOSRepository
        self.memoryOSIngestionService = memoryOSIngestionService
        self.memoryOSFacade = memoryOSFacade
        self.memoryOSIngestionWriter = memoryOSFacade.map(MemoryOSIngestionWriter.init(facade:))
    }

    public func flushMemoryOSIngestion() async throws {
        try await memoryOSIngestionWriter?.flush()
    }

    @discardableResult
    public mutating func submit(_ prompt: String) async throws -> AgentLoopChatResponse {
        let recentMessages = Array(session.messages.suffix(max(0, recentMessageLimit)))
        let userMessage = session.appendUserMessage(prompt)
        transcript = session.messages
        try await persistMemoryOSAfterUserMessage(userMessage)
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
                        try await persistMemoryOSAfterAssistantMessage(assistantMessage)
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

    private func persistMemoryOSAfterUserMessage(_ message: AgentMessage) async throws {
        if let memoryOSIngestionWriter {
            await memoryOSIngestionWriter.enqueueChatMessage(
                messageID: message.id,
                sessionID: session.id,
                role: "user",
                content: message.content,
                occurredAt: message.createdAt
            )
            return
        }
        guard let memoryOSRepository else { return }
        let result = memoryOSIngestionService.ingest(MemoryOSIngestionInput(
            sourceType: .chatMessage,
            sourceID: message.id,
            title: "User message",
            content: message.content,
            occurredAt: message.createdAt,
            sessionID: session.id
        ))
        try memoryOSRepository.save(result)
    }

    private func persistMemoryOSAfterAssistantMessage(_ message: AgentMessage) async throws {
        if let memoryOSIngestionWriter {
            await memoryOSIngestionWriter.enqueueChatMessage(
                messageID: message.id,
                sessionID: session.id,
                role: "assistant",
                content: message.content,
                occurredAt: message.createdAt
            )
            return
        }
        guard let memoryOSRepository else { return }
        let result = memoryOSIngestionService.ingest(MemoryOSIngestionInput(
            sourceType: .assistantMessage,
            sourceID: message.id,
            title: "Assistant message",
            content: message.content,
            occurredAt: message.createdAt,
            sessionID: session.id
        ))
        try memoryOSRepository.save(result)
    }
}
