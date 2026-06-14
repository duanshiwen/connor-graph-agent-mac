import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private actor NativeSessionFinalAnswerProvider: AgentModelProvider {
    let modelID = "native-session-final-answer"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: true,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false
    )

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        AgentModelResponse(
            text: "Connor-owned assistant response",
            usage: AgentModelUsage(promptTokens: 8, completionTokens: 4)
        )
    }
}

private enum NativeSessionFailingProviderError: Error, Sendable, Equatable {
    case backendUnavailable
}

private actor NativeSessionFailingProvider: AgentModelProvider {
    let modelID = "native-session-failing-provider"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: false,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false
    )

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        throw NativeSessionFailingProviderError.backendUnavailable
    }
}

private actor NativeSessionScriptedProvider: AgentModelProvider {
    let modelID = "native-session-scripted"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: true,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false
    )
    private var responses: [AgentModelResponse]

    init(responses: [AgentModelResponse]) {
        self.responses = responses
    }

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        responses.removeFirst()
    }
}

private func temporaryNativeSessionManagerDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private func makeNativeSessionStore() throws -> SQLiteGraphKernelStore {
    let store = try SQLiteGraphKernelStore(path: temporaryNativeSessionManagerDatabaseURL().path)
    try store.migrate()
    return store
}

@Test func nativeSessionManagerPersistsUserMessageBeforeBackendCompletes() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "native-session-1", title: "New Chat", createdAt: Date(timeIntervalSince1970: 1_000))
    try repository.saveSession(session)
    let loop = AgentLoopController(modelProvider: NativeSessionFinalAnswerProvider(), toolRegistry: AgentToolRegistry())
    var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

    let response = try await manager.submit("Build a native SessionManager")
    let loaded = try #require(try repository.loadSession(id: "native-session-1"))

    #expect(response.session.messages.map(\.role) == [.user, .assistant])
    #expect(loaded.messages.map(\.role) == [.user, .assistant])
    #expect(loaded.messages.first?.content == "Build a native SessionManager")
    #expect(loaded.messages.last?.content == "Connor-owned assistant response")
    #expect(manager.session.messages.map(\.id) == loaded.messages.map(\.id))
    #expect(manager.session.messages.map(\.role) == loaded.messages.map(\.role))
    #expect(manager.session.messages.map(\.content) == loaded.messages.map(\.content))
}

@Test func nativeSessionManagerPersistsAskToWritePendingApprovalAndContinuesAfterApproval() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "native-session-approval", title: "Approval Chat", createdAt: Date(timeIntervalSince1970: 1_000))
    try repository.saveSession(session)
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorNativeSessionApproval-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }
    var registry = AgentToolRegistry()
    registry.register(LocalWriteFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace)))
    let loop = AgentLoopController(
        modelProvider: NativeSessionScriptedProvider(responses: [
            AgentModelResponse(
                text: nil,
                toolCalls: [AgentToolCall(id: "native-write-call", name: "Write", argumentsJSON: #"{"file_path":"approved.txt","content":"ok"}"#)],
                usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
                finishReason: .toolCalls
            ),
            AgentModelResponse(
                text: "Approved write completed.",
                toolCalls: [],
                usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
                finishReason: .stop
            )
        ]),
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(permissionMode: .askToWrite)
    )
    var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

    let approvalTask = Task {
        var approval: AgentPendingApproval?
        for _ in 0..<100 {
            if let pending = try store.pendingApprovals(status: .pending, limit: 10).first {
                approval = pending
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let pending = try #require(approval)
        #expect(pending.capability == .writeWorkspaceFile)
        #expect(pending.toolName == "Write")
        await loop.resolveApproval(pending, status: .approved)
    }

    let response = try await manager.submit("Write with approval")
    try await approvalTask.value
    let approvals = try store.pendingApprovals(runID: try #require(response.events.first?.runID))

    #expect(response.events.map(\.kind).contains(.permissionRequested))
    #expect(response.events.map(\.kind).contains(.permissionResolved))
    #expect(response.assistantMessage?.content == "Approved write completed.")
    #expect(approvals.count == 1)
    #expect(approvals.first?.status == .pending)
    #expect(try String(contentsOf: workspace.appendingPathComponent("approved.txt"), encoding: .utf8) == "ok")
}

@Test func nativeSessionManagerPreservesUserMessageWhenBackendFails() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "native-session-failure", title: "New Chat", createdAt: Date(timeIntervalSince1970: 1_000))
    try repository.saveSession(session)
    let loop = AgentLoopController(modelProvider: NativeSessionFailingProvider(), toolRegistry: AgentToolRegistry())
    var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

    do {
        _ = try await manager.submit("This must be durable even if the backend fails")
        Issue.record("Expected backend failure")
    } catch NativeSessionFailingProviderError.backendUnavailable {
        // expected
    }

    let loaded = try #require(try repository.loadSession(id: "native-session-failure"))
    #expect(loaded.messages.count == 2)
    #expect(loaded.messages.first?.role == .user)
    #expect(loaded.messages.first?.content == "This must be durable even if the backend fails")
    #expect(loaded.messages.last?.role == .assistant)
    #expect(loaded.messages.last?.content.contains("操作已终止：") == true)
    #expect(loaded.messages.last?.content.contains("backendUnavailable") == true)
    #expect(manager.session.messages.map(\.id) == loaded.messages.map(\.id))
    #expect(manager.session.messages.map(\.role) == loaded.messages.map(\.role))
    #expect(manager.session.messages.map(\.content) == loaded.messages.map(\.content))
}
