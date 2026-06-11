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
