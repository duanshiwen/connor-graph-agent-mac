import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private actor PhaseBRecordingSessionTransport: ClaudeSDKSidecarSessionTransport {
    private(set) var startRequests: [ClaudeSDKSidecarRequest] = []
    private(set) var commands: [ClaudeSDKSidecarCommand] = []
    var sdkSessionIDToEmit: String?
    var terminalEvent: ClaudeSDKSidecarEvent

    init(sdkSessionIDToEmit: String? = "sdk-session-phase-b", terminalEvent: ClaudeSDKSidecarEvent = .runCompleted(ClaudeSDKSidecarRunCompleted())) {
        self.sdkSessionIDToEmit = sdkSessionIDToEmit
        self.terminalEvent = terminalEvent
    }

    func start(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error> {
        startRequests.append(request)
        let sdkSessionID = sdkSessionIDToEmit
        let terminal = terminalEvent
        return AsyncThrowingStream { continuation in
            continuation.yield(.runStarted(ClaudeSDKSidecarRunStarted(sdkSessionID: sdkSessionID)))
            continuation.yield(.textComplete(ClaudeSDKSidecarTextComplete(text: "ok")))
            continuation.yield(terminal)
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

private func phaseBTemporaryDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorPhaseB-\(name)-", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func phaseBRepositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test func claudeSDKSidecarRuntimeStorePersistsSDKSessionIDForResume() throws {
    let directory = try phaseBTemporaryDirectory("RuntimeStore")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = AppClaudeSDKSidecarRuntimeStore(configDirectory: directory)
    var record = ClaudeSDKSidecarRuntimeRecord(connorSessionID: "connor-session", groupID: "default")
    record.sdkSessionID = "sdk-session-1"
    record.lastRunID = "run-1"
    record.status = .ready
    try store.save(record)

    let loaded = try store.load(connorSessionID: "connor-session")
    #expect(loaded?.sdkSessionID == "sdk-session-1")
    #expect(loaded?.lastRunID == "run-1")
    #expect(loaded?.status == .ready)
}

@Test func governedClaudeSidecarRuntimeResumesWithPersistedSDKSessionIDAndUpdatesRecord() async throws {
    let directory = try phaseBTemporaryDirectory("GovernedRuntimeResume")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = AppClaudeSDKSidecarRuntimeStore(configDirectory: directory)
    try store.save(ClaudeSDKSidecarRuntimeRecord(
        connorSessionID: "connor-session-resume",
        groupID: "default",
        sdkSessionID: "sdk-session-existing",
        lastRunID: "previous-run",
        status: .ready
    ))

    let transport = PhaseBRecordingSessionTransport(sdkSessionIDToEmit: "sdk-session-updated")
    let runtime = try GovernedClaudeSDKSidecarRuntime(
        transport: transport,
        workingDirectory: URL(fileURLWithPath: "/tmp/project"),
        permissionMode: .askToWrite,
        runtimeStore: store
    )
    let request = AgentChatRequest(
        runID: "run-resume",
        sessionID: "connor-session-resume",
        groupID: "default",
        userMessage: "continue",
        permissionMode: .readOnly
    )

    var events: [AgentEvent] = []
    for try await event in runtime.chat(request) { events.append(event) }

    let starts = await transport.recordedStartRequests()
    #expect(starts.first?.sdkSessionID == "sdk-session-existing")
    #expect(events.map(\.kind) == [.runStarted, .textComplete, .runCompleted])

    let updated = try store.load(connorSessionID: "connor-session-resume")
    #expect(updated?.sdkSessionID == "sdk-session-updated")
    #expect(updated?.lastRunID == "run-resume")
    #expect(updated?.status == .ready)
}

@Test func governedClaudeSidecarRuntimeMarksRecordFailedWhenSidecarRunFails() async throws {
    let directory = try phaseBTemporaryDirectory("GovernedRuntimeFailure")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = AppClaudeSDKSidecarRuntimeStore(configDirectory: directory)
    let transport = PhaseBRecordingSessionTransport(
        sdkSessionIDToEmit: "sdk-session-failed",
        terminalEvent: .runFailed(ClaudeSDKSidecarRunFailed(message: "boom"))
    )
    let runtime = try GovernedClaudeSDKSidecarRuntime(
        transport: transport,
        workingDirectory: URL(fileURLWithPath: "/tmp/project"),
        permissionMode: .askToWrite,
        runtimeStore: store
    )

    let request = AgentChatRequest(runID: "run-fail", sessionID: "connor-session-fail", groupID: "default", userMessage: "fail", permissionMode: .readOnly)
    for try await _ in runtime.chat(request) {}

    let record = try store.load(connorSessionID: "connor-session-fail")
    #expect(record?.sdkSessionID == "sdk-session-failed")
    #expect(record?.lastRunID == "run-fail")
    #expect(record?.status == .failed)
    #expect(record?.lastError == "boom")
}

@Test func claudeSDKSidecarCommandEncodesCancelEnvelope() throws {
    let command = ClaudeSDKSidecarCommand.cancel(ClaudeSDKSidecarCancelCommand(
        connorRunID: "run-cancel",
        connorSessionID: "session-cancel",
        reason: "user cancelled"
    ))

    let data = try JSONEncoder().encode(command)
    let decoded = try JSONDecoder().decode(ClaudeSDKSidecarCommand.self, from: data)

    #expect(decoded == command)
    let json = String(data: data, encoding: .utf8) ?? ""
    #expect(json.contains("cancel"))
    #expect(json.contains("run-cancel"))
}

@Test func sidecarRuntimeDiagnosticsClassifiesHealthFromRecord() throws {
    let ready = ClaudeSDKSidecarRuntimeRecord(connorSessionID: "s1", groupID: "default", sdkSessionID: "sdk-1", status: .ready)
    let failed = ClaudeSDKSidecarRuntimeRecord(connorSessionID: "s2", groupID: "default", status: .failed, lastError: "boom")
    let pending = ClaudeSDKSidecarRuntimeRecord(connorSessionID: "s3", groupID: "default", status: .permissionPending, pendingApprovalRequestID: "permission-1")

    #expect(ClaudeSDKSidecarRuntimeDiagnostics(record: ready).health == .healthy)
    #expect(ClaudeSDKSidecarRuntimeDiagnostics(record: failed).health == .failed)
    #expect(ClaudeSDKSidecarRuntimeDiagnostics(record: pending).health == .waitingForApproval)
}

@Test func persistentProcessTransportWritesCancelCommandBeforeTerminating() async throws {
    let temporaryDirectory = try phaseBTemporaryDirectory("PersistentCancel")
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let capturedCommandsURL = temporaryDirectory.appendingPathComponent("commands.jsonl")
    let scriptURL = temporaryDirectory.appendingPathComponent("mock-cancel-sidecar.sh")
    try """
    #!/bin/sh
    while IFS= read -r command; do
      printf '%s\n' "$command" >> "$CONNOR_CAPTURED_COMMANDS"
      case "$command" in
        *'"start"'*)
          printf '%s\n' '{"runStarted":{"sdkSessionID":"sdk-cancel-session"}}'
          ;;
        *'"cancel"'*)
          printf '%s\n' '{"runFailed":{"message":"cancelled by test"}}'
          exit 0
          ;;
      esac
    done
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let transport = ClaudeSDKSidecarPersistentProcessTransport(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: [scriptURL.path],
        environment: ["CONNOR_CAPTURED_COMMANDS": capturedCommandsURL.path],
        currentDirectoryURL: temporaryDirectory
    )
    let request = ClaudeSDKSidecarRequest(
        connorRunID: "run-cancel-persistent",
        connorSessionID: "session-cancel-persistent",
        groupID: "default",
        prompt: "start then cancel",
        cwd: temporaryDirectory.path,
        permissionMode: .askToWrite
    )

    var iterator = await transport.start(request).makeAsyncIterator()
    _ = try await iterator.next()
    try await transport.send(.cancel(ClaudeSDKSidecarCancelCommand(
        connorRunID: "run-cancel-persistent",
        connorSessionID: "session-cancel-persistent",
        reason: "user cancelled"
    )))
    _ = try await iterator.next()
    await transport.cancel()

    let capturedLines = try String(contentsOf: capturedCommandsURL, encoding: .utf8)
        .split(separator: "\n")
        .map(String.init)
    let commands = try capturedLines.map { try JSONDecoder().decode(ClaudeSDKSidecarCommand.self, from: Data($0.utf8)) }
    #expect(commands.map(\.commandName) == ["start", "cancel"])
}

@Test func claudeSDKSidecarEngineDeclaresHealthCommand() throws {
    let root = phaseBRepositoryRootURL()
    let sidecarSource = try String(
        contentsOf: root.appendingPathComponent("sidecars/claude-agent-engine/claude-sidecar.mjs"),
        encoding: .utf8
    )

    #expect(sidecarSource.contains("case 'health'"))
    #expect(sidecarSource.contains("sidecarHealth"))
    #expect(sidecarSource.contains("pendingDeferredToolUses.size"))
}

@Test func claudeSDKSidecarJSONLProtocolDecodesHealthEvent() throws {
    let line = "{\"sidecarHealth\":{\"status\":\"ok\",\"pendingDeferredToolUseCount\":2,\"timestamp\":\"2026-06-11T11:57:00.000Z\",\"ownsProductState\":false}}"
    let decoded = try JSONDecoder().decode(ClaudeSDKSidecarEvent.self, from: Data(line.utf8))

    #expect(decoded == .sidecarHealth(ClaudeSDKSidecarHealth(status: "ok", pendingDeferredToolUseCount: 2, timestamp: "2026-06-11T11:57:00.000Z", ownsProductState: false)))
}
