import Foundation
import ConnorGraphMemory
import ConnorGraphSearch

public enum AgentRole: String, Codable, Sendable, Equatable {
    case user
    case assistant
    case system
}

public struct AgentMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var role: AgentRole
    public var content: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, role: AgentRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct AgentSession: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var messages: [AgentMessage]
    public var createdAt: Date

    public init(id: String = UUID().uuidString, messages: [AgentMessage] = [], createdAt: Date = Date()) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
    }

    @discardableResult
    public mutating func appendUserMessage(_ content: String) -> AgentMessage {
        let message = AgentMessage(role: .user, content: content)
        messages.append(message)
        return message
    }

    @discardableResult
    public mutating func appendAssistantMessage(_ content: String) -> AgentMessage {
        let message = AgentMessage(role: .assistant, content: content)
        messages.append(message)
        return message
    }
}

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

    public init(answer: LLMResponse, context: AgentContext, session: AgentSession, observeLogEntries: [ObserveLogEntry]) {
        self.answer = answer
        self.context = context
        self.session = session
        self.observeLogEntries = observeLogEntries
    }
}

public struct GraphAgent<Provider: LLMProvider>: Sendable {
    public var session: AgentSession
    public var contextBuilder: AgentContextBuilder
    public var llmProvider: Provider
    public var observeLogRecorder: ObserveLogRecorder

    public init(
        session: AgentSession,
        contextBuilder: AgentContextBuilder,
        llmProvider: Provider,
        observeLogRecorder: ObserveLogRecorder = ObserveLogRecorder()
    ) {
        self.session = session
        self.contextBuilder = contextBuilder
        self.llmProvider = llmProvider
        self.observeLogRecorder = observeLogRecorder
    }

    public func ask(_ prompt: String) async throws -> GraphAgentAskResponse {
        var updatedSession = session
        let userMessage = updatedSession.appendUserMessage(prompt)
        let observeEntry = observeLogRecorder.entry(for: userMessage, sessionID: updatedSession.id)
        let context = try contextBuilder.context(for: prompt)
        let answer = try await llmProvider.complete(prompt: prompt, context: context)
        updatedSession.appendAssistantMessage(answer.text)
        return GraphAgentAskResponse(
            answer: answer,
            context: context,
            session: updatedSession,
            observeLogEntries: [observeEntry]
        )
    }
}
