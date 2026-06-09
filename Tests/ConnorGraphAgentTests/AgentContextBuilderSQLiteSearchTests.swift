import Testing
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphAgent

private actor HybridSearchSpyState {
    private(set) var queries: [GraphSearchQuery] = []

    func record(_ query: GraphSearchQuery) {
        queries.append(query)
    }

    var recordedQueries: [GraphSearchQuery] { queries }
}

private struct SpyHybridSearchService: GraphHybridSearchService, Sendable {
    let state: HybridSearchSpyState
    let response: GraphSearchResponse

    func search(query: GraphSearchQuery) async throws -> GraphSearchResponse {
        await state.record(query)
        return response
    }
}

private actor HybridContextRecorder {
    private(set) var context: AgentContext?

    func record(_ context: AgentContext) {
        self.context = context
    }
}

private struct HybridContextCapturingProvider: LLMProvider, Sendable {
    let recorder: HybridContextRecorder

    func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        await recorder.record(context)
        return LLMResponse(text: "Captured", citations: context.items.map(\.sourceID))
    }
}

@Test func agentContextBuilderUsesHybridSearchService() async throws {
    let state = HybridSearchSpyState()
    let service = SpyHybridSearchService(
        state: state,
        response: GraphSearchResponse(hits: [
            GraphSearchHit(ownerType: .fact, ownerID: "fact-agent-os", title: "works_on", text: "诗闻正在设计 Agent OS 图谱存储层。", score: 1.0, retrievalMethod: "fts", sourceEpisodeIDs: ["episode-1"])
        ])
    )
    let builder = AgentContextBuilder(hybridSearchService: service, groupID: "default")

    let context = try await builder.context(for: "Agent OS")

    let queries = await state.recordedQueries
    #expect(queries.map(\.text) == ["Agent OS"])
    #expect(queries.map(\.groupID) == ["default"])
    #expect(context.items.map(\.sourceID) == ["fact:fact-agent-os"])
    #expect(context.renderedText.contains("Fact[works_on] 诗闻正在设计 Agent OS 图谱存储层。"))
}

@Test func graphAgentInjectsHybridSearchContextIntoProviderPrompt() async throws {
    let recorder = HybridContextRecorder()
    let service = SpyHybridSearchService(
        state: HybridSearchSpyState(),
        response: GraphSearchResponse(hits: [
            GraphSearchHit(ownerType: .fact, ownerID: "fact-agent-os", title: "works_on", text: "诗闻正在设计 Agent OS 图谱存储层。", score: 1.0, retrievalMethod: "fts", sourceEpisodeIDs: ["episode-1"])
        ])
    )
    let agent = GraphAgent(
        session: AgentSession(id: "session-1"),
        contextBuilder: AgentContextBuilder(hybridSearchService: service, groupID: "default"),
        llmProvider: HybridContextCapturingProvider(recorder: recorder)
    )

    let response = try await agent.ask("Agent OS")
    let context = try #require(await recorder.context)

    #expect(context.renderedText.contains("Fact[works_on] 诗闻正在设计 Agent OS 图谱存储层。"))
    #expect(response.answer.citations == ["fact:fact-agent-os"])
    #expect(response.session.messages.last?.contextSnapshot?.contains("fact:fact-agent-os") == true)
}

@Test func agentContextBuilderRendersFactEndpointGraphContext() async throws {
    let service = SpyHybridSearchService(
        state: HybridSearchSpyState(),
        response: GraphSearchResponse(hits: [
            GraphSearchHit(
                ownerType: .fact,
                ownerID: "fact-agent-os-context",
                title: "WORKS_ON",
                text: "诗闻正在设计 Agent OS 的图谱记忆。",
                score: 0.03,
                retrievalMethod: "hybrid",
                sourceEpisodeIDs: ["episode-1"],
                metadata: [
                    "graph_context": "fact_endpoints",
                    "source_node_title": "诗闻",
                    "source_node_type": "person",
                    "target_node_title": "Agent OS",
                    "target_node_type": "work_object",
                    "graph_context_node_ids": "node-shiwen,node-agent-os"
                ]
            )
        ])
    )
    let builder = AgentContextBuilder(hybridSearchService: service, groupID: "default")

    let context = try await builder.context(for: "Agent OS 图谱记忆")

    #expect(context.renderedText.contains("Fact[WORKS_ON] 诗闻正在设计 Agent OS 的图谱记忆。"))
    #expect(context.renderedText.contains("Graph endpoints: 诗闻(person) -> Agent OS(work_object)"))
    #expect(context.renderedText.contains("Graph node ids: node-shiwen,node-agent-os"))
}

@Test func graphAgentInjectsNodeAdjacentGraphContextIntoProviderPrompt() async throws {
    let recorder = HybridContextRecorder()
    let service = SpyHybridSearchService(
        state: HybridSearchSpyState(),
        response: GraphSearchResponse(hits: [
            GraphSearchHit(
                ownerType: .node,
                ownerID: "node-agent-os-context",
                title: "Agent OS",
                text: "本地优先 Agent 操作系统。",
                score: 0.03,
                retrievalMethod: "fts",
                metadata: [
                    "type": "work_object",
                    "graph_context": "adjacent_facts",
                    "adjacent_fact_ids": "fact-mentions,fact-works-on",
                    "adjacent_fact_relations": "MENTIONS,WORKS_ON",
                    "adjacent_node_ids": "node-graphiti,node-shiwen"
                ]
            )
        ])
    )
    let agent = GraphAgent(
        session: AgentSession(id: "session-graph-context"),
        contextBuilder: AgentContextBuilder(hybridSearchService: service, groupID: "default"),
        llmProvider: HybridContextCapturingProvider(recorder: recorder)
    )

    let response = try await agent.ask("Agent OS")
    let context = try #require(await recorder.context)

    #expect(context.renderedText.contains("Node[work_object] Agent OS: 本地优先 Agent 操作系统。"))
    #expect(context.renderedText.contains("Adjacent facts: fact-mentions,fact-works-on"))
    #expect(context.renderedText.contains("Adjacent relations: MENTIONS,WORKS_ON"))
    #expect(context.renderedText.contains("Adjacent node ids: node-graphiti,node-shiwen"))
    #expect(response.session.messages.last?.contextSnapshot?.contains("Adjacent facts: fact-mentions,fact-works-on") == true)
}
