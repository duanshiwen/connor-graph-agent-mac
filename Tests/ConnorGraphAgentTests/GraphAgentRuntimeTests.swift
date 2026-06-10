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
        citations: ["entity:memory"],
        contextSnapshot: "Node[work_object] Memory"
    )

    #expect(message.citations == ["entity:memory"])
    #expect(message.contextSnapshot == "Node[work_object] Memory")
}

@Test func assistantMessageCanCarryPromptInspectionSnapshot() throws {
    let snapshot = AgentPromptInspectionSnapshot(
        includesSummary: true,
        recentMessageCount: 3,
        currentRequest: "What next?",
        renderedPrompt: "Previous session summary..."
    )
    let message = AgentMessage(
        id: "message-1",
        role: .assistant,
        content: "Answer",
        promptInspection: snapshot
    )

    #expect(message.promptInspection == snapshot)
}

@Test func agentMessageCodableRoundTripsPromptInspectionSnapshot() throws {
    let snapshot = AgentPromptInspectionSnapshot(
        includesSummary: true,
        recentMessageCount: 2,
        currentRequest: "What next?",
        renderedPrompt: "Rendered prompt",
        renderedPromptCharacterCount: 24_000,
        estimatedPromptTokenCount: 6_000,
        promptBudgetStatus: .warning
    )
    let message = AgentMessage(
        id: "message-1",
        role: .assistant,
        content: "Answer",
        promptInspection: snapshot
    )

    let data = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(AgentMessage.self, from: data)

    #expect(decoded.promptInspection == snapshot)
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

@Test func agentContextBuilderUsesHybridSearch() async throws {
    let builder = AgentContextBuilder(hybridSearchService: TestHybridSearchService(hits: [
        GraphSearchHit(ownerType: .entity, ownerID: "work-object-agent-os", title: "Agent OS", text: "Graph-backed agent system", score: 1.0, retrievalMethod: "test", metadata: ["type": "work_object"])
    ]), groupID: "default")

    let context = try await builder.context(for: "graph backed")

    #expect(context.query == "graph backed")
    #expect(context.items.map(\.sourceID) == ["entity:work-object-agent-os"])
}

@Test func stubLLMProviderReturnsDeterministicAnswerWithCitations() async throws {
    let context = AgentContext(
        query: "How should memory work?",
        items: [
            AgentContextItem(sourceID: "entity:work-object-agent-os", kind: .node, content: "Node[work_object] Agent OS: Graph-backed memory", reason: "matched node")
        ]
    )
    let provider = StubLLMProvider()

    let response = try await provider.complete(prompt: "How should memory work?", context: context)

    #expect(response.text.contains("How should memory work?"))
    #expect(response.citations == ["entity:work-object-agent-os"])
}

@Test func graphAgentAskReturnsAnswerAndCitedContext() async throws {
    let agent = GraphAgent(
        session: AgentSession(id: "session-1"),
        contextBuilder: AgentContextBuilder(hybridSearchService: TestHybridSearchService(hits: [
            GraphSearchHit(ownerType: .entity, ownerID: "question-memory", title: "How should memory work?", text: "", score: 1.0, retrievalMethod: "test"),
            GraphSearchHit(ownerType: .entity, ownerID: "answer-graph", title: "Use graph-backed context", text: "Use a graph store as runtime knowledge.", score: 0.8, retrievalMethod: "test")
        ]), groupID: "default"),
        llmProvider: StubLLMProvider()
    )

    let response = try await agent.ask("memory")

    #expect(response.answer.text.contains("memory"))
    #expect(response.context.items.contains { $0.sourceID == "entity:question-memory" })
    #expect(response.answer.citations.contains("entity:question-memory"))
    #expect(response.session.messages.map(\.role) == [.user, .assistant])
    #expect(response.observeLogEntries.count == 1)
    #expect(response.observeLogEntries[0].content == "memory")
}

private actor RuntimePromptRecorder {
    private(set) var prompt: String?

    func record(_ prompt: String) {
        self.prompt = prompt
    }
}

private struct RuntimeCapturingProvider: LLMProvider, Sendable {
    let recorder: RuntimePromptRecorder

    func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        await recorder.record(prompt)
        return LLMResponse(text: "Captured answer", citations: context.items.map(\.sourceID))
    }
}

@Test func graphAgentReturnsPromptInspectionForAsk() async throws {
    let recorder = RuntimePromptRecorder()
    let session = AgentSession(
        id: "session-1",
        messages: [
            AgentMessage(id: "message-1", role: .user, content: "Earlier question"),
            AgentMessage(id: "message-2", role: .assistant, content: "Earlier answer")
        ]
    )
    let agent = GraphAgent(
        session: session,
        contextBuilder: AgentContextBuilder(hybridSearchService: TestHybridSearchService(), groupID: "default"),
        llmProvider: RuntimeCapturingProvider(recorder: recorder),
        recentMessageLimit: 1
    )
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "Summary content",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )

    let response = try await agent.ask("What next?", sessionSummary: summary)
    let inspection = try #require(response.promptInspection)

    #expect(inspection.includesSummary)
    #expect(inspection.recentMessageCount == 1)
    #expect(inspection.currentRequest == "What next?")
    #expect(inspection.renderedPrompt.contains("Previous session summary:"))
    #expect(inspection.renderedPrompt.contains("Recent conversation:"))
    #expect(inspection.renderedPrompt.contains("Current user request:"))
}

@Test func graphAgentStoresPromptInspectionOnAssistantMessage() async throws {
    let recorder = RuntimePromptRecorder()
    let session = AgentSession(
        id: "session-1",
        messages: [
            AgentMessage(id: "message-1", role: .user, content: "Earlier question"),
            AgentMessage(id: "message-2", role: .assistant, content: "Earlier answer")
        ]
    )
    let agent = GraphAgent(
        session: session,
        contextBuilder: AgentContextBuilder(hybridSearchService: TestHybridSearchService(), groupID: "default"),
        llmProvider: RuntimeCapturingProvider(recorder: recorder),
        recentMessageLimit: 1
    )

    let response = try await agent.ask("What next?")
    let assistantMessage = try #require(response.session.messages.last)

    #expect(assistantMessage.role == .assistant)
    let snapshot = try #require(assistantMessage.promptInspection)
    #expect(!snapshot.includesSummary)
    #expect(snapshot.recentMessageCount == 1)
    #expect(snapshot.currentRequest == "What next?")
    #expect(snapshot.renderedPrompt?.contains("Current user request:") == true)
}

@Test func graphAgentStoresPolicyFilteredPromptInspectionSnapshot() async throws {
    let recorder = RuntimePromptRecorder()
    let agent = GraphAgent(
        session: AgentSession(id: "session-1"),
        contextBuilder: AgentContextBuilder(hybridSearchService: TestHybridSearchService(), groupID: "default"),
        llmProvider: RuntimeCapturingProvider(recorder: recorder),
        promptInspectionSnapshotPolicy: AgentPromptInspectionSnapshotPolicy(includeRenderedPrompt: false)
    )

    let response = try await agent.ask("What next?")
    let responseInspection = try #require(response.promptInspection)
    let assistantMessage = try #require(response.session.messages.last)
    let snapshot = try #require(assistantMessage.promptInspection)

    #expect(responseInspection.renderedPrompt == "What next?")
    #expect(snapshot.currentRequest == "What next?")
    #expect(snapshot.renderedPrompt == nil)
}

@Test func graphAgentIncludesRecentConversationWindowInProviderPrompt() async throws {
    let recorder = RuntimePromptRecorder()
    let session = AgentSession(
        id: "session-1",
        messages: [
            AgentMessage(id: "message-1", role: .user, content: "Earlier question"),
            AgentMessage(id: "message-2", role: .assistant, content: "Earlier answer"),
            AgentMessage(id: "message-3", role: .user, content: "Follow-up detail")
        ]
    )
    let agent = GraphAgent(
        session: session,
        contextBuilder: AgentContextBuilder(hybridSearchService: TestHybridSearchService(), groupID: "default"),
        llmProvider: RuntimeCapturingProvider(recorder: recorder),
        recentMessageLimit: 2
    )

    let response = try await agent.ask("What next?")
    let providerPrompt = try #require(await recorder.prompt)

    #expect(providerPrompt.contains("Recent conversation:"))
    #expect(providerPrompt.contains("Assistant: Earlier answer"))
    #expect(providerPrompt.contains("User: Follow-up detail"))
    #expect(!providerPrompt.contains("User: Earlier question"))
    #expect(providerPrompt.contains("Current user request:"))
    #expect(providerPrompt.contains("What next?"))
    #expect(response.session.messages.last { $0.role == .user }?.content == "What next?")
    #expect(!response.session.messages.last { $0.role == .user }!.content.contains("Recent conversation"))
}

@Test func graphAgentInjectsSessionSummaryIntoProviderPrompt() async throws {
    let recorder = RuntimePromptRecorder()
    let agent = GraphAgent(
        session: AgentSession(id: "session-1"),
        contextBuilder: AgentContextBuilder(hybridSearchService: TestHybridSearchService(), groupID: "default"),
        llmProvider: RuntimeCapturingProvider(recorder: recorder)
    )
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "Phase 18 added manual summary persistence.",
        sourceMessageCount: 4,
        lastMessageID: "message-4"
    )

    let response = try await agent.ask("What next?", sessionSummary: summary)
    let providerPrompt = try #require(await recorder.prompt)

    #expect(providerPrompt.contains("Previous session summary:"))
    #expect(providerPrompt.contains("Phase 18 added manual summary persistence."))
    #expect(providerPrompt.contains("Current user request:"))
    #expect(providerPrompt.contains("What next?"))
    #expect(response.session.messages.first?.content == "What next?")
    #expect(!response.session.messages.first!.content.contains("Previous session summary"))
}
