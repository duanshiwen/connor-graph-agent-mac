import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private final class PhaseADelayedBackend: AgentBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var aborted: [String] = []
    var abortedRunIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return aborted
    }

    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.runStarted(AgentRunStartedEvent(run: AgentRun(
                    id: request.runID,
                    sessionID: request.sessionID,
                    groupID: request.groupID,
                    status: .running,
                    model: "phase-a-delayed",
                    metadata: ["runtime": "phase-a-test"]
                ))))
                try? await Task.sleep(nanoseconds: 150_000_000)
                continuation.yield(.textComplete(AgentTextCompleteEvent(
                    runID: request.runID,
                    sessionID: request.sessionID,
                    text: "Phase A response"
                )))
                continuation.yield(.runCompleted(AgentRunCompletedEvent(run: AgentRun(
                    id: request.runID,
                    sessionID: request.sessionID,
                    groupID: request.groupID,
                    status: .completed,
                    completedAt: Date(),
                    model: "phase-a-delayed"
                ))))
                continuation.finish()
            }
        }
    }

    func abort(runID: String) {
        lock.lock()
        aborted.append(runID)
        lock.unlock()
    }
}

private func phaseATemporaryRoot(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
}

private func phaseAStore() throws -> SQLiteGraphKernelStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    let store = try SQLiteGraphKernelStore(path: url.path)
    try store.migrate()
    return store
}

@Test func nativeSessionManagerTracksProcessingStateAndCanCancelActiveRun() async throws {
    let store = try phaseAStore()
    let repository = AppChatSessionRepository(store: store)
    let session = try repository.createSession(title: "Phase A")
    let backend = PhaseADelayedBackend()
    var manager = NativeSessionManager(backend: backend, sessionRepository: repository, session: session)

    _ = try await manager.submit("start long run")

    let activeRunID = try #require(manager.runtimeState.lastRunID)
    manager.cancel(runID: activeRunID, reason: "user cancelled")

    #expect(backend.abortedRunIDs == [activeRunID])
    #expect(manager.runtimeState.isProcessing == false)
    #expect(manager.runtimeState.activeRunID == nil)
    #expect(manager.runtimeState.lastRunID == activeRunID)
}

@Test func agentEventReplayerRestoresPersistedRuntimeEvents() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let run = AgentRun(id: "run-replay", sessionID: "session-replay", groupID: "default", status: .running, model: "test-model")
    let event = PersistedAgentEvent(
        runID: run.id,
        sessionID: run.sessionID,
        kind: .runStarted,
        payloadJSON: String(data: try encoder.encode(AgentRunStartedEvent(run: run)), encoding: .utf8)!,
        sequence: 0
    )

    let replayed = try AgentEventReplayer().replay(event)

    #expect(replayed.kind == .runStarted)
    #expect(replayed.runID == "run-replay")
    #expect(replayed.sessionID == "session-replay")
}

@Test func artifactManagerWritesSessionArtifactAndReturnsTimelineEvent() throws {
    let root = phaseATemporaryRoot()
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    let manager = AppSessionArtifactManager(storagePaths: paths)

    let result = try manager.writeTextArtifact(
        sessionID: "session-artifact",
        kind: "plan",
        filename: "phase-a.md",
        contents: "# Phase A\nRuntime foundation hardening."
    )

    #expect(FileManager.default.fileExists(atPath: result.url.path))
    #expect(try String(contentsOf: result.url) == "# Phase A\nRuntime foundation hardening.")
    #expect(result.event.sessionID == "session-artifact")
    #expect(result.event.artifactKind == "plan")
    #expect(result.event.path == result.url.path)
}

@Test func runtimeSettingsRepositoryPersistsLoopAndBudgetDefaults() throws {
    let root = phaseATemporaryRoot()
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    let repository = AppRuntimeSettingsRepository(configDirectory: paths.configDirectory)

    var settings = AgentRuntimeSettings.default
    settings.loop.maxToolIterations = 12
    settings.loop.maxToolCallsPerIteration = 6
    settings.loop.budget.maxTotalTokens = 240_000
    settings.ui.textDeltaFlushCharacterThreshold = 120

    try repository.save(settings)
    let loaded = try repository.loadOrCreateDefault()

    #expect(loaded.loop.maxToolIterations == 12)
    #expect(loaded.loop.maxToolCallsPerIteration == 6)
    #expect(loaded.loop.budget.maxTotalTokens == 240_000)
    #expect(loaded.ui.textDeltaFlushCharacterThreshold == 120)
}

@Test func runtimeSettingsRepositoryPersistsWorkspaceDefaults() throws {
    let root = phaseATemporaryRoot()
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    let repository = AppRuntimeSettingsRepository(configDirectory: paths.configDirectory)

    var settings = AgentRuntimeSettings.default
    settings.workspace.defaultWorkingDirectoryPath = "/tmp/connor-project"
    settings.workspace.additionalAllowedDirectoryPaths = ["/tmp/shared-assets"]

    try repository.save(settings)
    let loaded = try repository.loadOrCreateDefault()

    #expect(loaded.workspace.defaultWorkingDirectoryPath == "/tmp/connor-project")
    #expect(loaded.workspace.additionalAllowedDirectoryPaths == ["/tmp/shared-assets"])
}
