import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private actor FakeClaudeSDKSidecarTransport: ClaudeSDKSidecarTransport {
    private(set) var requests: [ClaudeSDKSidecarRequest] = []
    var scriptedEvents: [ClaudeSDKSidecarEvent]

    init(scriptedEvents: [ClaudeSDKSidecarEvent]) {
        self.scriptedEvents = scriptedEvents
    }

    func stream(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error> {
        requests.append(request)
        let events = scriptedEvents
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func recordedRequests() -> [ClaudeSDKSidecarRequest] { requests }
}

@Test func claudeSDKSidecarRequestMapsConnorPolicyWithoutGrantingSDKStateOwnership() throws {
    let request = AgentChatRequest(
        runID: "run-1",
        sessionID: "connor-session-1",
        groupID: "default",
        userMessage: "Build the backend abstraction",
        permissionMode: .askToWrite
    )
    let sidecarRequest = ClaudeSDKSidecarRequest(request: request, workingDirectory: URL(fileURLWithPath: "/tmp/project"))

    #expect(sidecarRequest.connorRunID == "run-1")
    #expect(sidecarRequest.connorSessionID == "connor-session-1")
    #expect(sidecarRequest.prompt == "Build the backend abstraction")
    #expect(sidecarRequest.cwd == "/tmp/project")
    #expect(sidecarRequest.permissionMode == .askToWrite)
    #expect(sidecarRequest.sdkSessionID == nil)
    #expect(sidecarRequest.sdkPermissionMode == "bypassPermissions")
    #expect(sidecarRequest.ownsProductState == false)
}

@Test func claudeSDKSidecarBackendConvertsSidecarEventsToConnorAgentEvents() async throws {
    let transport = FakeClaudeSDKSidecarTransport(scriptedEvents: [
        .runStarted(ClaudeSDKSidecarRunStarted(sdkSessionID: "claude-sdk-session")),
        .textDelta(ClaudeSDKSidecarTextDelta(text: "Hello")),
        .textComplete(ClaudeSDKSidecarTextComplete(text: "Hello from Claude sidecar", citations: ["sdk:context"])),
        .runCompleted(ClaudeSDKSidecarRunCompleted())
    ])
    let backend = ClaudeSDKSidecarBackend(
        transport: transport,
        workingDirectory: URL(fileURLWithPath: "/tmp/project")
    )
    let request = AgentChatRequest(
        runID: "run-sidecar",
        sessionID: "connor-session-sidecar",
        groupID: "default",
        userMessage: "Use Claude SDK as sidecar",
        permissionMode: .readOnly
    )

    var events: [AgentEvent] = []
    for try await event in backend.chat(request) {
        events.append(event)
    }

    let recorded = await transport.recordedRequests()
    #expect(recorded.first?.connorSessionID == "connor-session-sidecar")
    #expect(recorded.first?.sdkPermissionMode == "bypassPermissions")
    #expect(events.map(\.kind) == [.runStarted, .textDelta, .textComplete, .runCompleted])
    #expect(events.compactMap(\.sessionID).allSatisfy { $0 == "connor-session-sidecar" })
    if case .runStarted(let started)? = events.first {
        #expect(started.run.metadata["runtime"] == "claude-sdk-sidecar")
        #expect(started.run.metadata["sdk_session_id"] == "claude-sdk-session")
    } else {
        Issue.record("Expected runStarted event")
    }
}

@Test func claudeSDKSidecarProcessTransportWritesRequestAndReadsJSONLEvents() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorSidecarTransportTests-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let capturedRequestURL = temporaryDirectory.appendingPathComponent("request.jsonl")
    let scriptURL = temporaryDirectory.appendingPathComponent("mock-sidecar.sh")
    try """
    #!/bin/sh
    IFS= read -r request
    printf '%s\n' "$request" > "$CONNOR_CAPTURED_REQUEST"
    printf '%s\n' '{"runStarted":{"sdkSessionID":"sdk-process-session"}}'
    printf '%s\n' '{"textDelta":{"text":"Hello"}}'
    printf '%s\n' '{"textComplete":{"text":"Hello from process","citations":["process"],"contextSnapshot":null}}'
    printf '%s\n' '{"runCompleted":{}}'
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let transport = ClaudeSDKSidecarProcessTransport(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: [scriptURL.path],
        environment: ["CONNOR_CAPTURED_REQUEST": capturedRequestURL.path]
    )
    let request = ClaudeSDKSidecarRequest(
        connorRunID: "run-process",
        connorSessionID: "session-process",
        groupID: "default",
        prompt: "Use the process transport",
        cwd: temporaryDirectory.path,
        permissionMode: .askToWrite
    )

    var events: [ClaudeSDKSidecarEvent] = []
    for try await event in await transport.stream(request) {
        events.append(event)
    }

    let capturedData = try Data(contentsOf: capturedRequestURL)
    let captured = try JSONDecoder().decode(ClaudeSDKSidecarRequest.self, from: capturedData)
    #expect(captured.connorRunID == "run-process")
    #expect(captured.connorSessionID == "session-process")
    #expect(captured.prompt == "Use the process transport")
    #expect(captured.sdkPermissionMode == "bypassPermissions")
    #expect(captured.ownsProductState == false)
    #expect(events == [
        .runStarted(ClaudeSDKSidecarRunStarted(sdkSessionID: "sdk-process-session")),
        .textDelta(ClaudeSDKSidecarTextDelta(text: "Hello")),
        .textComplete(ClaudeSDKSidecarTextComplete(text: "Hello from process", citations: ["process"])),
        .runCompleted(ClaudeSDKSidecarRunCompleted())
    ])
}

@Test func claudeSDKSidecarEnginePackageDeclaresRealSDKEntryPoint() throws {
    let root = repositoryRootURL()
    let sidecarDirectory = root.appendingPathComponent("sidecars/claude-agent-engine", isDirectory: true)
    let packageData = try Data(contentsOf: sidecarDirectory.appendingPathComponent("package.json"))
    let package = try JSONSerialization.jsonObject(with: packageData) as? [String: Any]
    let dependencies = package?["dependencies"] as? [String: String]
    let scripts = package?["scripts"] as? [String: String]
    let sidecarSource = try String(contentsOf: sidecarDirectory.appendingPathComponent("claude-sidecar.mjs"), encoding: .utf8)

    #expect(dependencies?["@anthropic-ai/claude-agent-sdk"] != nil)
    #expect(scripts?["start"] == "node claude-sidecar.mjs")
    #expect(sidecarSource.contains("@anthropic-ai/claude-agent-sdk"))
    #expect(sidecarSource.contains("query("))
    #expect(sidecarSource.contains("permissionMode: request.sdkPermissionMode"))
    #expect(sidecarSource.contains("ownsProductState"))
}

@Test func realClaudeSDKSidecarIntegrationSkipsUnlessExplicitlyEnabled() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["CONNOR_RUN_CLAUDE_SIDECAR_INTEGRATION"] == "1" else {
        return
    }
    guard let runtime = environment["CONNOR_CLAUDE_SIDECAR_RUNTIME"] else {
        Issue.record("Set CONNOR_CLAUDE_SIDECAR_RUNTIME to node or bun when enabling integration.")
        return
    }

    let root = repositoryRootURL()
    let sidecarDirectory = root.appendingPathComponent("sidecars/claude-agent-engine", isDirectory: true)
    let executableURL = URL(fileURLWithPath: runtime)
    let arguments = runtime.hasSuffix("bun")
        ? [sidecarDirectory.appendingPathComponent("claude-sidecar.mjs").path]
        : [sidecarDirectory.appendingPathComponent("claude-sidecar.mjs").path]
    let transport = ClaudeSDKSidecarProcessTransport(
        executableURL: executableURL,
        arguments: arguments,
        currentDirectoryURL: sidecarDirectory
    )
    let request = ClaudeSDKSidecarRequest(
        connorRunID: "integration-run",
        connorSessionID: "integration-session",
        groupID: "default",
        prompt: "Reply with exactly: Connor sidecar integration ok",
        cwd: root.path,
        permissionMode: .readOnly
    )

    var events: [ClaudeSDKSidecarEvent] = []
    for try await event in await transport.stream(request) {
        events.append(event)
    }

    #expect(events.contains { if case .runStarted = $0 { true } else { false } })
    #expect(events.contains { if case .textComplete = $0 { true } else { false } })
}

private func repositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
