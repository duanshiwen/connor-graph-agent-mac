import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private struct RecordingAgentBackend: AgentBackend {
    let answer: String

    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let run = AgentRun(
                id: request.runID,
                sessionID: request.sessionID,
                groupID: request.groupID,
                status: .running,
                model: "recording-backend",
                metadata: ["runtime": "test-agent-backend"]
            )
            continuation.yield(.runStarted(AgentRunStartedEvent(run: run)))
            continuation.yield(.textComplete(AgentTextCompleteEvent(
                runID: request.runID,
                sessionID: request.sessionID,
                text: answer,
                citations: ["backend:test"]
            )))
            var completedRun = run
            completedRun.status = .completed
            completedRun.completedAt = Date()
            continuation.yield(.runCompleted(AgentRunCompletedEvent(run: completedRun)))
            continuation.finish()
        }
    }
}

private func temporaryBackendSessionDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func nativeSessionManagerSubmitsThroughAgentBackendAbstraction() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryBackendSessionDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "backend-session", title: "New Chat")
    try repository.saveSession(session)
    var manager = NativeSessionManager(
        backend: RecordingAgentBackend(answer: "Answer from backend abstraction"),
        sessionRepository: repository,
        session: session
    )

    let response = try await manager.submit("Use backend abstraction")
    let loaded = try #require(try repository.loadSession(id: "backend-session"))

    #expect(response.session.messages.map(\.role) == [.user, .assistant])
    #expect(loaded.messages.last?.content == "Answer from backend abstraction")
    #expect(response.events.map(\.kind) == [.runStarted, .textComplete, .runCompleted])
}
