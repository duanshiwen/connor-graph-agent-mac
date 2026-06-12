import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private actor Train2RecordingSessionTransport: ClaudeSDKSidecarSessionTransport {
    private(set) var startRequests: [ClaudeSDKSidecarRequest] = []
    private(set) var commands: [ClaudeSDKSidecarCommand] = []
    var events: [ClaudeSDKSidecarEvent]

    init(events: [ClaudeSDKSidecarEvent]) {
        self.events = events
    }

    func start(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error> {
        startRequests.append(request)
        let events = events
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func send(_ command: ClaudeSDKSidecarCommand) async throws {
        commands.append(command)
    }

    func cancel() async {}

    func recordedStartRequests() -> [ClaudeSDKSidecarRequest] { startRequests }
    func recordedCommands() -> [ClaudeSDKSidecarCommand] { commands }
}

private func train2TemporaryDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorTrain2-\(name)-", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func train2RepositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test func commercialTrain2SidecarRequestCarriesProtocolV2OptionsAndSovereignty() throws {
    let request = ClaudeSDKSidecarRequest(
        requestKind: .fork,
        connorRunID: "run-train2",
        connorSessionID: "connor-session-train2",
        groupID: "default",
        prompt: "Continue through a governed sidecar",
        cwd: "/tmp/project",
        permissionMode: .askToWrite,
        sdkSessionID: nil,
        forkFromSDKSessionID: "sdk-parent-session",
        options: ClaudeSDKSidecarRequestOptions(
            maxTurns: 12,
            model: "claude-sonnet-4-5",
            effort: "high",
            sdkSessionStoreHint: "~/.claude/projects/project"
        )
    )

    let data = try JSONEncoder().encode(ClaudeSDKSidecarCommand.start(request))
    let decoded = try JSONDecoder().decode(ClaudeSDKSidecarCommand.self, from: data)

    guard case .start(let payload) = decoded else {
        Issue.record("Expected start command")
        return
    }
    #expect(payload.protocolVersion == 2)
    #expect(payload.requestKind == .fork)
    #expect(payload.effectiveRequestKind == .fork)
    #expect(payload.forkFromSDKSessionID == "sdk-parent-session")
    #expect(payload.sdkPermissionMode == "bypassPermissions")
    #expect(payload.ownsProductState == false)
    #expect(payload.options.maxTurns == 12)
    #expect(payload.options.model == "claude-sonnet-4-5")
    #expect(payload.options.effort == "high")
    #expect(payload.options.persistSession == true)
}

@Test func commercialTrain2RuntimePersistsHeartbeatDiagnosticAndStructuredFailure() async throws {
    let directory = try train2TemporaryDirectory("RuntimeDiagnostics")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = AppClaudeSDKSidecarRuntimeStore(configDirectory: directory)
    let transport = Train2RecordingSessionTransport(events: [
        .runStarted(ClaudeSDKSidecarRunStarted(sdkSessionID: "sdk-train2")),
        .heartbeat(ClaudeSDKSidecarHeartbeat(sdkSessionID: "sdk-train2", sdkCWD: "/tmp/project", timestamp: "2026-06-12T12:09:00.000Z")),
        .runtimeDiagnostic(ClaudeSDKSidecarRuntimeDiagnostic(status: "running", message: "sidecar healthy", sdkSessionID: "sdk-train2", sdkCWD: "/tmp/project")),
        .runFailed(ClaudeSDKSidecarRunFailed(message: "tool approval required", code: .permissionDeferred, recoverability: .requiresUserAction))
    ])
    let runtime = try GovernedClaudeSDKSidecarRuntime(
        transport: transport,
        workingDirectory: URL(fileURLWithPath: "/tmp/project"),
        permissionMode: .askToWrite,
        runtimeStore: store
    )
    let request = AgentChatRequest(runID: "run-train2-runtime", sessionID: "session-train2-runtime", groupID: "default", userMessage: "Use sidecar", permissionMode: .readOnly)

    var events: [AgentEvent] = []
    for try await event in runtime.chat(request) { events.append(event) }

    #expect(events.map(\.kind) == [.runStarted, .runFailed])
    let record = try #require(try store.load(connorSessionID: "session-train2-runtime"))
    #expect(record.protocolVersion == 2)
    #expect(record.sdkSessionID == "sdk-train2")
    #expect(record.sdkCWD == "/tmp/project")
    #expect(record.lastHeartbeatAt != nil)
    #expect(record.lastDiagnosticMessage == "sidecar healthy")
    #expect(record.failureCode == .permissionDeferred)
    #expect(record.recoverability == .requiresUserAction)
}

@Test func commercialTrain2RuntimeStorePreservesSessionAnchorMetadata() throws {
    let directory = try train2TemporaryDirectory("RuntimeStoreMetadata")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = AppClaudeSDKSidecarRuntimeStore(configDirectory: directory)
    var record = ClaudeSDKSidecarRuntimeRecord(
        connorSessionID: "session-anchor",
        groupID: "default",
        sdkSessionID: "sdk-anchor",
        status: .ready,
        protocolVersion: 2,
        sdkCWD: "/tmp/project",
        sdkSessionStoreHint: "~/.claude/projects/project",
        forkedFromSDKSessionID: "sdk-parent",
        lastDiagnosticMessage: "ready for resume",
        recoverability: .resumable
    )
    record.lastHeartbeatAt = Date()
    try store.save(record)

    let loaded = try #require(try store.load(connorSessionID: "session-anchor"))
    #expect(loaded.sdkSessionID == "sdk-anchor")
    #expect(loaded.sdkCWD == "/tmp/project")
    #expect(loaded.sdkSessionStoreHint == "~/.claude/projects/project")
    #expect(loaded.forkedFromSDKSessionID == "sdk-parent")
    #expect(loaded.lastHeartbeatAt != nil)
    #expect(loaded.lastDiagnosticMessage == "ready for resume")
    #expect(loaded.recoverability == .resumable)
}

@Test func commercialTrain2JSONLProtocolDecodesHealthHeartbeatDiagnosticAndStructuredFailure() throws {
    let lines = [
        "{\"sidecarHealth\":{\"status\":\"ok\",\"pendingDeferredToolUseCount\":1,\"timestamp\":\"2026-06-12T12:09:00.000Z\",\"ownsProductState\":false,\"protocolVersion\":2,\"capabilities\":[\"resume\",\"fork\"]}}",
        "{\"heartbeat\":{\"protocolVersion\":2,\"sdkSessionID\":\"sdk-1\",\"sdkCWD\":\"/tmp/project\",\"timestamp\":\"2026-06-12T12:09:01.000Z\",\"pendingDeferredToolUseCount\":0,\"ownsProductState\":false}}",
        "{\"runtimeDiagnostic\":{\"protocolVersion\":2,\"status\":\"failed\",\"message\":\"bad request\",\"sdkSessionID\":\"sdk-1\",\"sdkCWD\":\"/tmp/project\",\"failureCode\":\"invalid_request\",\"recoverability\":\"requires_user_action\",\"ownsProductState\":false}}",
        "{\"runFailed\":{\"message\":\"cancelled\",\"code\":\"cancelled\",\"recoverability\":\"terminal\"}}"
    ]
    let decoded = try lines.map { try JSONDecoder().decode(ClaudeSDKSidecarEvent.self, from: Data($0.utf8)) }

    #expect(decoded.count == 4)
    if case .sidecarHealth(let health) = decoded[0] {
        #expect(health.protocolVersion == 2)
        #expect(health.capabilities.contains("fork"))
        #expect(health.ownsProductState == false)
    } else { Issue.record("Expected sidecarHealth") }
    if case .heartbeat(let heartbeat) = decoded[1] {
        #expect(heartbeat.sdkSessionID == "sdk-1")
        #expect(heartbeat.sdkCWD == "/tmp/project")
    } else { Issue.record("Expected heartbeat") }
    if case .runtimeDiagnostic(let diagnostic) = decoded[2] {
        #expect(diagnostic.failureCode == .invalidRequest)
        #expect(diagnostic.recoverability == .requiresUserAction)
    } else { Issue.record("Expected runtimeDiagnostic") }
    if case .runFailed(let failure) = decoded[3] {
        #expect(failure.code == .cancelled)
        #expect(failure.recoverability == .terminal)
    } else { Issue.record("Expected runFailed") }
}

@Test func commercialTrain2SidecarScriptDeclaresProtocolV2Capabilities() throws {
    let root = train2RepositoryRootURL()
    let source = try String(contentsOf: root.appendingPathComponent("sidecars/claude-agent-engine/claude-sidecar.mjs"), encoding: .utf8)

    #expect(source.contains("SIDECAR_PROTOCOL_VERSION = 2"))
    #expect(source.contains("forkSession"))
    #expect(source.contains("heartbeat"))
    #expect(source.contains("runtimeDiagnostic"))
    #expect(source.contains("structured-failure"))
    #expect(source.contains("bypassPermissions"))
}
