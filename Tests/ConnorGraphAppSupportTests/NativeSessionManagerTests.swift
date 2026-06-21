import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphSearch
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

private actor NativeSessionRecordingLLMProvider: LLMProvider {
    private var promptCount = 0

    func complete(prompt: String, context: AgentContext) async throws -> LLMResponse {
        promptCount += 1
        return LLMResponse(text: """
        INTENT: Preserve prior session context.
        DECISIONS: NONE
        CHANGES: NONE
        PENDING: NONE
        DETAILS: compressed
        """, citations: [])
    }

    func count() -> Int { promptCount }
}

private func temporaryNativeSessionManagerDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private func makeNativeSessionStore() throws -> SQLiteGraphKernelStore {
    let store = try SQLiteGraphKernelStore(path: temporaryNativeSessionManagerDatabaseURL().path)
    try store.migrate()
    return store
}

@Test func nativeSessionManagerRunsMainAgentPromptAssemblyBeforeMaintenanceCompression() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let longMessage = String(repeating: "historical context requiring compression ", count: 120)
    let historicalMessages = (0..<10).map { index in
        AgentMessage(
            id: "history-\(index)",
            role: index.isMultiple(of: 2) ? .user : .assistant,
            content: "\(index): \(longMessage)",
            createdAt: Date(timeIntervalSince1970: Double(index))
        )
    }
    let session = AgentSession(
        id: "native-session-compression-order",
        title: "Compression Order",
        messages: historicalMessages,
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    try repository.saveSession(session)
    let compressionProvider = NativeSessionRecordingLLMProvider()
    let loop = AgentLoopController(modelProvider: NativeSessionFinalAnswerProvider(), toolRegistry: AgentToolRegistry())
    var manager = NativeSessionManager(
        backend: AgentLoopBackend(loopController: loop),
        sessionRepository: repository,
        session: session,
        compressionProvider: AnyLLMProvider(compressionProvider),
        contextWindowSize: 100
    )

    let response = try await manager.submit("Handle the current request")
    let eventKinds: [AgentEventKind] = response.events.map(\.kind)
    let promptAssembledIndex = try #require(eventKinds.firstIndex(of: AgentEventKind.promptAssembled))
    let textCompleteIndex = try #require(eventKinds.firstIndex(of: AgentEventKind.textComplete))

    #expect(promptAssembledIndex < textCompleteIndex)
    #expect(response.assistantMessage?.content == "Connor-owned assistant response")
    #expect(await compressionProvider.count() == 1)
    #expect(manager.session.messages.last?.role == .assistant)
    #expect(manager.session.messages.last?.content == "Connor-owned assistant response")
}

@Test func nativeSessionManagerPreservesSessionStatusChangedByAgentTool() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "native-session-status-tool", title: "Status Tool", createdAt: Date(timeIntervalSince1970: 1_000))
    try repository.saveSession(session)
    var registry = AgentToolRegistry()
    registry.registerSessionStatusTools(repository: repository)
    let loop = AgentLoopController(
        modelProvider: NativeSessionScriptedProvider(responses: [
            AgentModelResponse(
                text: nil,
                toolCalls: [AgentToolCall(id: "set-status-call", name: "session_set_status", argumentsJSON: #"{"status":"done","reason":"The user asked to mark this session done."}"#)],
                usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
                finishReason: .toolCalls
            ),
            AgentModelResponse(
                text: "已将当前会话标记为已完成。",
                toolCalls: [],
                usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
                finishReason: .stop
            )
        ]),
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(permissionMode: .allowAll)
    )
    var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

    let response = try await manager.submit("把当前会话标记为完成")
    let loaded = try #require(try repository.loadSession(id: session.id))

    #expect(response.session.governance.status == .done)
    #expect(manager.session.governance.status == .done)
    #expect(loaded.governance.status == .done)
    #expect(loaded.messages.last?.role == .assistant)
    #expect(loaded.messages.last?.content == "已将当前会话标记为已完成。")
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
