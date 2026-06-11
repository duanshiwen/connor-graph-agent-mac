import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private final class PhaseACountingBackend: AgentBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var prompts: [String] = []

    var submittedPrompts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return prompts
    }

    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        lock.lock()
        prompts.append(request.userMessage)
        lock.unlock()
        return AsyncThrowingStream { continuation in
            let run = AgentRun(id: request.runID, sessionID: request.sessionID, groupID: request.groupID, status: .running, model: "counting")
            continuation.yield(.runStarted(AgentRunStartedEvent(run: run)))
            continuation.yield(.textComplete(AgentTextCompleteEvent(runID: request.runID, sessionID: request.sessionID, text: "answer for \(request.userMessage)")))
            var completed = run
            completed.status = .completed
            completed.completedAt = Date()
            continuation.yield(.runCompleted(AgentRunCompletedEvent(run: completed)))
            continuation.finish()
        }
    }
}

private func phaseARound2Store() throws -> SQLiteGraphKernelStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    let store = try SQLiteGraphKernelStore(path: url.path)
    try store.migrate()
    return store
}

@Test func nativeSessionManagerCanRetryLastUserMessage() async throws {
    let store = try phaseARound2Store()
    let repository = AppChatSessionRepository(store: store)
    let session = try repository.createSession(title: "Retry")
    let backend = PhaseACountingBackend()
    var manager = NativeSessionManager(backend: backend, sessionRepository: repository, session: session)

    _ = try await manager.submit("retry me")
    _ = try await manager.retryLastUserMessage()

    #expect(backend.submittedPrompts == ["retry me", "retry me"])
    #expect(manager.session.messages.map(\.role) == [.user, .assistant, .user, .assistant])
}

@Test func textDeltaBufferFlushesByThresholdAndOnCompletion() {
    var buffer = AgentTextDeltaBuffer(configuration: AgentTextDeltaBufferConfiguration(characterThreshold: 6))

    #expect(buffer.append(AgentTextDeltaEvent(runID: "run", sessionID: "session", text: "Hel")) == nil)
    let firstFlush = buffer.append(AgentTextDeltaEvent(runID: "run", sessionID: "session", text: "lo!"))
    #expect(firstFlush?.text == "Hello!")

    #expect(buffer.append(AgentTextDeltaEvent(runID: "run", sessionID: "session", text: "Bye")) == nil)
    let finalFlush = buffer.flush(runID: "run", sessionID: "session")
    #expect(finalFlush?.text == "Bye")
    #expect(buffer.flush(runID: "run", sessionID: "session") == nil)
}

@Test func usageTrackerAggregatesModelUsageIntoBudgetSnapshot() async throws {
    let tracker = AgentRuntimeUsageTracker(configuration: AgentBudgetConfiguration(maxTotalTokens: 100, warningThresholdRatio: 0.5))

    let first = await tracker.record(AgentModelUsage(promptTokens: 20, completionTokens: 10))
    let second = await tracker.record(AgentModelUsage(promptTokens: 15, completionTokens: 5))

    #expect(first.totalTokens == 30)
    #expect(first.status == .ok)
    #expect(second.promptTokens == 35)
    #expect(second.completionTokens == 15)
    #expect(second.totalTokens == 50)
    #expect(second.status == .warning)
}
