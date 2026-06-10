import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphSearch

private actor CapturingFinalAnswerProvider: AgentModelProvider {
    let modelID = "capturing-final"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)
    private(set) var lastRequest: AgentModelRequest?

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        lastRequest = request
        return AgentModelResponse(text: "Grounded final answer", usage: AgentModelUsage(promptTokens: 12, completionTokens: 4))
    }
}

private actor ScriptedModelProvider: AgentModelProvider {
    let modelID = "scripted"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)
    private var responses: [AgentModelResponse]

    init(responses: [AgentModelResponse]) {
        self.responses = responses
    }

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        responses.removeFirst()
    }
}

@Test func agentLoopRunsGraphToolThenFinalAnswer() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-1", name: "graph_search", argumentsJSON: #"{"query":"memory"}"#)],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: "Use graph memory.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
            finishReason: .stop
        )
    ])
    var registry = AgentToolRegistry()
    registry.register(GraphSearchTool(searchService: TestHybridSearchService(hits: [
        GraphSearchHit(ownerType: .node, ownerID: "node-memory", title: "Memory", text: "Graph memory", score: 1.0, retrievalMethod: "test")
    ])))
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-1", userMessage: "How should memory work?")) {
        events.append(event)
    }

    #expect(events.map(\.kind).contains(.toolStarted))
    #expect(events.map(\.kind).contains(.toolFinished))
    #expect(events.map(\.kind).contains(.textComplete))
    #expect(events.last?.kind == .runCompleted)
}

@Test func agentLoopInjectsInitialGraphContextIntoModelRequest() async throws {
    let provider = CapturingFinalAnswerProvider()
    let contextBuilder = AgentContextBuilder(
        hybridSearchService: TestHybridSearchService(hits: [
            GraphSearchHit(
                ownerType: .episode,
                ownerID: "episode-1",
                title: "Preference memory",
                text: "诗闻喜欢结构化推进。",
                score: 1.0,
                retrievalMethod: "test",
                metadata: ["source_type": "chat"]
            )
        ]),
        groupID: "default",
        limit: 3
    )
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        contextBuilder: contextBuilder
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-context", userMessage: "我偏好什么方式推进？")) {
        events.append(event)
    }

    let request = await provider.lastRequest
    #expect(request?.messages.contains(where: { $0.role == .system && $0.content.contains("Relevant Graph Memory Context") }) == true)
    #expect(request?.messages.contains(where: { $0.content.contains("诗闻喜欢结构化推进") }) == true)
    let textComplete = events.compactMap { event -> AgentTextCompleteEvent? in
        if case .textComplete(let payload) = event { return payload }
        return nil
    }.first
    #expect(textComplete?.citations == ["episode:episode-1"])
    #expect(textComplete?.contextSnapshot?.contains("诗闻喜欢结构化推进") == true)
}
