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

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return AgentModelResponse(text: "should not complete")
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }
}

@Test func agentLoopConfigurationDefaultsAllowDeeperSingleRunWork() {
    let configuration = AgentLoopConfiguration()

    #expect(configuration.maxToolIterations == 64)
    #expect(configuration.maxToolCallsPerIteration == 4)
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

    try await Task.sleep(nanoseconds: 100_000_000)
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
    let definition = AgentToolDefinition(
        name: "echo_args",
        description: "Echo arguments",
        inputSchema: .object(properties: ["value": .string(description: "Value")], required: ["value"])
    )

    func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let value = arguments.object["value"]?.stringValue ?? ""
        return AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: definition.name,
            contentText: value
        )
    }
}

@Test func agentLoopDoesNotTreatSameToolWithDifferentArgumentsAsLoop() async throws {
    let toolResponses = (1...12).map { index in
        AgentModelResponse(
            text: nil,
            toolCalls: [AgentToolCall(id: "call-echo-\(index)", name: "echo_args", argumentsJSON: #"{"value":"step-\\#(index)"}"#)],
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

@Test func agentLoopInjectsInitialGraphContextIntoModelRequest() async throws {
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
    #expect(request?.messages.contains(where: { $0.role == .system && $0.content.contains("Relevant Graph Memory Context") }) == true)
    #expect(request?.messages.contains(where: { $0.content.contains("诗闻喜欢结构化推进") }) == true)
    let textComplete = events.compactMap { event -> AgentTextCompleteEvent? in
        if case .textComplete(let payload) = event { return payload }
        return nil
    }.first
    #expect(textComplete?.citations == ["episode:episode-1"])
    #expect(textComplete?.contextSnapshot?.contains("诗闻喜欢结构化推进") == true)
}
