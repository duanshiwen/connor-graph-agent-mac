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

private actor FakeClaudeSDKSidecarSessionTransport: ClaudeSDKSidecarSessionTransport {
    private var continuation: AsyncThrowingStream<ClaudeSDKSidecarEvent, Error>.Continuation?
    private(set) var startRequests: [ClaudeSDKSidecarRequest] = []
    private(set) var commands: [ClaudeSDKSidecarCommand] = []

    func start(_ request: ClaudeSDKSidecarRequest) async -> AsyncThrowingStream<ClaudeSDKSidecarEvent, Error> {
        startRequests.append(request)
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ClaudeSDKSidecarEvent.self, throwing: Error.self)
        self.continuation = continuation
        continuation.yield(.runStarted(ClaudeSDKSidecarRunStarted(sdkSessionID: "fake-session")))
        continuation.yield(.permissionRequested(ClaudeSDKSidecarPermissionRequested(
            requestID: "permission-tool-1",
            capability: .commitGraphWrite,
            toolName: "Write",
            payloadJSON: "{}"
        )))
        return stream
    }

    func send(_ command: ClaudeSDKSidecarCommand) async throws {
        commands.append(command)
        guard case .approvalResolved(let resolution) = command else { return }
        if resolution.outcome == .approved {
            continuation?.yield(.resumeAccepted(ClaudeSDKSidecarResumeAccepted(
                requestID: resolution.requestID,
                toolName: resolution.toolName,
                message: "Resume accepted by fake sidecar"
            )))
        } else {
            continuation?.yield(.resumeRejected(ClaudeSDKSidecarResumeRejected(
                requestID: resolution.requestID,
                toolName: resolution.toolName,
                reason: resolution.reason
            )))
        }
    }

    func cancel() async {
        continuation?.finish()
    }

    func recordedStartRequests() -> [ClaudeSDKSidecarRequest] { startRequests }
    func recordedCommands() -> [ClaudeSDKSidecarCommand] { commands }
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

@Test func claudeSDKSidecarBackendNormalizesToolAndPermissionEvents() async throws {
    let transport = FakeClaudeSDKSidecarTransport(scriptedEvents: [
        .runStarted(ClaudeSDKSidecarRunStarted(sdkSessionID: "claude-sdk-session")),
        .toolUseRequested(ClaudeSDKSidecarToolUseRequested(toolCallID: "tool-1", name: "Read", inputJSON: "{\"file_path\":\"README.md\"}")),
        .permissionRequested(ClaudeSDKSidecarPermissionRequested(requestID: "permission-1", capability: .readSession, toolName: "Read", payloadJSON: "{\"file_path\":\"README.md\"}")),
        .toolUseStarted(ClaudeSDKSidecarToolUseStarted(toolCallID: "tool-1", name: "Read")),
        .toolUseCompleted(ClaudeSDKSidecarToolUseCompleted(toolCallID: "tool-1", name: "Read", contentText: "README contents", contentJSON: nil, isError: false)),
        .runCompleted(ClaudeSDKSidecarRunCompleted())
    ])
    let backend = ClaudeSDKSidecarBackend(
        transport: transport,
        workingDirectory: URL(fileURLWithPath: "/tmp/project")
    )
    let request = AgentChatRequest(
        runID: "run-sidecar-tools",
        sessionID: "connor-session-sidecar-tools",
        groupID: "default",
        userMessage: "Read README",
        permissionMode: .readOnly
    )

    var events: [AgentEvent] = []
    for try await event in backend.chat(request) {
        events.append(event)
    }

    #expect(events.map(\.kind) == [.runStarted, .toolRequested, .permissionRequested, .toolStarted, .toolFinished, .runCompleted])
    if case .toolRequested(let call)? = events.first(where: { $0.kind == .toolRequested }) {
        #expect(call.id == "tool-1")
        #expect(call.runID == "run-sidecar-tools")
        #expect(call.sessionID == "connor-session-sidecar-tools")
        #expect(call.name == "Read")
        #expect(call.argumentsJSON == "{\"file_path\":\"README.md\"}")
    } else {
        Issue.record("Expected normalized toolRequested event")
    }
    if case .permissionRequested(let permission)? = events.first(where: { $0.kind == .permissionRequested }) {
        #expect(permission.id == "permission-1")
        #expect(permission.runID == "run-sidecar-tools")
        #expect(permission.sessionID == "connor-session-sidecar-tools")
        #expect(permission.capability == .readSession)
        #expect(permission.toolName == "Read")
    } else {
        Issue.record("Expected normalized permissionRequested event")
    }
    if case .toolFinished(let result)? = events.first(where: { $0.kind == .toolFinished }) {
        #expect(result.toolCallID == "tool-1")
        #expect(result.toolName == "Read")
        #expect(result.contentText == "README contents")
        #expect(result.error == nil)
    } else {
        Issue.record("Expected normalized toolFinished event")
    }
}

@Test func claudeSDKSidecarApprovalResolutionCommandKeepsConnorStateOwnership() throws {
    let approval = AgentPendingApproval(
        requestID: "permission-tool-1",
        runID: "run-sidecar-tools",
        sessionID: "connor-session-sidecar-tools",
        capability: .commitGraphWrite,
        toolName: "Write",
        payloadJSON: "{\"file_path\":\"README.md\"}",
        status: .approved
    )
    let resolution = ClaudeSDKSidecarApprovalResolution(
        approval: approval,
        status: .approved,
        reason: "Human reviewer approved the write",
        actor: "human-reviewer"
    )
    let command = ClaudeSDKSidecarCommand.approvalResolved(resolution)

    let data = try JSONEncoder().encode(command)
    let decoded = try JSONDecoder().decode(ClaudeSDKSidecarCommand.self, from: data)

    #expect(decoded == command)
    if case .approvalResolved(let payload) = decoded {
        #expect(payload.connorRunID == "run-sidecar-tools")
        #expect(payload.connorSessionID == "connor-session-sidecar-tools")
        #expect(payload.requestID == "permission-tool-1")
        #expect(payload.status == .approved)
        #expect(payload.outcome == .approved)
        #expect(payload.capability == .commitGraphWrite)
        #expect(payload.toolName == "Write")
        #expect(payload.payloadJSON == "{\"file_path\":\"README.md\"}")
        #expect(payload.reason == "Human reviewer approved the write")
        #expect(payload.actor == "human-reviewer")
        #expect(payload.ownsProductState == false)
    } else {
        Issue.record("Expected approvalResolved sidecar command")
    }
}

@Test func claudeSDKSidecarApprovalResolutionCommandMapsCancelledToDeniedOutcome() throws {
    let approval = AgentPendingApproval(
        requestID: "permission-tool-2",
        runID: "run-sidecar-tools",
        sessionID: "connor-session-sidecar-tools",
        capability: .externalNetwork,
        toolName: "WebFetch",
        status: .cancelled
    )
    let resolution = ClaudeSDKSidecarApprovalResolution(
        approval: approval,
        status: .cancelled,
        reason: "Run was cancelled",
        actor: "system"
    )

    #expect(resolution.status == .cancelled)
    #expect(resolution.outcome == .denied)
    #expect(resolution.ownsProductState == false)
}

@Test func claudeSDKSidecarJSONLProtocolDecodesToolAndPermissionEvents() throws {
    let lines = [
        "{\"toolUseRequested\":{\"toolCallID\":\"tool-1\",\"name\":\"Read\",\"inputJSON\":\"{}\"}}",
        "{\"permissionRequested\":{\"requestID\":\"permission-1\",\"capability\":\"readSession\",\"toolName\":\"Read\",\"payloadJSON\":\"{}\"}}",
        "{\"toolUseStarted\":{\"toolCallID\":\"tool-1\",\"name\":\"Read\"}}",
        "{\"toolUseCompleted\":{\"toolCallID\":\"tool-1\",\"name\":\"Read\",\"contentText\":\"ok\",\"contentJSON\":null,\"isError\":false}}"
    ]
    let decoder = JSONDecoder()
    let decoded = try lines.map { line in
        try decoder.decode(ClaudeSDKSidecarEvent.self, from: Data(line.utf8))
    }

    #expect(decoded == [
        .toolUseRequested(ClaudeSDKSidecarToolUseRequested(toolCallID: "tool-1", name: "Read", inputJSON: "{}")),
        .permissionRequested(ClaudeSDKSidecarPermissionRequested(requestID: "permission-1", capability: .readSession, toolName: "Read", payloadJSON: "{}")),
        .toolUseStarted(ClaudeSDKSidecarToolUseStarted(toolCallID: "tool-1", name: "Read")),
        .toolUseCompleted(ClaudeSDKSidecarToolUseCompleted(toolCallID: "tool-1", name: "Read", contentText: "ok", contentJSON: nil, isError: false))
    ])
}

@Test func claudeSDKSidecarJSONLProtocolDecodesResumeEvents() throws {
    let lines = [
        "{\"resumeAccepted\":{\"requestID\":\"permission-tool-1\",\"toolName\":\"Write\",\"message\":\"accepted\"}}",
        "{\"resumeRejected\":{\"requestID\":\"permission-tool-2\",\"toolName\":\"Bash\",\"reason\":\"denied\"}}"
    ]
    let decoder = JSONDecoder()
    let decoded = try lines.map { line in
        try decoder.decode(ClaudeSDKSidecarEvent.self, from: Data(line.utf8))
    }

    #expect(decoded == [
        .resumeAccepted(ClaudeSDKSidecarResumeAccepted(requestID: "permission-tool-1", toolName: "Write", message: "accepted")),
        .resumeRejected(ClaudeSDKSidecarResumeRejected(requestID: "permission-tool-2", toolName: "Bash", reason: "denied"))
    ])
}

@Test func claudeSDKSidecarSessionTransportAcceptsApprovalResolutionCommands() async throws {
    let transport = FakeClaudeSDKSidecarSessionTransport()
    let request = ClaudeSDKSidecarRequest(
        connorRunID: "run-session-transport",
        connorSessionID: "connor-session-transport",
        groupID: "default",
        prompt: "Use a persistent sidecar session transport",
        cwd: "/tmp/project",
        permissionMode: .askToWrite
    )

    var iterator = await transport.start(request).makeAsyncIterator()
    let started = try await iterator.next()
    let permission = try await iterator.next()

    #expect(started == .runStarted(ClaudeSDKSidecarRunStarted(sdkSessionID: "fake-session")))
    #expect(permission == .permissionRequested(ClaudeSDKSidecarPermissionRequested(
        requestID: "permission-tool-1",
        capability: .commitGraphWrite,
        toolName: "Write",
        payloadJSON: "{}"
    )))

    let approval = AgentPendingApproval(
        requestID: "permission-tool-1",
        runID: "run-session-transport",
        sessionID: "connor-session-transport",
        capability: .commitGraphWrite,
        toolName: "Write",
        payloadJSON: "{}",
        status: .approved
    )
    let resolution = ClaudeSDKSidecarApprovalResolution(
        approval: approval,
        status: .approved,
        reason: "Human reviewer approved the write"
    )

    try await transport.send(.approvalResolved(resolution))
    let resumeEvent = try await iterator.next()

    #expect(resumeEvent == .resumeAccepted(ClaudeSDKSidecarResumeAccepted(
        requestID: "permission-tool-1",
        toolName: "Write",
        message: "Resume accepted by fake sidecar"
    )))
    #expect(await transport.recordedStartRequests() == [request])
    #expect(await transport.recordedCommands() == [.approvalResolved(resolution)])

    await transport.cancel()
}

@Test func claudeSDKSidecarPersistentProcessTransportStreamsEventsAndSendsCommands() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorPersistentSidecarTransportTests-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let capturedCommandsURL = temporaryDirectory.appendingPathComponent("commands.jsonl")
    let scriptURL = temporaryDirectory.appendingPathComponent("mock-persistent-sidecar.sh")
    try """
    #!/bin/sh
    while IFS= read -r command; do
      printf '%s\n' "$command" >> "$CONNOR_CAPTURED_COMMANDS"
      case "$command" in
        *'"start"'*)
          printf '%s\n' '{"runStarted":{"sdkSessionID":"sdk-persistent-session"}}'
          printf '%s\n' '{"permissionRequested":{"requestID":"permission-tool-1","capability":"commitGraphWrite","toolName":"Write","payloadJSON":"{}"}}'
          ;;
        *'"approvalResolved"'*)
          printf '%s\n' '{"resumeAccepted":{"requestID":"permission-tool-1","toolName":"Write","message":"persistent resume accepted"}}'
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
        connorRunID: "run-persistent",
        connorSessionID: "session-persistent",
        groupID: "default",
        prompt: "Use persistent process transport",
        cwd: temporaryDirectory.path,
        permissionMode: .askToWrite
    )

    var iterator = await transport.start(request).makeAsyncIterator()
    let started = try await iterator.next()
    let permission = try await iterator.next()

    #expect(started == .runStarted(ClaudeSDKSidecarRunStarted(sdkSessionID: "sdk-persistent-session")))
    #expect(permission == .permissionRequested(ClaudeSDKSidecarPermissionRequested(
        requestID: "permission-tool-1",
        capability: .commitGraphWrite,
        toolName: "Write",
        payloadJSON: "{}"
    )))

    let approval = AgentPendingApproval(
        requestID: "permission-tool-1",
        runID: "run-persistent",
        sessionID: "session-persistent",
        capability: .commitGraphWrite,
        toolName: "Write",
        payloadJSON: "{}",
        status: .approved
    )
    let resolution = ClaudeSDKSidecarApprovalResolution(
        approval: approval,
        status: .approved,
        reason: "Approved by reviewer"
    )

    try await transport.send(.approvalResolved(resolution))
    let resume = try await iterator.next()
    #expect(resume == .resumeAccepted(ClaudeSDKSidecarResumeAccepted(
        requestID: "permission-tool-1",
        toolName: "Write",
        message: "persistent resume accepted"
    )))

    await transport.cancel()

    let capturedLines = try String(contentsOf: capturedCommandsURL, encoding: .utf8)
        .split(separator: "\n")
        .map(String.init)
    let decoder = JSONDecoder()
    let commands = try capturedLines.map { try decoder.decode(ClaudeSDKSidecarCommand.self, from: Data($0.utf8)) }
    #expect(commands == [.start(request), .approvalResolved(resolution)])
}

@Test func claudeSDKSidecarProcessTransportSupportsStartCommandBoundaryWithoutChangingLegacyRequestShape() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorSidecarCommandTransportTests-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let capturedRequestURL = temporaryDirectory.appendingPathComponent("request.jsonl")
    let scriptURL = temporaryDirectory.appendingPathComponent("mock-sidecar.sh")
    try """
    #!/bin/sh
    IFS= read -r request
    printf '%s\n' "$request" > "$CONNOR_CAPTURED_REQUEST"
    printf '%s\n' '{"runStarted":{"sdkSessionID":"sdk-command-session"}}'
    printf '%s\n' '{"runCompleted":{}}'
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let transport = ClaudeSDKSidecarProcessTransport(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: [scriptURL.path],
        environment: ["CONNOR_CAPTURED_REQUEST": capturedRequestURL.path]
    )
    let request = ClaudeSDKSidecarRequest(
        connorRunID: "run-command-start",
        connorSessionID: "session-command-start",
        groupID: "default",
        prompt: "Use the command transport start boundary",
        cwd: temporaryDirectory.path,
        permissionMode: .askToWrite
    )

    var events: [ClaudeSDKSidecarEvent] = []
    for try await event in await transport.stream(.start(request)) {
        events.append(event)
    }

    let capturedData = try Data(contentsOf: capturedRequestURL)
    let captured = try JSONDecoder().decode(ClaudeSDKSidecarRequest.self, from: capturedData)
    #expect(captured.connorRunID == "run-command-start")
    #expect(captured.connorSessionID == "session-command-start")
    #expect(captured.ownsProductState == false)
    #expect(events == [
        .runStarted(ClaudeSDKSidecarRunStarted(sdkSessionID: "sdk-command-session")),
        .runCompleted(ClaudeSDKSidecarRunCompleted())
    ])
}

@Test func claudeSDKSidecarProcessTransportRejectsApprovalResolutionCommandUntilStreamingSessionExists() async throws {
    let transport = ClaudeSDKSidecarProcessTransport(executableURL: URL(fileURLWithPath: "/bin/sh"))
    let approval = AgentPendingApproval(
        requestID: "permission-tool-1",
        runID: "run-sidecar-tools",
        sessionID: "connor-session-sidecar-tools",
        capability: .commitGraphWrite,
        toolName: "Write",
        status: .approved
    )
    let resolution = ClaudeSDKSidecarApprovalResolution(
        approval: approval,
        status: .approved,
        reason: "Approved by reviewer"
    )

    do {
        for try await _ in await transport.stream(.approvalResolved(resolution)) {}
        Issue.record("Expected approvalResolved command to be rejected by one-shot process transport")
    } catch let error as ClaudeSDKSidecarProcessTransportError {
        #expect(error == .unsupportedCommand("approvalResolved"))
    } catch {
        Issue.record("Expected ClaudeSDKSidecarProcessTransportError.unsupportedCommand, got \(error)")
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
    #expect(sidecarSource.contains("toolUseRequested"))
    #expect(sidecarSource.contains("permissionRequested"))
    #expect(sidecarSource.contains("toolUseCompleted"))
}

@Test func claudeSDKSidecarEngineDeclaresPersistentCommandLoopSkeleton() throws {
    let root = repositoryRootURL()
    let sidecarSource = try String(
        contentsOf: root.appendingPathComponent("sidecars/claude-agent-engine/claude-sidecar.mjs"),
        encoding: .utf8
    )

    #expect(sidecarSource.contains("parseCommand"))
    #expect(sidecarSource.contains("runCommandLoop"))
    #expect(sidecarSource.contains("handleApprovalResolved"))
    #expect(sidecarSource.contains("resumeAccepted"))
    #expect(sidecarSource.contains("resumeRejected"))
    #expect(sidecarSource.contains("case 'start'"))
    #expect(sidecarSource.contains("case 'approvalResolved'"))
    #expect(sidecarSource.contains("case 'cancel'"))
    #expect(sidecarSource.contains("resuming deferred Claude SDK tool use under Connor governance"))
}

@Test func claudeSDKSidecarEngineDeclaresDeferredToolResumeAdapterSeam() throws {
    let root = repositoryRootURL()
    let sidecarSource = try String(
        contentsOf: root.appendingPathComponent("sidecars/claude-agent-engine/claude-sidecar.mjs"),
        encoding: .utf8
    )

    #expect(sidecarSource.contains("pendingDeferredToolUses"))
    #expect(sidecarSource.contains("buildConnorDeferHooks"))
    #expect(sidecarSource.contains("permissionDecision: 'defer'"))
    #expect(sidecarSource.contains("terminalReason === 'tool_deferred'"))
    #expect(sidecarSource.contains("deferred_tool_use"))
    #expect(sidecarSource.contains("runDeferredResume"))
    #expect(sidecarSource.contains("buildDeferredResumeHooks"))
    #expect(sidecarSource.contains("permissionDecision: 'allow'"))
    #expect(sidecarSource.contains("updatedInput"))
    #expect(sidecarSource.contains("resume: deferred.sdkSessionID"))
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

@Test func governedClaudeSidecarRuntimeSendsConnorOwnedApprovalResolution() async throws {
    let transport = FakeClaudeSDKSidecarSessionTransport()
    let runtime = try GovernedClaudeSDKSidecarRuntime(
        transport: transport,
        workingDirectory: URL(fileURLWithPath: "/tmp/project"),
        permissionMode: .askToWrite
    )
    let approval = AgentPendingApproval(
        requestID: "permission-tool-1",
        runID: "run-sidecar-tools",
        sessionID: "connor-session-sidecar-tools",
        capability: .commitGraphWrite,
        toolName: "Write",
        payloadJSON: "{}",
        status: .approved
    )

    try await runtime.resolveApproval(approval, status: .approved, reason: "Approved in Connor", actor: "human-reviewer")

    let commands = await transport.recordedCommands()
    #expect(commands.count == 1)
    if case .approvalResolved(let resolution)? = commands.first {
        #expect(resolution.connorRunID == "run-sidecar-tools")
        #expect(resolution.connorSessionID == "connor-session-sidecar-tools")
        #expect(resolution.requestID == "permission-tool-1")
        #expect(resolution.status == .approved)
        #expect(resolution.outcome == .approved)
        #expect(resolution.ownsProductState == false)
    } else {
        Issue.record("Expected approvalResolved command")
    }
}

@Test func governedClaudeSidecarRuntimeRejectsAllowAll() throws {
    #expect(throws: GovernedClaudeSDKSidecarRuntimeError.self) {
        _ = try GovernedClaudeSDKSidecarRuntime(
            transport: FakeClaudeSDKSidecarSessionTransport(),
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            permissionMode: .allowAll
        )
    }
}

@Test func governedClaudeSidecarRuntimeSendsNormalizedPromptWithSessionContext() async throws {
    let transport = FakeClaudeSDKSidecarSessionTransport()
    let runtime = try GovernedClaudeSDKSidecarRuntime(
        transport: transport,
        workingDirectory: URL(fileURLWithPath: "/tmp/project"),
        permissionMode: .askToWrite
    )
    let summary = AgentSessionSummary(
        sessionID: "connor-session-normalized",
        content: "We were migrating all calls to NativeSessionManager.",
        sourceMessageCount: 2
    )
    let request = AgentChatRequest(
        runID: "run-normalized",
        sessionID: "connor-session-normalized",
        groupID: "default",
        userMessage: "继续",
        sessionSummary: summary,
        recentMessages: [
            AgentMessage(role: .user, content: "先定位为什么继续失效"),
            AgentMessage(role: .assistant, content: "主路径没有显式传同 session 上下文。")
        ],
        permissionMode: .readOnly
    )

    var iterator = runtime.chat(request).makeAsyncIterator()
    _ = try await iterator.next()
    await runtime.cancel()

    let recorded = await transport.recordedStartRequests()
    let prompt = try #require(recorded.first?.prompt)
    #expect(prompt.contains("Previous session summary:"))
    #expect(prompt.contains("We were migrating all calls to NativeSessionManager."))
    #expect(prompt.contains("Recent conversation:"))
    #expect(prompt.contains("User: 先定位为什么继续失效"))
    #expect(prompt.contains("Assistant: 主路径没有显式传同 session 上下文。"))
    #expect(prompt.contains("Current user request:\n继续"))
    #expect(recorded.first?.permissionMode == .askToWrite)
}
