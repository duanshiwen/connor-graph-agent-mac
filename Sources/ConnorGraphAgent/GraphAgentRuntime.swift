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
    private var hybridSearchService: any GraphHybridSearchService
    public private(set) var groupID: String
    private var limit: Int

    public init(
        hybridSearchService: any GraphHybridSearchService,
        groupID: String,
        limit: Int = 20
    ) {
        self.hybridSearchService = hybridSearchService
        self.groupID = groupID
        self.limit = limit
    }

    public func context(for query: String) async throws -> AgentContext {
        let response = try await hybridSearchService.search(query: GraphSearchQuery(text: query, groupID: groupID, limit: limit))
        return AgentContext(query: query, items: response.hits.map(contextItem))
    }

    private func contextItem(_ hit: GraphSearchHit) -> AgentContextItem {
        AgentContextItem(
            sourceID: hit.id,
            kind: resultKind(for: hit.ownerType),
            content: renderedContent(for: hit),
            reason: "matched via \(hit.retrievalMethod)"
        )
    }

    private func resultKind(for ownerType: GraphIndexOwnerType) -> GraphSearchResultKind {
        switch ownerType {
        case .node: .node
        case .fact: .edge
        case .episode: .observeLog
        }
    }

    private func renderedContent(for hit: GraphSearchHit) -> String {
        switch hit.ownerType {
        case .node:
            let type = hit.metadata["type"] ?? "node"
            var lines = ["Node[\(type)] \(hit.title): \(hit.text)"]
            if hit.metadata["graph_context"] == "adjacent_facts" {
                if let adjacentFactIDs = hit.metadata["adjacent_fact_ids"], !adjacentFactIDs.isEmpty {
                    lines.append("Adjacent facts: \(adjacentFactIDs)")
                }
                if let adjacentRelations = hit.metadata["adjacent_fact_relations"], !adjacentRelations.isEmpty {
                    lines.append("Adjacent relations: \(adjacentRelations)")
                }
                if let adjacentNodeIDs = hit.metadata["adjacent_node_ids"], !adjacentNodeIDs.isEmpty {
                    lines.append("Adjacent node ids: \(adjacentNodeIDs)")
                }
            }
            return lines.joined(separator: "\n")
        case .fact:
            var lines = ["Fact[\(hit.title)] \(hit.text)"]
            if hit.metadata["graph_context"] == "fact_endpoints" {
                let sourceTitle = hit.metadata["source_node_title"]
                let sourceType = hit.metadata["source_node_type"]
                let targetTitle = hit.metadata["target_node_title"]
                let targetType = hit.metadata["target_node_type"]
                if let sourceTitle, let sourceType, let targetTitle, let targetType {
                    lines.append("Graph endpoints: \(sourceTitle)(\(sourceType)) -> \(targetTitle)(\(targetType))")
                }
                if let nodeIDs = hit.metadata["graph_context_node_ids"], !nodeIDs.isEmpty {
                    lines.append("Graph node ids: \(nodeIDs)")
                }
            }
            return lines.joined(separator: "\n")
        case .episode:
            let sourceType = hit.metadata["source_type"] ?? "episode"
            return "Episode[\(sourceType)] \(hit.title): \(hit.text)"
        }
    }
}

public enum AgentContextBuilderError: Error, Sendable, Equatable {
    case asyncContextRequired
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
    public var promptInspectionSnapshotPolicy: AgentPromptInspectionSnapshotPolicy

    public init(
        session: AgentSession,
        contextBuilder: AgentContextBuilder,
        llmProvider: Provider,
        observeLogRecorder: ObserveLogRecorder = ObserveLogRecorder(),
        recentMessageLimit: Int = 6
    ) {
        self.init(
            session: session,
            contextBuilder: contextBuilder,
            llmProvider: llmProvider,
            observeLogRecorder: observeLogRecorder,
            recentMessageLimit: recentMessageLimit,
            promptInspectionSnapshotPolicy: AgentPromptInspectionSnapshotPolicy()
        )
    }

    public init(
        session: AgentSession,
        contextBuilder: AgentContextBuilder,
        llmProvider: Provider,
        observeLogRecorder: ObserveLogRecorder = ObserveLogRecorder(),
        recentMessageLimit: Int = 6,
        promptInspectionSnapshotPolicy: AgentPromptInspectionSnapshotPolicy
    ) {
        self.session = session
        self.contextBuilder = contextBuilder
        self.llmProvider = llmProvider
        self.observeLogRecorder = observeLogRecorder
        self.recentMessageLimit = recentMessageLimit
        self.promptInspectionSnapshotPolicy = promptInspectionSnapshotPolicy
    }

    public func ask(_ prompt: String) async throws -> GraphAgentAskResponse {
        try await ask(prompt, sessionSummary: nil)
    }

    public func ask(_ prompt: String, sessionSummary: AgentSessionSummary?) async throws -> GraphAgentAskResponse {
        let recentMessages = Array(session.messages.suffix(max(0, recentMessageLimit)))
        var updatedSession = session
        let userMessage = updatedSession.appendUserMessage(prompt)
        let observeEntry = observeLogRecorder.entry(for: userMessage, sessionID: updatedSession.id)
        let context = try await contextBuilder.context(for: prompt)
        let promptContext = AgentChatPromptContext(
            userPrompt: prompt,
            sessionSummary: sessionSummary,
            recentMessages: recentMessages
        )
        let effectivePrompt = promptContext.renderedPrompt
        let answer = try await llmProvider.complete(prompt: effectivePrompt, context: context)
        updatedSession.appendAssistantMessage(
            answer.text,
            citations: answer.citations,
            contextSnapshot: context.renderedText,
            promptInspection: promptInspectionSnapshotPolicy.snapshot(for: promptContext.inspection)
        )
        return GraphAgentAskResponse(
            answer: answer,
            context: context,
            session: updatedSession,
            observeLogEntries: [observeEntry],
            promptInspection: promptContext.inspection
        )
    }

    public func chat(_ prompt: String, sessionSummary: AgentSessionSummary? = nil) -> AsyncThrowingStream<AgentEvent, Error> {
        let request = AgentChatRequest(
            sessionID: session.id,
            groupID: contextBuilder.groupIdentifier,
            userMessage: prompt,
            sessionSummary: sessionSummary
        )
        return chat(request)
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var run = AgentRun(
                    id: request.runID,
                    sessionID: request.sessionID,
                    groupID: request.groupID,
                    status: .running,
                    model: String(describing: Provider.self),
                    metadata: ["runtime": "graph-agent"]
                )
                continuation.yield(.runStarted(AgentRunStartedEvent(run: run)))
                do {
                    let response = try await ask(request.userMessage, sessionSummary: request.sessionSummary)
                    continuation.yield(.textComplete(AgentTextCompleteEvent(
                        runID: run.id,
                        sessionID: run.sessionID,
                        text: response.answer.text,
                        citations: response.answer.citations
                    )))
                    if let assistantMessage = response.session.messages.last, assistantMessage.role == .assistant {
                        continuation.yield(.assistantMessageCreated(assistantMessage))
                    }
                    run.status = .completed
                    run.completedAt = Date()
                    continuation.yield(.runCompleted(AgentRunCompletedEvent(run: run)))
                    continuation.finish()
                } catch {
                    run.status = .failed
                    run.completedAt = Date()
                    continuation.yield(.runFailed(AgentRunFailure(
                        runID: run.id,
                        sessionID: run.sessionID,
                        message: String(describing: error)
                    )))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public extension AgentContextBuilder {
    var groupIdentifier: String { groupID }
}
