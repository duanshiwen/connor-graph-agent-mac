import Testing
import ConnorGraphSearch
import ConnorGraphAgent

private actor ControllerPromptRecorder {
    private(set) var prompt: String?

    func record(_ prompt: String) {
        self.prompt = prompt
    }
}

private struct ControllerCapturingProvider: LLMProvider, Sendable {
    let recorder: ControllerPromptRecorder

    func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        await recorder.record(prompt)
        return LLMResponse(text: "Captured controller answer", citations: context.items.map(\.sourceID))
    }
}

@Test func agentChatControllerSubmitsPromptAndStoresTranscript() async throws {
    let agent = GraphAgent(
        session: AgentSession(id: "session-ui"),
        contextBuilder: AgentContextBuilder(hybridSearchService: TestHybridSearchService(hits: [
            GraphSearchHit(ownerType: .node, ownerID: "question-memory", title: "How should memory work?", text: "Use graph-backed context", score: 1.0, retrievalMethod: "test")
        ]), groupID: "default"),
        llmProvider: StubLLMProvider()
    )
    var controller = AgentChatController(agent: agent)

    let response = try await controller.submit("memory")

    #expect(response.answer.citations == ["node:question-memory"])
    #expect(controller.transcript.map(\.role) == [.user, .assistant])
    #expect(controller.lastContext?.items.map(\.sourceID) == ["node:question-memory"])
}

@Test func agentChatControllerSubmitsPromptWithSessionSummary() async throws {
    let recorder = ControllerPromptRecorder()
    let agent = GraphAgent(
        session: AgentSession(id: "session-ui"),
        contextBuilder: AgentContextBuilder(hybridSearchService: TestHybridSearchService(), groupID: "default"),
        llmProvider: ControllerCapturingProvider(recorder: recorder)
    )
    var controller = AgentChatController(agent: agent)
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-ui",
        content: "The previous session created manual summaries.",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )

    try await controller.submit("Next", sessionSummary: summary)
    let providerPrompt = try #require(await recorder.prompt)

    #expect(providerPrompt.contains("Previous session summary:"))
    #expect(providerPrompt.contains("The previous session created manual summaries."))
    #expect(providerPrompt.contains("Current user request:"))
    #expect(providerPrompt.contains("Next"))
    #expect(controller.transcript.first?.content == "Next")
}
