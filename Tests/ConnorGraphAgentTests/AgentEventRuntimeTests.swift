import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore

@Test func agentRunStartedEventCarriesCommercialRuntimeMetadata() throws {
    let run = AgentRun(
        id: "run-1",
        sessionID: "session-1",
        groupID: "default",
        status: .running,
        startedAt: Date(timeIntervalSince1970: 1_000),
        model: "stub",
        metadata: ["source": "test"]
    )
    let event = AgentEvent.runStarted(AgentRunStartedEvent(run: run))

    #expect(event.runID == "run-1")
    #expect(event.sessionID == "session-1")
    #expect(event.kind == .runStarted)
}

@Test func graphAgentChatEmitsEventStreamAroundExistingAskPath() async throws {
    let agent = GraphAgent(
        session: AgentSession(id: "session-1"),
        contextBuilder: AgentContextBuilder(hybridSearchService: TestHybridSearchService(), groupID: "default"),
        llmProvider: StubLLMProvider()
    )

    var events: [AgentEvent] = []
    for try await event in agent.chat("What should memory do?") {
        events.append(event)
    }

    #expect(events.map(\.kind) == [.runStarted, .textComplete, .assistantMessageCreated, .runCompleted])
    #expect(events.compactMap { event -> String? in
        if case .textComplete(let complete) = event { return complete.text }
        return nil
    }.first?.contains("What should memory do?") == true)
}
