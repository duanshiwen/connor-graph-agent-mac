import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch

public struct ObserveLogRecorder: Sendable, Equatable {
    public init() {}

    public func entry(for message: AgentMessage, sessionID: String) -> ObserveLogEntry {
        ObserveLogEntry(
            id: "observe-message-\(message.id)",
            timestamp: message.createdAt,
            kind: .observation,
            source: message.role == .user ? .user : .agent,
            content: message.content,
            sessionID: sessionID
        )
    }
}

public struct AgentContextBuilder: Sendable {
    public var searchIndex: InMemoryGraphSearchIndex
    public var assembler: ContextAssembler
    public var searchOptions: GraphSearchOptions

    public init(
        searchIndex: InMemoryGraphSearchIndex,
        assembler: ContextAssembler,
        searchOptions: GraphSearchOptions = .init(includeNeighborhood: true)
    ) {
        self.searchIndex = searchIndex
        self.assembler = assembler
        self.searchOptions = searchOptions
    }

    public func context(for query: String) throws -> AgentContext {
        let results = try searchIndex.search(query: query, options: searchOptions)
        return assembler.assemble(query: query, results: results)
    }
}

public struct LLMResponse: Sendable, Equatable {
    public var text: String
    public var citations: [String]

    public init(text: String, citations: [String]) {
        self.text = text
        self.citations = citations
    }
}

public protocol LLMProvider: Sendable {
    func complete(prompt: String, context: AgentContext) async throws -> LLMResponse
}

public struct StubLLMProvider: LLMProvider, Sendable, Equatable {
    public init() {}

    public func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        let citations = context.items.map(\.sourceID)
        let contextSummary: String
        if context.items.isEmpty {
            contextSummary = "No graph context was found."
        } else {
            contextSummary = context.items.map { $0.content }.joined(separator: "\n")
        }
        return LLMResponse(
            text: "Stub answer for: \(prompt)\n\nGrounded context:\n\(contextSummary)",
            citations: citations
        )
    }
}

public struct GraphAgentAskResponse: Sendable, Equatable {
    public var answer: LLMResponse
    public var context: AgentContext
    public var session: AgentSession
    public var observeLogEntries: [ObserveLogEntry]
    public var promptInspection: AgentChatPromptInspection?

    public init(answer: LLMResponse, context: AgentContext, session: AgentSession, observeLogEntries: [ObserveLogEntry]) {
        self.init(
            answer: answer,
            context: context,
            session: session,
            observeLogEntries: observeLogEntries,
            promptInspection: nil
        )
    }

    public init(
        answer: LLMResponse,
        context: AgentContext,
        session: AgentSession,
        observeLogEntries: [ObserveLogEntry],
        promptInspection: AgentChatPromptInspection?
    ) {
        self.answer = answer
        self.context = context
        self.session = session
        self.observeLogEntries = observeLogEntries
        self.promptInspection = promptInspection
    }
}

public struct GraphAgent<Provider: LLMProvider>: Sendable {
    public var session: AgentSession
    public var contextBuilder: AgentContextBuilder
    public var llmProvider: Provider
    public var observeLogRecorder: ObserveLogRecorder
    public var recentMessageLimit: Int

    public init(
        session: AgentSession,
        contextBuilder: AgentContextBuilder,
        llmProvider: Provider,
        observeLogRecorder: ObserveLogRecorder = ObserveLogRecorder(),
        recentMessageLimit: Int = 6
    ) {
        self.session = session
        self.contextBuilder = contextBuilder
        self.llmProvider = llmProvider
        self.observeLogRecorder = observeLogRecorder
        self.recentMessageLimit = recentMessageLimit
    }

    public func ask(_ prompt: String) async throws -> GraphAgentAskResponse {
        try await ask(prompt, sessionSummary: nil)
    }

    public func ask(_ prompt: String, sessionSummary: AgentSessionSummary?) async throws -> GraphAgentAskResponse {
        let recentMessages = Array(session.messages.suffix(max(0, recentMessageLimit)))
        var updatedSession = session
        let userMessage = updatedSession.appendUserMessage(prompt)
        let observeEntry = observeLogRecorder.entry(for: userMessage, sessionID: updatedSession.id)
        let context = try contextBuilder.context(for: prompt)
        let promptContext = AgentChatPromptContext(
            userPrompt: prompt,
            sessionSummary: sessionSummary,
            recentMessages: recentMessages
        )
        let effectivePrompt = promptContext.renderedPrompt
        let answer = try await llmProvider.complete(prompt: effectivePrompt, context: context)
        updatedSession.appendAssistantMessage(answer.text, citations: answer.citations, contextSnapshot: context.renderedText)
        return GraphAgentAskResponse(
            answer: answer,
            context: context,
            session: updatedSession,
            observeLogEntries: [observeEntry],
            promptInspection: promptContext.inspection
        )
    }
}
