import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphSearch

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
