import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch

private actor CapturingFinalAnswerProvider: AgentModelProvider {
    let modelID = "capturing-final"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)
    private(set) var lastRequest: AgentModelRequest?

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        lastRequest = request
        return AgentModelResponse(text: "Grounded final answer", usage: AgentModelUsage(promptTokens: 12, completionTokens: 4))
    }
}

private actor ScriptedModelProvider: AgentModelProvider {
    let modelID = "scripted"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)
    private var responses: [AgentModelResponse]
    private(set) var requests: [AgentModelRequest] = []

    init(responses: [AgentModelResponse]) {
        self.responses = responses
    }

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        requests.append(request)
        return responses.removeFirst()
    }
}

private actor SuspendingModelProvider: AgentModelProvider {
    let modelID = "suspending"
    let capabilities = AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)
    private(set) var wasCancelled = false
    private var hasEnteredRequest = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?

    func waitUntilRequestStarted() async {
        if hasEnteredRequest { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        hasEnteredRequest = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return AgentModelResponse(text: "should not complete")
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }
}

private struct StreamingFinalAnswerProvider: StreamingAgentModelProvider {
    let modelID = "streaming-final"
    let capabilities = AgentModelCapabilities(supportsStreaming: true, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false)

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        AgentModelResponse(text: "Fallback")
    }

    func streamComplete(_ request: AgentModelRequest) -> AsyncThrowingStream<AgentModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("Hel"))
            continuation.yield(.textDelta("lo"))
            continuation.yield(.completed(AgentModelResponse(text: "Hello", usage: AgentModelUsage(promptTokens: 2, completionTokens: 1))))
            continuation.finish()
        }
    }
}

@Test func agentLoopConfigurationDefaultsAllowDeeperSingleRunWork() {
    let configuration = AgentLoopConfiguration()

    #expect(configuration.maxToolIterations == 256)
    #expect(configuration.maxToolCallsPerIteration == 4)
    #expect(configuration.promptProjectionMode == .legacySingleUserMessage)
}

@Test func agentLoopConfigurationDecodesLegacyJSONWithPromptDefaults() throws {
    let data = Data(#"""
    {
      "maxToolIterations": 32,
      "maxToolCallsPerIteration": 2,
      "maxRunDurationSeconds": 90,
      "maxToolResultBytes": 4096,
      "allowParallelToolCalls": false,
      "permissionMode": "askToWrite",
      "budget": { "maxTotalTokens": 10000, "warningThresholdRatio": 0.8 }
    }
    """#.utf8)

    let configuration = try JSONDecoder().decode(AgentLoopConfiguration.self, from: data)

    #expect(configuration.maxToolIterations == 32)
    #expect(configuration.promptProjectionMode == .legacySingleUserMessage)
    #expect(configuration.promptMaxEstimatedTokens == 160_000)
    #expect(configuration.maxConsecutiveToolResultErrors == 0)
}

@Test func agentLoopEmitsTextDeltaForStreamingProvider() async throws {
    let provider = StreamingFinalAnswerProvider()
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        streamComplete: { provider, request in provider.streamComplete(request) }
    )

    var textDeltas: [String] = []
    var completeText: String?
    for try await event in loop.run(AgentChatRequest(runID: "run-streaming", sessionID: "session-streaming", userMessage: "Hello")) {
        switch event {
        case .textDelta(let payload): textDeltas.append(payload.text)
        case .textComplete(let payload): completeText = payload.text
        default: break
        }
    }

    #expect(textDeltas == ["Hel", "lo"])
    #expect(completeText == "Hello")
}

@Test func agentLoopEmitsPromptAssembledDiagnosticsBeforeModelCall() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(text: "Done", usage: AgentModelUsage(promptTokens: 12, completionTokens: 2))
    ])
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: AgentToolRegistry())

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(
        runID: "run-prompt-assembled",
        sessionID: "session-prompt-assembled",
        userMessage: "Summarize the prompt mechanism",
        recentMessages: [AgentMessage(id: "message-1", role: .assistant, content: "Earlier context")]
    )) {
        events.append(event)
    }

    let promptEvent = try #require(events.compactMap { event -> AgentPromptAssembledEvent? in
        if case .promptAssembled(let payload) = event { return payload }
        return nil
    }.first)
    #expect(promptEvent.projectionMode == AgentPromptProjectionMode.legacySingleUserMessage.rawValue)
    #expect(promptEvent.sections.map(\.id).contains("instruction"))
    #expect(promptEvent.sections.map(\.id).contains("current_request"))
    #expect(promptEvent.totalEstimatedTokenCount > 0)
    #expect(events.first?.kind == .runStarted)
    #expect(events.map(\.kind).firstIndex(of: .promptAssembled)! < events.map(\.kind).firstIndex(of: .turnStarted)!)
}

@Test func agentLoopAbortCancelsActiveModelRequest() async throws {
    let provider = SuspendingModelProvider()
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: AgentToolRegistry())
    let request = AgentChatRequest(runID: "run-cancel-loop", sessionID: "session-cancel-loop", userMessage: "wait")

    let task = Task { () -> [AgentEvent] in
        var events: [AgentEvent] = []
        do {
            for try await event in loop.run(request) { events.append(event) }
        } catch {
            // Expected cancellation path.
        }
        return events
    }

    await provider.waitUntilRequestStarted()
    loop.abort(runID: request.runID)
    let events = await task.value

    #expect(await provider.wasCancelled == true)
    #expect(events.map(\.kind).contains(.runStarted))
    #expect(events.map(\.kind).contains(.runFailed))
}

@Test func agentLoopRequestsApprovalForAskToWriteToolAndContinuesAfterApproval() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-write-approval", name: "Write", argumentsJSON: #"{"file_path":"note.txt","content":"approved"}"#)],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: "Write completed.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
            finishReason: .stop
        )
    ])
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorAgentLoopApproval-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }
    var registry = AgentToolRegistry()
    registry.register(LocalWriteFileTool(policy: LocalWorkspacePolicy(workingDirectory: workspace)))
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(permissionMode: .askToWrite)
    )
    let request = AgentChatRequest(runID: "run-write-approval", sessionID: "session-write-approval", userMessage: "Write note", permissionMode: .askToWrite)

    let task = Task { () throws -> [AgentEvent] in
        var events: [AgentEvent] = []
        for try await event in loop.run(request) {
            events.append(event)
            if case .permissionRequested(let approvalRequest) = event {
                Task {
                    await loop.resolveApproval(AgentPendingApproval(
                        requestID: approvalRequest.id,
                        runID: approvalRequest.runID,
                        sessionID: approvalRequest.sessionID,
                        capability: approvalRequest.capability,
                        toolName: approvalRequest.toolName,
                        payloadJSON: approvalRequest.payloadJSON
                    ), status: .approved)
                }
            }
        }
        return events
    }

    let events = try await task.value

    #expect(events.map(\.kind).contains(.permissionRequested))
    #expect(events.map(\.kind).contains(.permissionResolved))
    #expect(events.map(\.kind).contains(.toolFinished))
    #expect(events.map(\.kind).contains(.textComplete))
    #expect(events.last?.kind == .runCompleted)
    #expect(try String(contentsOf: workspace.appendingPathComponent("note.txt"), encoding: .utf8) == "approved")
}

@Test func agentLoopRequestsApprovalForWorkspaceShellCommand() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-bash-approval", name: "Bash", argumentsJSON: #"{"command":"touch shell-created.txt"}"#)],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: "Shell command completed.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
            finishReason: .stop
        )
    ])
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorAgentLoopShellApproval-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }
    var registry = AgentToolRegistry()
    registry.register(LocalBashTool(policy: LocalWorkspacePolicy(workingDirectory: workspace)))
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(permissionMode: .askToWrite)
    )
    let request = AgentChatRequest(runID: "run-bash-approval", sessionID: "session-bash-approval", userMessage: "Touch file", permissionMode: .askToWrite)

    let task = Task { () throws -> [AgentEvent] in
        var events: [AgentEvent] = []
        for try await event in loop.run(request) {
            events.append(event)
            if case .permissionRequested(let approvalRequest) = event {
                #expect(approvalRequest.capability == .runWorkspaceShellCommand)
                Task {
                    await loop.resolveApproval(AgentPendingApproval(
                        requestID: approvalRequest.id,
                        runID: approvalRequest.runID,
                        sessionID: approvalRequest.sessionID,
                        capability: approvalRequest.capability,
                        toolName: approvalRequest.toolName,
                        payloadJSON: approvalRequest.payloadJSON
                    ), status: .approved)
                }
            }
        }
        return events
    }

    let events = try await task.value

    #expect(events.map(\.kind).contains(.permissionRequested))
    #expect(events.map(\.kind).contains(.toolFinished))
    #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("shell-created.txt").path))
}

@Test func agentLoopContinuesAfterTokenBudgetExceeded() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: "Still completed after budget warning.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 200, completionTokens: 50),
            finishReason: .stop
        )
    ])
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        configuration: AgentLoopConfiguration(
            maxToolIterations: 1,
            permissionMode: .askToWrite,
            budget: AgentBudgetConfiguration(maxTotalTokens: 100, warningThresholdRatio: 0.8)
        )
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-budget-continue", userMessage: "Continue even if budget exceeds")) {
        events.append(event)
    }

    #expect(events.map(\.kind).contains(.budgetWarning))
    #expect(events.map(\.kind).contains(.textComplete))
    #expect(events.last?.kind == .runCompleted)
}

private struct EchoArgumentsTool: AgentTool {
    let name = "echo_args"
    let description = "Echo arguments"
    let permission = AgentPermissionCapability.readSession
    let inputSchema = AgentToolInputSchema.object(properties: ["value": .string(description: "Value")], required: ["value"])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let value = arguments.string("value") ?? ""
        return AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: value
        )
    }
}

private struct RetrievalEvidenceTool: AgentTool {
    let name: String
    let description = "Return deterministic retrieval evidence"
    let permission = AgentPermissionCapability.readSession
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "retrieved by \(name)",
            citations: name.hasPrefix("memory_os_") ? ["record:\(name)"] : []
        )
    }
}

private struct MemoryClaimEvidenceTool: AgentTool {
    let name: String
    let contentJSON: String
    let citations: [String]
    let description = "Return claim-validation memory evidence"
    let permission = AgentPermissionCapability.readSession
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: contentJSON, contentJSON: contentJSON, citations: citations)
    }
}

private struct NamedDelayTool: AgentTool {
    let name: String
    let delayNanoseconds: UInt64
    let description = "Delay and return tool name"
    let permission = AgentPermissionCapability.readSession
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: name
        )
    }
}

private struct LongResultTool: AgentTool {
    let name = "long_result"
    let description = "Return a long deterministic result"
    let permission = AgentPermissionCapability.readSession
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "abcdefghijklmnopqrstuvwxyz"
        )
    }
}

private struct BashLikeOutputTool: AgentTool {
    let name = "Bash"
    let description = "Return shell-like stdout plus JSON metadata"
    let permission = AgentPermissionCapability.readSession
    let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "exitCode: 0\nstdout:\nhello-from-stdout\n\nstderr:\n",
            contentJSON: "{\"exitCode\":0,\"truncated\":false}"
        )
    }
}

@Test func agentLoopDoesNotTreatSameToolWithDifferentArgumentsAsLoop() async throws {
    let toolResponses = (1...12).map { index in
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-echo-\(index)", name: "echo_args", argumentsJSON: #"{"value":"step-\#(index)"}"#)],
            usage: AgentModelUsage(promptTokens: 1, completionTokens: 1),
            finishReason: .toolCalls
        )
    }
    let provider = ScriptedModelProvider(responses: toolResponses + [
        AgentModelResponse(
            text: "Completed varied tool calls.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 1, completionTokens: 1),
            finishReason: .stop
        )
    ])
    var registry = AgentToolRegistry()
    registry.register(EchoArgumentsTool())
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(maxToolIterations: 16)
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-varied-tool-args", userMessage: "Run many varied steps")) {
        events.append(event)
    }

    #expect(events.map(\.kind).contains(.textComplete))
    #expect(events.last?.kind == .runCompleted)
}

@Test func agentLoopSendsToolTextOutputToFollowUpModelRequestWhenJSONMetadataExists() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-bash-output", name: "Bash", argumentsJSON: #"{}"#)],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: "Saw stdout.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
            finishReason: .stop
        )
    ])
    var registry = AgentToolRegistry()
    registry.register(BashLikeOutputTool())
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    for try await _ in loop.run(AgentChatRequest(sessionID: "session-bash-output", userMessage: "Run echo")) {}

    let followUpMessages = try #require(await provider.requests.last?.messages)
    let toolMessage = try #require(followUpMessages.first(where: { $0.role == .tool && $0.toolCallID == "call-bash-output" }))

    #expect(toolMessage.name == "Bash")
    #expect(toolMessage.content.contains("stdout:"))
    #expect(toolMessage.content.contains("hello-from-stdout"))
    #expect(toolMessage.content != "{\"exitCode\":0,\"truncated\":false}")
}

@Test func agentLoopPreservesProviderReasoningMetadataAcrossToolContinuation() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-reasoning", name: "echo_args", argumentsJSON: #"{"value":"step"}"#)],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls,
            providerMetadata: AgentModelProviderMetadata(
                providerID: "openai-compatible",
                reasoningContent: "I need the tool result to continue."
            )
        ),
        AgentModelResponse(
            text: "Done.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
            finishReason: .stop
        )
    ])
    var registry = AgentToolRegistry()
    registry.register(EchoArgumentsTool())
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    for try await _ in loop.run(AgentChatRequest(sessionID: "session-reasoning", userMessage: "Continue after the tool")) {}

    let followUpMessages = try #require(await provider.requests.last?.messages)
    let assistantMessage = try #require(followUpMessages.first { $0.role == .assistant })
    #expect(assistantMessage.providerMetadata?.reasoningContent == "I need the tool result to continue.")
}

@Test func agentLoopGatesLargeToolResultBeforeFollowUpModelRequest() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-long-result", name: "long_result", argumentsJSON: #"{}"#)],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: "Handled gated result.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
            finishReason: .stop
        )
    ])
    var registry = AgentToolRegistry()
    registry.register(LongResultTool())
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(maxToolResultBytes: 10)
    )

    for try await _ in loop.run(AgentChatRequest(sessionID: "session-gated-tool-result", userMessage: "Run long result")) {}

    let followUpMessages = try #require(await provider.requests.last?.messages)
    let toolMessage = try #require(followUpMessages.first(where: { $0.role == .tool && $0.toolCallID == "call-long-result" }))

    #expect(toolMessage.name == "long_result")
    #expect(toolMessage.content.hasPrefix("abcdefghij"))
    #expect(!toolMessage.content.contains("klmnopqrstuvwxyz"))
    #expect(toolMessage.content.contains("...[truncated tool result:"))
    #expect(toolMessage.content.contains("tool=long_result"))
    #expect(toolMessage.content.contains("kept=10 chars"))
    #expect(toolMessage.content.contains("original=26 chars"))
}

@Test func agentLoopPreservesAssistantToolCallsBeforeToolResult() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-science-transcript", name: "science_compute", argumentsJSON: #"{"operation":"add","inputs":{"values":[1,2]}}"#)],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: "1 + 2 = 3.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
            finishReason: .stop
        )
    ])
    var registry = AgentToolRegistry()
    registry.register(ScienceComputeTool(runtime: ScientificComputeRuntime(engines: [NativeSwiftScientificEngine()])))
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    for try await _ in loop.run(AgentChatRequest(sessionID: "session-tool-transcript", userMessage: "Calculate 1+2")) {}

    let requests = await provider.requests
    #expect(requests.count == 2)
    let followUpMessages = try #require(requests.last?.messages)
    let assistantToolMessage = try #require(followUpMessages.first(where: { $0.role == .assistant && $0.toolCalls?.isEmpty == false }))
    let assistantToolCallIDs = assistantToolMessage.toolCalls?.map(\.id)
    let assistantToolName = assistantToolMessage.toolCalls?.first?.name
    let containsMatchingToolResult = followUpMessages.contains { message in
        message.role == .tool &&
            message.toolCallID == "call-science-transcript" &&
            message.name == "science_compute"
    }
    #expect(assistantToolCallIDs == ["call-science-transcript"])
    #expect(assistantToolName == "science_compute")
    #expect(containsMatchingToolResult)
}

@Test func agentLoopRunsScientificToolThenFinalAnswer() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-science-1", name: "science_compute", argumentsJSON: #"{"operation":"add","inputs":{"values":[2,3,4]}}"#)],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: "2 + 3 + 4 = 9.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
            finishReason: .stop
        )
    ])
    var registry = AgentToolRegistry()
    registry.register(ScienceComputeTool(runtime: ScientificComputeRuntime(engines: [NativeSwiftScientificEngine()])))
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-science-loop", userMessage: "Calculate 2+3+4")) {
        events.append(event)
    }

    #expect(events.map(\.kind).contains(.toolStarted))
    #expect(events.map(\.kind).contains(.toolFinished))
    #expect(events.map(\.kind).contains(.textComplete))
    #expect(events.last?.kind == .runCompleted)
}

@Test func agentLoopRunsGraphToolThenFinalAnswer() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-1", name: "graph_search", argumentsJSON: #"{"query":"memory"}"#)],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: "Use graph memory.",
            toolCalls: [],
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 5),
            finishReason: .stop
        )
    ])
    var registry = AgentToolRegistry()
    registry.register(GraphSearchTool(searchService: TestHybridSearchService(hits: [
        GraphSearchHit(ownerType: .entity, ownerID: "node-memory", title: "Memory", text: "Graph memory", score: 1.0, retrievalMethod: "test")
    ])))
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-1", userMessage: "How should memory work?")) {
        events.append(event)
    }

    #expect(events.map(\.kind).contains(.toolStarted))
    #expect(events.map(\.kind).contains(.toolFinished))
    #expect(events.map(\.kind).contains(.textComplete))
    #expect(events.last?.kind == .runCompleted)
}

@Test func agentLoopUsesNormalizedPromptWithSessionContext() async throws {
    let provider = CapturingFinalAnswerProvider()
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry()
    )
    let summary = AgentSessionSummary(
        sessionID: "session-context",
        content: "We were designing reliable session context injection.",
        sourceMessageCount: 2
    )
    let recentMessages = [
        AgentMessage(role: .user, content: "先说明当前架构问题"),
        AgentMessage(role: .assistant, content: "主路径没有显式上传 recent messages。")
    ]
    let request = AgentChatRequest(
        sessionID: "session-context",
        userMessage: "继续",
        sessionSummary: summary,
        recentMessages: recentMessages
    )

    for try await _ in loop.run(request) {}

    let modelRequest = await provider.lastRequest
    let userContent = try #require(modelRequest?.messages.last(where: { $0.role == .user })?.content)
    #expect(userContent.contains("Previous session summary:"))
    #expect(userContent.contains("We were designing reliable session context injection."))
    #expect(userContent.contains("Recent conversation:"))
    #expect(userContent.contains("User: 先说明当前架构问题"))
    #expect(userContent.contains("Assistant: 主路径没有显式上传 recent messages。"))
    #expect(userContent.contains("Current user request:\n继续"))
}

@Test func agentLoopDoesNotInjectInitialGraphContextIntoModelRequest() async throws {
    let provider = CapturingFinalAnswerProvider()
    let contextBuilder = AgentContextBuilder(
        hybridSearchService: TestHybridSearchService(hits: [
            GraphSearchHit(
                ownerType: .episode,
                ownerID: "episode-1",
                title: "Preference memory",
                text: "诗闻喜欢结构化推进。",
                score: 1.0,
                retrievalMethod: "test",
                metadata: ["source_type": "chat"]
            )
        ]),
        groupID: "default",
        limit: 3
    )
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        contextBuilder: contextBuilder
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-context", userMessage: "我偏好什么方式推进？")) {
        events.append(event)
    }

    let request = await provider.lastRequest
    #expect(request?.messages.contains(where: { $0.role == .system && $0.content.contains("Relevant Memory OS Context") }) == false)
    #expect(request?.messages.contains(where: { $0.content.contains("诗闻喜欢结构化推进") }) == false)
    let textComplete = events.compactMap { event -> AgentTextCompleteEvent? in
        if case .textComplete(let payload) = event { return payload }
        return nil
    }.first
    #expect(textComplete?.citations == [])
    #expect(textComplete?.contextSnapshot == nil)
}

@Test func retrievalComplianceRequiresMemoryAndWebForNonMemoryTasks() async throws {
    let toolNames = AgentRetrievalCompliancePolicy.requiredMemoryTools + ["web_search"]
    let calls = toolNames.enumerated().map { index, name in
        AgentToolCall(id: "required-\(index)", name: name, argumentsJSON: "{}")
    }
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(text: "premature"),
        AgentModelResponse(text: nil, toolCalls: calls, finishReason: .toolCalls),
        AgentModelResponse(text: "grounded")
    ])
    var registry = AgentToolRegistry()
    for name in toolNames { registry.register(RetrievalEvidenceTool(name: name)) }
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    var completed: AgentTextCompleteEvent?
    for try await event in loop.run(AgentChatRequest(sessionID: "compliance-web", userMessage: "Explain Swift concurrency")) {
        if case .textComplete(let payload) = event { completed = payload }
    }

    let requests = await provider.requests
    #expect(requests.count == 3)
    #expect(requests[1].messages.last?.content.contains("blocked the first completion") == true)
    #expect(completed?.text == "grounded")
    #expect(completed?.citations.count == 3)
    #expect(completed?.citations.allSatisfy { $0.hasPrefix("record:memory_os_") } == true)
}

@Test func retrievalComplianceExemptsPureMemoryTasksFromWebSearch() async throws {
    let policy = AgentRetrievalCompliancePolicy()
    #expect(policy.isPureMemoryTask("请根据我的记忆总结我们之前的决定"))
    #expect(!policy.isPureMemoryTask("请搜索最新 Swift 版本"))
    #expect(policy.requiredTools(for: "回忆我的偏好") == AgentRetrievalCompliancePolicy.requiredMemoryTools)
}

@Test func memoryClaimValidatorClassifiesUnsupportedIndirectAndConflictedClaims() {
    let validator = AgentMemoryClaimValidator()
    #expect(validator.validate(answer: "My budget was 100.", evidencePayloads: [], citations: []).status == .unsupported)
    #expect(validator.validate(answer: "A directly causes B.", evidencePayloads: [#"{"depth":2,"status":"active"}"#], citations: ["edge-2"]).status == .inferred)
    #expect(validator.validate(answer: "当前是方案 A，确定。", evidencePayloads: [#"{"depth":0,"status":"conflicted"}"#], citations: ["record-a"]).status == .conflicted)
    #expect(validator.validate(answer: "Memory suggests an indirect relationship.", evidencePayloads: [#"{"depth":2,"status":"active"}"#], citations: ["edge-2"]).status == .supported)
}

@Test func agentLoopCorrectsConflictedMemoryClaimOnce() async throws {
    let names = AgentRetrievalCompliancePolicy.requiredMemoryTools
    let calls = names.enumerated().map { AgentToolCall(id: "memory-\($0.offset)", name: $0.element, argumentsJSON: "{}") }
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(text: nil, toolCalls: calls, finishReason: .toolCalls),
        AgentModelResponse(text: "当前是方案 A，确定。"),
        AgentModelResponse(text: "记忆记录对当前方案存在冲突：一条支持 A，另一条支持 B，无法消解。")
    ])
    var registry = AgentToolRegistry()
    for name in names {
        let status = name == "memory_os_knowledge_context" ? "conflicted" : "active"
        registry.register(MemoryClaimEvidenceTool(name: name, contentJSON: "{\"status\":\"\(status)\",\"depth\":0}", citations: ["record-\(name)"]))
    }
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    var completed: AgentTextCompleteEvent?
    for try await event in loop.run(AgentChatRequest(sessionID: "claim-conflict", userMessage: "请根据记忆回忆我们之前的方案")) {
        if case .textComplete(let payload) = event { completed = payload }
    }

    #expect(await provider.requests.count == 3)
    #expect(completed?.text.contains("存在冲突") == true)
    #expect(completed?.citations.count == 3)
}

@Test func modelReliabilityRegistryKeysOverridesByExactModelID() {
    let registry = AgentModelReliabilityRegistry(toolResultReliabilityByModelID: ["gpt-exact-1": .verified])
    #expect(registry.toolResultReliability(for: "gpt-exact-1") == .verified)
    #expect(registry.toolResultReliability(for: "gpt-exact-2") == .unknown)
}

@Test func agentLoopPreservesAssistantToolCallBatchBeforeToolResults() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: "I will inspect two values.",
            toolCalls: [
                AgentToolCall(id: "call-batch-1", name: "echo_args", argumentsJSON: #"{"value":"one"}"#),
                AgentToolCall(id: "call-batch-2", name: "echo_args", argumentsJSON: #"{"value":"two"}"#)
            ],
            usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
            finishReason: .toolCalls
        ),
        AgentModelResponse(text: "Done.", usage: AgentModelUsage(promptTokens: 20, completionTokens: 5))
    ])
    var registry = AgentToolRegistry()
    registry.register(EchoArgumentsTool())
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    for try await _ in loop.run(AgentChatRequest(sessionID: "session-batch-transcript", userMessage: "Run two tools")) {}

    let followUpMessages = try #require(await provider.requests.last?.messages)
    let assistantToolMessages = followUpMessages.filter { $0.role == .assistant && $0.toolCalls?.isEmpty == false }
    #expect(assistantToolMessages.count == 1)
    #expect(assistantToolMessages.first?.content == "I will inspect two values.")
    #expect(assistantToolMessages.first?.toolCalls?.map(\.id) == ["call-batch-1", "call-batch-2"])
    let toolMessages = followUpMessages.filter { $0.role == .tool }
    #expect(toolMessages.map(\.toolCallID) == ["call-batch-1", "call-batch-2"])
    #expect(toolMessages.map(\.name) == ["echo_args", "echo_args"])
}

@Test func agentLoopReturnsInvalidArgumentsAsToolResultAndLetsModelRetry() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-invalid-json", name: "echo_args", argumentsJSON: #"["not","object"]"#)],
            usage: AgentModelUsage(promptTokens: 5, completionTokens: 2),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-valid-json", name: "echo_args", argumentsJSON: #"{"value":"recovered"}"#)],
            usage: AgentModelUsage(promptTokens: 5, completionTokens: 2),
            finishReason: .toolCalls
        ),
        AgentModelResponse(text: "Recovered.", usage: AgentModelUsage(promptTokens: 5, completionTokens: 2))
    ])
    var registry = AgentToolRegistry()
    registry.register(EchoArgumentsTool())
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-invalid-retry", userMessage: "Retry after invalid args")) {
        events.append(event)
    }

    #expect(events.map(\.kind).contains(.toolFailed))
    #expect(events.last?.kind == .runCompleted)
    let secondRequest = try #require(await provider.requests.dropFirst().first)
    let errorToolMessage = try #require(secondRequest.messages.first(where: { $0.role == .tool && $0.toolCallID == "call-invalid-json" }))
    #expect(errorToolMessage.content.contains("Tool failed:"))
    #expect(errorToolMessage.content.contains("Invalid arguments"))
}

@Test func agentLoopCompletesVerifiedCalendarDeleteProviderNeutrally() async throws {
    let event = CalendarEvent(id: .init(rawValue: "event:opaque/id"), calendarID: .init(rawValue: "calendar-test"), title: "Connor Test", start: .init(date: Date(timeIntervalSince1970: 1_000)), end: .init(date: Date(timeIntervalSince1970: 4_600)), sourceMetadata: .init(sourceKind: .macOSEventKit, etag: "version-1"))
    let runtime = InMemoryAgentCalendarRuntime(calendars: [.init(id: .init(rawValue: "calendar-test"), accountID: .init(rawValue: "account"), displayName: "Connor Test")], events: [event])
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(text: nil, toolCalls: [.init(id: "search", name: "calendar_search_events", argumentsJSON: #"{"query":"Connor Test"}"#)], usage: .init(promptTokens: 1, completionTokens: 1), finishReason: .toolCalls),
        AgentModelResponse(text: nil, toolCalls: [.init(id: "detail", name: "calendar_read", argumentsJSON: #"{"operation":"get_event","eventID":"event:opaque/id"}"#)], usage: .init(promptTokens: 1, completionTokens: 1), finishReason: .toolCalls),
        AgentModelResponse(text: nil, toolCalls: [.init(id: "delete", name: "calendar_write", argumentsJSON: #"{"operation":"delete_event","eventID":"event:opaque/id","expectedVersion":"version-1"}"#)], usage: .init(promptTokens: 1, completionTokens: 1), finishReason: .toolCalls),
        AgentModelResponse(text: "Deleted safely.", usage: .init(promptTokens: 1, completionTokens: 1))
    ])
    var registry = AgentToolRegistry(); registry.registerNativeCalendarTools(runtime: runtime)
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry, configuration: .init(permissionMode: .askToWrite))
    var events: [AgentEvent] = []
    for try await output in loop.run(.init(runID: "run-verified-delete", sessionID: "session-verified-delete", userMessage: "Delete Connor Test", permissionMode: .askToWrite)) {
        events.append(output)
        if case .permissionRequested(let request) = output { Task { await loop.resolveApproval(.init(requestID: request.id, runID: request.runID, sessionID: request.sessionID, capability: request.capability, toolName: request.toolName, payloadJSON: request.payloadJSON), status: .approved) } }
    }
    #expect(events.filter { $0.kind == .permissionRequested }.count == 1)
    #expect(events.filter { $0.kind == .toolFailed }.isEmpty)
    #expect(try await runtime.getEvent(id: .init(rawValue: "event:opaque/id"), runID: nil, sessionID: nil) == nil)
    let detailFollowUp = try #require(await provider.requests.dropFirst(2).first)
    #expect(detailFollowUp.messages.contains { $0.role == .tool && $0.content.contains("expectedVersion: version-1") })
}

@Test func agentLoopRejectsUnverifiedCalendarMutationBeforeApproval() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(text: nil, toolCalls: [AgentToolCall(id: "calendar-unverified-delete", name: "calendar_write", argumentsJSON: #"{"operation":"delete_event","eventID":"guessed-event","expectedVersion":"1"}"#)], usage: .init(promptTokens: 1, completionTokens: 1), finishReason: .toolCalls),
        AgentModelResponse(text: "Stopped safely.", usage: .init(promptTokens: 1, completionTokens: 1))
    ])
    let runtime = InMemoryAgentCalendarRuntime()
    var registry = AgentToolRegistry()
    registry.registerNativeCalendarTools(runtime: runtime)
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry, configuration: .init(permissionMode: .askToWrite))

    var events: [AgentEvent] = []
    for try await event in loop.run(.init(runID: "run-unverified-calendar", sessionID: "session-unverified-calendar", userMessage: "Delete it", permissionMode: .askToWrite)) { events.append(event) }

    #expect(events.map(\.kind).contains(.toolFailed))
    #expect(!events.map(\.kind).contains(.permissionRequested))
    #expect(events.last?.kind == .runCompleted)
}

@Test func agentLoopRecoversCalendarWriteAfterUnknownCalendarID() async throws {
    let exactID = "calendar-exact-id"
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(text: nil, toolCalls: [AgentToolCall(id: "calendar-bad", name: "calendar_write", argumentsJSON: #"{"operation":"create_event","calendarID":"default","title":"Test","start":"2026-07-12T01:30:00Z","end":"2026-07-12T02:00:00Z"}"#)], usage: .init(promptTokens: 1, completionTokens: 1), finishReason: .toolCalls),
        AgentModelResponse(text: nil, toolCalls: [AgentToolCall(id: "calendar-list", name: "calendar_read", argumentsJSON: #"{"operation":"list_calendars"}"#)], usage: .init(promptTokens: 1, completionTokens: 1), finishReason: .toolCalls),
        AgentModelResponse(text: nil, toolCalls: [AgentToolCall(id: "calendar-good", name: "calendar_write", argumentsJSON: #"{"operation":"create_event","calendarID":"calendar-exact-id","title":"Test","start":"2026-07-12T01:30:00Z","end":"2026-07-12T02:00:00Z"}"#)], usage: .init(promptTokens: 1, completionTokens: 1), finishReason: .toolCalls),
        AgentModelResponse(text: "Created safely.", usage: .init(promptTokens: 1, completionTokens: 1))
    ])
    let runtime = InMemoryAgentCalendarRuntime(calendars: [.init(id: .init(rawValue: exactID), accountID: .init(rawValue: "account"), displayName: "Connor Test")])
    var registry = AgentToolRegistry()
    registry.registerNativeCalendarTools(runtime: runtime)
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry, configuration: .init(permissionMode: .allowAll))

    var events: [AgentEvent] = []
    for try await event in loop.run(.init(runID: "run-calendar-recovery", sessionID: "session-calendar-recovery", userMessage: "Create a test event", permissionMode: .allowAll)) {
        events.append(event)
        if case .permissionRequested(let request) = event {
            Task {
                await loop.resolveApproval(.init(requestID: request.id, runID: request.runID, sessionID: request.sessionID, capability: request.capability, toolName: request.toolName, payloadJSON: request.payloadJSON), status: .approved)
            }
        }
    }

    #expect(events.map(\.kind).contains(.toolFailed))
    #expect(events.last?.kind == .runCompleted)
    let recoveryRequest = try #require(await provider.requests.dropFirst().first)
    let failure = try #require(recoveryRequest.messages.first { $0.role == .tool && $0.toolCallID == "calendar-bad" })
    #expect(failure.content.contains("Calendar 'default' was not found"))
    #expect(failure.content.contains("list_calendars"))
    let createdEvents = try await runtime.listEvents(calendarID: .init(rawValue: exactID), runID: nil, sessionID: nil)
    #expect(createdEvents.count == 1)
}

@Test func agentLoopReturnsUnknownToolAsToolResultAndLetsModelRecover() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-unknown", name: "missing_tool", argumentsJSON: #"{}"#)],
            usage: AgentModelUsage(promptTokens: 5, completionTokens: 2),
            finishReason: .toolCalls
        ),
        AgentModelResponse(text: "I can recover without that tool.", usage: AgentModelUsage(promptTokens: 5, completionTokens: 2))
    ])
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: AgentToolRegistry())

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-unknown-tool", userMessage: "Call unknown")) {
        events.append(event)
    }

    #expect(events.map(\.kind).contains(.toolFailed))
    #expect(events.last?.kind == .runCompleted)
    let followUp = try #require(await provider.requests.last)
    let errorToolMessage = try #require(followUp.messages.first(where: { $0.role == .tool && $0.toolCallID == "call-unknown" }))
    #expect(errorToolMessage.content.contains("Unknown tool"))
}

@Test func agentLoopContinuesDespiteConsecutiveToolResultErrors() async throws {
    let errorResponses = (1...3).map { index in
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-error-\(index)", name: "missing_tool", argumentsJSON: #"{}"#)],
            usage: AgentModelUsage(promptTokens: 1, completionTokens: 1),
            finishReason: .toolCalls
        )
    }
    let recoveryResponse = AgentModelResponse(text: "Recovered.", usage: AgentModelUsage(promptTokens: 1, completionTokens: 1))
    let provider = ScriptedModelProvider(responses: errorResponses + [recoveryResponse])
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        configuration: AgentLoopConfiguration(maxToolIterations: 8, maxConsecutiveToolResultErrors: 0)
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-errors-no-fuse", userMessage: "Keep failing then recover")) {
        events.append(event)
    }

    #expect(events.map(\.kind).filter { $0 == .toolFailed }.count == 3)
    #expect(events.last?.kind == .runCompleted)
}

@Test func agentLoopStopsAtConfiguredConsecutiveToolResultErrorLimit() async throws {
    let provider = ScriptedModelProvider(responses: (1...3).map { index in
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-limited-error-\(index)", name: "missing_tool_\(index)", argumentsJSON: #"{}"#)],
            usage: AgentModelUsage(promptTokens: 1, completionTokens: 1),
            finishReason: .toolCalls
        )
    })
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: AgentToolRegistry(),
        configuration: AgentLoopConfiguration(maxToolIterations: 8, maxConsecutiveToolResultErrors: 2)
    )

    var events: [AgentEvent] = []
    do {
        for try await event in loop.run(AgentChatRequest(sessionID: "session-errors-limited", userMessage: "Stop after repeated failures")) {
            events.append(event)
        }
        Issue.record("Expected the configured consecutive tool error limit to stop the run")
    } catch {
        #expect(error as? AgentLoopError == .consecutiveToolResultErrorsReached)
    }

    #expect(events.map(\.kind).filter { $0 == .toolFailed }.count == 2)
    #expect(events.last?.kind == .runFailed)
    let failureMessages = events.compactMap { event -> String? in
        if case .runFailed(let failure) = event { return failure.message }
        return nil
    }
    #expect(failureMessages.last?.contains("2 consecutive tool result errors") == true)
}

@Test func successfulToolResultResetsConsecutiveErrorCount() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-error-before-success", name: "missing_tool_before", argumentsJSON: #"{}"#)],
            usage: AgentModelUsage(promptTokens: 1, completionTokens: 1),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-success-reset", name: "echo_args", argumentsJSON: #"{"value":"reset"}"#)],
            usage: AgentModelUsage(promptTokens: 1, completionTokens: 1),
            finishReason: .toolCalls
        ),
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-error-after-success", name: "missing_tool_after", argumentsJSON: #"{}"#)],
            usage: AgentModelUsage(promptTokens: 1, completionTokens: 1),
            finishReason: .toolCalls
        ),
        AgentModelResponse(text: "Recovered after reset.", usage: AgentModelUsage(promptTokens: 1, completionTokens: 1))
    ])
    var registry = AgentToolRegistry()
    registry.register(EchoArgumentsTool())
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(maxToolIterations: 8, maxConsecutiveToolResultErrors: 2)
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-errors-reset", userMessage: "Recover between failures")) {
        events.append(event)
    }

    #expect(events.map(\.kind).filter { $0 == .toolFailed }.count == 2)
    #expect(events.map(\.kind).contains(.toolFinished))
    #expect(events.last?.kind == .runCompleted)
}

@Test func agentLoopParallelToolCallsAppendToolResultsInAssistantSourceOrder() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [
                AgentToolCall(id: "call-slow", name: "slow_tool", argumentsJSON: #"{}"#),
                AgentToolCall(id: "call-fast", name: "fast_tool", argumentsJSON: #"{}"#)
            ],
            usage: AgentModelUsage(promptTokens: 5, completionTokens: 2),
            finishReason: .toolCalls
        ),
        AgentModelResponse(text: "Parallel done.", usage: AgentModelUsage(promptTokens: 5, completionTokens: 2))
    ])
    var registry = AgentToolRegistry()
    registry.register(NamedDelayTool(name: "slow_tool", delayNanoseconds: 60_000_000))
    registry.register(NamedDelayTool(name: "fast_tool", delayNanoseconds: 1_000_000))
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(allowParallelToolCalls: true)
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-parallel-order", userMessage: "Run parallel")) {
        events.append(event)
    }

    let finishedNames = events.compactMap { event -> String? in
        if case .toolFinished(let result) = event { return result.toolName }
        return nil
    }
    #expect(finishedNames.first == "fast_tool")
    let followUp = try #require(await provider.requests.last)
    let toolMessages = followUp.messages.filter { $0.role == .tool }
    #expect(toolMessages.map(\.toolCallID) == ["call-slow", "call-fast"])
}

@Test func agentLoopEmitsTurnBoundariesAroundModelCallAndToolBatch() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-turn", name: "echo_args", argumentsJSON: #"{"value":"turn"}"#)],
            usage: AgentModelUsage(promptTokens: 5, completionTokens: 2),
            finishReason: .toolCalls
        ),
        AgentModelResponse(text: "Turn done.", usage: AgentModelUsage(promptTokens: 5, completionTokens: 2))
    ])
    var registry = AgentToolRegistry()
    registry.register(EchoArgumentsTool())
    let loop = AgentLoopController(modelProvider: provider, toolRegistry: registry)

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-turn-events", userMessage: "Emit turns")) {
        events.append(event)
    }

    #expect(events.map(\.kind).filter { $0 == .turnStarted }.count == 2)
    #expect(events.map(\.kind).filter { $0 == .turnCompleted }.count == 2)
    let completedTurns = events.compactMap { event -> AgentTurnCompletedEvent? in
        if case .turnCompleted(let payload) = event { return payload }
        return nil
    }
    #expect(completedTurns.first?.toolCallCount == 1)
    #expect(completedTurns.first?.toolResultCount == 1)
    #expect(completedTurns.last?.toolCallCount == 0)
}

@Test func agentLoopCanStopGracefullyAfterBudgetExceededTurn() async throws {
    let provider = ScriptedModelProvider(responses: [
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-budget-stop", name: "echo_args", argumentsJSON: #"{"value":"budget"}"#)],
            usage: AgentModelUsage(promptTokens: 200, completionTokens: 50),
            finishReason: .toolCalls
        )
    ])
    var registry = AgentToolRegistry()
    registry.register(EchoArgumentsTool())
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(
            maxToolIterations: 4,
            stopAfterTurnWhenBudgetExceeded: true,
            budget: AgentBudgetConfiguration(maxTotalTokens: 100, warningThresholdRatio: 0.8)
        )
    )

    var events: [AgentEvent] = []
    for try await event in loop.run(AgentChatRequest(sessionID: "session-budget-stop", userMessage: "Stop after turn")) {
        events.append(event)
    }

    #expect(await provider.requests.count == 1)
    #expect(events.map(\.kind).contains(.budgetWarning))
    let turnCompleted = try #require(events.compactMap { event -> AgentTurnCompletedEvent? in
        if case .turnCompleted(let payload) = event { return payload }
        return nil
    }.first)
    #expect(turnCompleted.stoppedAfterTurn)
    #expect(events.last?.kind == .runCompleted)
}
