import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private final class RecordingAgentBackend: AgentBackend, @unchecked Sendable {
    let answer: String
    private let lock = NSLock()
    private var capturedRequests: [AgentChatRequest] = []

    var requests: [AgentChatRequest] {
        lock.withLock { capturedRequests }
    }

    init(answer: String) {
        self.answer = answer
    }

    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        lock.withLock { capturedRequests.append(request) }
        return AsyncThrowingStream { continuation in
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
    let backend = RecordingAgentBackend(answer: "Answer from backend abstraction")
    var manager = NativeSessionManager(
        backend: backend,
        sessionRepository: repository,
        session: session
    )

    let response = try await manager.submit("Use backend abstraction")
    let loaded = try #require(try repository.loadSession(id: "backend-session"))

    #expect(response.session.messages.map(\.role) == [.user, .assistant])
    #expect(loaded.messages.last?.content == "Answer from backend abstraction")
    #expect(response.events.map(\.kind) == [.runStarted, .textComplete, .runCompleted])
    #expect(backend.requests.map(\.userMessage) == ["Use backend abstraction"])
}

@Test func nativeSessionManagerPassesExplicitPersonContextsToAgentRequest() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryBackendSessionDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "person-context-session", title: "New Chat")
    try repository.saveSession(session)
    let backend = RecordingAgentBackend(answer: "Answer")
    var manager = NativeSessionManager(
        backend: backend,
        sessionRepository: repository,
        session: session
    )
    let profile = PersonProfile(
        id: ContactID(rawValue: "person-duan-fuqiang"),
        displayName: "段福强",
        emails: [ContactEmailAddress(email: "oisin.duan@apecho.com")]
    )

    _ = try await manager.submit(
        "@段福强 帮我给他发封邮件",
        sessionSummary: nil,
        explicitPersonContexts: [PersonContextSnapshot(profile: profile)]
    )

    let request = try #require(backend.requests.first)
    #expect(request.userMessage == "@段福强 帮我给他发封邮件")
    #expect(request.explicitPersonContexts.map(\.profile.id.rawValue) == ["person-duan-fuqiang"])
    #expect(request.normalizedPrompt.contains("emails: oisin.duan@apecho.com"))
}
