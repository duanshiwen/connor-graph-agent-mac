import Testing
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphAgent

@Test func agentChatControllerSubmitsPromptAndStoresTranscript() async throws {
    let node = GraphNode.question(id: "question-memory", title: "How should memory work?", summary: "Use graph-backed context")
    let index = InMemoryGraphSearchIndex(nodes: [node], edges: [], observeLogEntries: [])
    let agent = GraphAgent(
        session: AgentSession(id: "session-ui"),
        contextBuilder: AgentContextBuilder(searchIndex: index, assembler: ContextAssembler()),
        llmProvider: StubLLMProvider()
    )
    var controller = AgentChatController(agent: agent)

    let response = try await controller.submit("memory")

    #expect(response.answer.citations == ["node:question-memory"])
    #expect(controller.transcript.map(\.role) == [.user, .assistant])
    #expect(controller.lastContext?.items.map(\.sourceID) == ["node:question-memory"])
}
