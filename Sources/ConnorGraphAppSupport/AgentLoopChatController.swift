import Foundation
import ConnorGraphAgent
import ConnorGraphCore

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

    private let presenter: AgentEventPresenter

    public init(loopController: AgentLoopController<Provider>, session: AgentSession = AgentSession(), groupID: String = "default") {
        self.loopController = loopController
        self.session = session
        self.transcript = session.messages
        self.events = []
        self.eventPresentations = []
        self.groupID = groupID
        self.presenter = AgentEventPresenter()
    }

    @discardableResult
    public mutating func submit(_ prompt: String) async throws -> AgentLoopChatResponse {
        let userMessage = session.appendUserMessage(prompt)
        transcript = session.messages
        let request = AgentChatRequest(
            sessionID: session.id,
            groupID: groupID,
            userMessage: prompt,
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
                    assistantMessage = session.appendAssistantMessage(payload.text, citations: payload.citations)
                    transcript = session.messages
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
}
