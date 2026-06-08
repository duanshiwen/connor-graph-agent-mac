import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent

@Test func agentSessionAcceptsUserMessages() throws {
    var session = AgentSession(id: "session-1")

    let message = session.appendUserMessage("How should memory work?")

    #expect(message.role == .user)
    #expect(message.content == "How should memory work?")
    #expect(session.messages.map(\.content) == ["How should memory work?"])
}

@Test func agentSessionTracksTitleAndUpdatedAt() throws {
    let createdAt = Date(timeIntervalSince1970: 1_000)
    let updatedAt = Date(timeIntervalSince1970: 2_000)

    let session = AgentSession(id: "session-1", title: "Planning", messages: [], createdAt: createdAt, updatedAt: updatedAt)

    #expect(session.title == "Planning")
    #expect(session.createdAt == createdAt)
    #expect(session.updatedAt == updatedAt)
}

@Test func assistantMessageCanCarryCitationsAndContextSnapshot() throws {
    let message = AgentMessage(
        id: "message-1",
        role: .assistant,
        content: "Use graph memory.",
        createdAt: Date(timeIntervalSince1970: 1_000),
        citations: ["node:memory"],
        contextSnapshot: "Node[work_object] Memory"
    )

    #expect(message.citations == ["node:memory"])
    #expect(message.contextSnapshot == "Node[work_object] Memory")
}

@Test func userMessageCanBeRecordedAsObserveLogEntry() throws {
    let session = AgentSession(id: "session-1")
    let message = AgentMessage(id: "message-1", role: .user, content: "Remember this insight")

    let entry = ObserveLogRecorder().entry(for: message, sessionID: session.id)

    #expect(entry.kind == .observation)
    #expect(entry.source == .user)
    #expect(entry.sessionID == "session-1")
    #expect(entry.content == "Remember this insight")
}

@Test func agentContextBuilderCallsSearchAndAssembler() throws {
    let node = GraphNode.workObject(id: "work-object-agent-os", title: "Agent OS", summary: "Graph-backed agent system")
    let searchIndex = InMemoryGraphSearchIndex(nodes: [node], edges: [], observeLogEntries: [])
    let builder = AgentContextBuilder(searchIndex: searchIndex, assembler: ContextAssembler())

    let context = try builder.context(for: "graph backed")

    #expect(context.query == "graph backed")
    #expect(context.items.map(\.sourceID) == ["node:work-object-agent-os"])
}

@Test func stubLLMProviderReturnsDeterministicAnswerWithCitations() async throws {
    let context = AgentContext(
        query: "How should memory work?",
        items: [
            AgentContextItem(sourceID: "node:work-object-agent-os", kind: .node, content: "Node[work_object] Agent OS: Graph-backed memory", reason: "matched node")
        ]
    )
    let provider = StubLLMProvider()

    let response = try await provider.complete(prompt: "How should memory work?", context: context)

    #expect(response.text.contains("How should memory work?"))
    #expect(response.citations == ["node:work-object-agent-os"])
}

@Test func graphAgentAskReturnsAnswerAndCitedContext() async throws {
    let question = GraphNode.question(id: "question-memory", title: "How should memory work?")
    let answer = GraphNode.answer(id: "answer-graph", title: "Use graph-backed context", summary: "Use a graph store as runtime knowledge.")
    let edge = SemanticEdge.answeredBy(questionID: question.id, answerID: answer.id)
    let searchIndex = InMemoryGraphSearchIndex(nodes: [question, answer], edges: [edge], observeLogEntries: [])
    let agent = GraphAgent(
        session: AgentSession(id: "session-1"),
        contextBuilder: AgentContextBuilder(searchIndex: searchIndex, assembler: ContextAssembler()),
        llmProvider: StubLLMProvider()
    )

    let response = try await agent.ask("memory")

    #expect(response.answer.text.contains("memory"))
    #expect(response.context.items.contains { $0.sourceID == "node:question-memory" })
    #expect(response.answer.citations.contains("node:question-memory"))
    #expect(response.session.messages.map(\.role) == [.user, .assistant])
    #expect(response.observeLogEntries.count == 1)
    #expect(response.observeLogEntries[0].content == "memory")
}
