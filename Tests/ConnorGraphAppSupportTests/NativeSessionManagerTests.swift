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

private actor NativeSessionPromptRecordingProvider: AgentModelProvider {
    let modelID = "native-session-prompt-recording"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: true,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false
    )
    private var requests: [AgentModelRequest] = []

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        requests.append(request)
        return AgentModelResponse(
            text: "Recorded response",
            usage: AgentModelUsage(promptTokens: 8, completionTokens: 4)
        )
    }

    func lastRequest() -> AgentModelRequest? { requests.last }
}

private actor NativeSessionTwoTurnToolProvider: AgentModelProvider {
    let modelID = "native-session-two-turn-tool"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: true,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false
    )
    private var requests: [AgentModelRequest] = []

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        requests.append(request)
        let content = request.messages.map(\.content).joined(separator: "\n")
        if content.contains("SECOND_USER_TURN") {
            return AgentModelResponse(text: "SECOND_ASSISTANT_FINAL")
        }
        if request.messages.contains(where: { $0.role == .tool }) {
            return AgentModelResponse(text: "FIRST_ASSISTANT_FINAL")
        }
        return AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "first-turn-tool-call", name: "continuity_probe", argumentsJSON: #"{}"#)],
            finishReason: .toolCalls
        )
    }

    func recordedRequests() -> [AgentModelRequest] { requests }
}

private struct NativeSessionContinuityProbeTool: AgentTool {
    let name = "continuity_probe"
    let description = "Return a marker that must remain scoped to the current run"
    let permission = AgentPermissionCapability.readSession
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "FIRST_TURN_TOOL_RESULT_MUST_NOT_CROSS_ROUNDS"
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
        return LLMResponse(text: #"{"currentGoal":"Handle the current request","userConstraints":[],"decisions":[],"completedWork":[],"importantFacts":[],"filesAndArtifacts":[],"pendingWork":[],"attachments":[]}"#, citations: [])
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

@Test func nativeSessionManagerCompactsAtMostOncePerSubmission() async throws {
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
        contextWindowSize: 100,
        rollingSummaryProvider: AnyLLMProvider(compressionProvider),
        rollingSummaryModelID: "summary-test-model"
    )

    let response = try await manager.submit("Handle the current request")
    let eventKinds: [AgentEventKind] = response.events.map(\.kind)
    let promptAssembledIndex = try #require(eventKinds.firstIndex(of: AgentEventKind.promptAssembled))
    let textCompleteIndex = try #require(eventKinds.firstIndex(of: AgentEventKind.textComplete))

    #expect(promptAssembledIndex < textCompleteIndex)
    #expect(response.assistantMessage?.content == "Connor-owned assistant response")
    #expect(await compressionProvider.count() == 1)
    let loadedSummaryState = try repository.loadConversationSummaryState(sessionID: session.id)
    let summaryState = try #require(loadedSummaryState)
    #expect(summaryState.compressionGeneration == 1)
    #expect(summaryState.payload.currentGoal == "Handle the current request")
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

@Test func nativeSessionManagerPersistsAndPromptsStructuredPersonReferences() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "native-session-person-ref", title: "Person Ref", createdAt: Date(timeIntervalSince1970: 1_000))
    try repository.saveSession(session)
    let provider = NativeSessionPromptRecordingProvider()
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: AgentToolRegistry())
    var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)
    let reference = PersonReference(
        personID: ContactID(rawValue: "person-duan-leiqiang"),
        displayName: "段磊强",
        mentionText: "@段磊强",
        status: .active,
        memoryEntityID: "memory-person-duan"
    )

    let response = try await manager.submit(
        "请整理和 @段磊强 相关的事项",
        sessionSummary: nil,
        displayPrompt: "请整理和 @段磊强 相关的事项",
        personReferences: [reference]
    )
    let loaded = try #require(try repository.loadSession(id: session.id))
    let request = try #require(await provider.lastRequest())
    let renderedMessages = request.messages.map(\.content).joined(separator: "\n\n")

    #expect(response.session.messages.first?.personReferences == [reference])
    #expect(loaded.messages.first?.personReferences == [reference])
    #expect(renderedMessages.contains("Referenced People in Current User Request"))
    #expect(renderedMessages.contains("personID: person-duan-leiqiang"))
    #expect(renderedMessages.contains("memoryEntityID: memory-person-duan"))
}

@Test func nativeSessionManagerPromptsWithCompletePersistedConversationWithoutHistoricalSystemMessages() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let persistedMessages = [
        AgentMessage(id: "history-user-1", role: .user, content: "EARLIEST_USER_HISTORY"),
        AgentMessage(id: "history-assistant-1", role: .assistant, content: "EARLIEST_ASSISTANT_HISTORY"),
        AgentMessage(id: "history-system", role: .system, content: "LEGACY_SYSTEM_MARKER"),
        AgentMessage(id: "history-user-2", role: .user, content: "LATEST_USER_HISTORY"),
        AgentMessage(id: "history-assistant-2", role: .assistant, content: "LATEST_ASSISTANT_HISTORY")
    ]
    let persistedSession = AgentSession(
        id: "native-session-complete-history",
        title: "Complete History",
        messages: persistedMessages
    )
    try repository.saveSession(persistedSession)

    var partiallyLoadedSession = persistedSession
    partiallyLoadedSession.messages = Array(persistedMessages.suffix(2))
    let provider = NativeSessionPromptRecordingProvider()
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: AgentToolRegistry())
    var manager = NativeSessionManager(
        loopController: loop,
        sessionRepository: repository,
        session: partiallyLoadedSession
    )

    _ = try await manager.submit("CURRENT_USER_REQUEST")
    let request = try #require(await provider.lastRequest())
    let renderedMessages = request.messages.map(\.content).joined(separator: "\n\n")

    #expect(renderedMessages.contains("EARLIEST_USER_HISTORY"))
    #expect(renderedMessages.contains("EARLIEST_ASSISTANT_HISTORY"))
    #expect(renderedMessages.contains("LATEST_USER_HISTORY"))
    #expect(renderedMessages.contains("LATEST_ASSISTANT_HISTORY"))
    #expect(renderedMessages.contains("CURRENT_USER_REQUEST"))
    #expect(!renderedMessages.contains("LEGACY_SYSTEM_MARKER"))
}

@Test func nativeSessionManagerCarriesOnlyUserAndFinalAssistantMessagesAcrossRealTurns() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(
        id: "native-session-real-two-turn-continuity",
        title: "Real Two Turn Continuity",
        messages: [AgentMessage(id: "legacy-system", role: .system, content: "LEGACY_SYSTEM_MUST_NOT_CROSS_ROUNDS")]
    )
    try repository.saveSession(session)
    let provider = NativeSessionTwoTurnToolProvider()
    var registry = AgentToolRegistry()
    registry.register(NativeSessionContinuityProbeTool())
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(permissionMode: .allowAll)
    )
    var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

    let first = try await manager.submit("FIRST_USER_TURN")
    let second = try await manager.submit("SECOND_USER_TURN")

    #expect(first.assistantMessage?.content == "FIRST_ASSISTANT_FINAL")
    #expect(second.assistantMessage?.content == "SECOND_ASSISTANT_FINAL")
    let requests = await provider.recordedRequests()
    #expect(requests.count == 3)
    let secondTurnRequest = try #require(requests.last)
    let secondTurnContent = secondTurnRequest.messages.map(\.content).joined(separator: "\n")
    #expect(secondTurnContent.contains("FIRST_USER_TURN"))
    #expect(secondTurnContent.contains("FIRST_ASSISTANT_FINAL"))
    #expect(secondTurnContent.contains("SECOND_USER_TURN"))
    #expect(secondTurnRequest.messages.first?.content.contains("## Cross-Run Continuity") == true)
    #expect(secondTurnRequest.messages.first?.content.contains("final response as the durable handoff record") == true)
    #expect(!secondTurnContent.contains("FIRST_TURN_TOOL_RESULT_MUST_NOT_CROSS_ROUNDS"))
    #expect(!secondTurnContent.contains("first-turn-tool-call"))
    #expect(!secondTurnContent.contains("LEGACY_SYSTEM_MUST_NOT_CROSS_ROUNDS"))
    #expect(!secondTurnRequest.messages.contains { $0.role == .tool })
    #expect(!secondTurnRequest.messages.contains { !($0.toolCalls ?? []).isEmpty })

    let persisted = try #require(try repository.loadSession(id: session.id))
    #expect(persisted.messages.filter { $0.role == .user }.map(\.content) == ["FIRST_USER_TURN", "SECOND_USER_TURN"])
    #expect(persisted.messages.filter { $0.role == .assistant }.map(\.content) == ["FIRST_ASSISTANT_FINAL", "SECOND_ASSISTANT_FINAL"])
    #expect(try repository.loadConversationSummaryState(sessionID: session.id) == nil)
}

@Test func nativeSessionManagerCanAppendRevisionReplyWithoutAppendingAnotherUserMessage() async throws {
    let store = try makeNativeSessionStore()
    let repository = AppChatSessionRepository(store: store)
    var governance = AgentSessionGovernanceMetadata.default
    governance.kind = .note
    let body = AgentMessage(id: "note-body", role: .user, content: "updated note")
    let previousReply = AgentMessage(id: "previous-reply", role: .assistant, content: "previous analysis")
    let session = AgentSession(
        id: "note-revision-session",
        title: "Revision",
        messages: [body, previousReply],
        governance: governance
    )
    try repository.saveSession(session)
    let provider = NativeSessionPromptRecordingProvider()
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: AgentToolRegistry())
    var manager = NativeSessionManager(loopController: loop, sessionRepository: repository, session: session)

    let response = try await manager.submit(
        "note_phase: revision_review",
        sessionSummary: nil,
        existingUserMessageID: body.id
    )

    #expect(response.session.messages.map(\.role) == [.user, .assistant, .assistant])
    #expect(response.session.messages.first == body)
    #expect(response.session.messages.last?.content == "Recorded response")
    let loaded = try #require(try repository.loadSession(id: session.id))
    #expect(loaded.messages.map(\.id).filter { $0 == body.id }.count == 1)
    #expect(loaded.messages.filter { $0.role == .user }.count == 1)
    let run = try #require(try repository.loadRuns(sessionID: session.id).first)
    #expect(run.metadata["input_mode"] == "existing_user_message")
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
                toolCalls: [AgentToolCall(id: "native-write-call", name: "Write", argumentsJSON: #"{"filePath":"approved.txt","content":"ok"}"#)],
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
    #expect(loaded.messages.last?.content.contains("已完成边界：本轮用户消息已保存") == true)
    #expect(loaded.messages.last?.content.contains("继续前请重新检查相关持久状态") == true)
    #expect(manager.session.messages.map(\.id) == loaded.messages.map(\.id))
    #expect(manager.session.messages.map(\.role) == loaded.messages.map(\.role))
    #expect(manager.session.messages.map(\.content) == loaded.messages.map(\.content))

    let recoveryProvider = NativeSessionPromptRecordingProvider()
    let recoveryLoop = AgentLoopController(modelProvider: recoveryProvider, toolRegistry: AgentToolRegistry())
    var recoveryManager = NativeSessionManager(
        loopController: recoveryLoop,
        sessionRepository: repository,
        session: loaded
    )
    _ = try await recoveryManager.submit("Continue from the saved boundary")
    let recoveryRequest = try #require(await recoveryProvider.lastRequest())
    let recoveryContent = recoveryRequest.messages.map(\.content).joined(separator: "\n")

    #expect(recoveryContent.contains("This must be durable even if the backend fails"))
    #expect(recoveryContent.contains("已完成边界：本轮用户消息已保存"))
    #expect(recoveryContent.contains("Continue from the saved boundary"))
    #expect(!recoveryRequest.messages.contains { $0.role == .tool })
    #expect(!recoveryRequest.messages.contains { !(($0.toolCalls ?? []).isEmpty) })
}
