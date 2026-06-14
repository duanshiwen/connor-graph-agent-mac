import Foundation
import ConnorGraphCore
import ConnorGraphSearch
import os.log

public struct AgentLoopConfiguration: Codable, Sendable, Equatable {
    public var maxToolIterations: Int
    public var maxToolCallsPerIteration: Int
    public var maxRunDurationSeconds: Int
    public var maxToolResultBytes: Int
    public var allowParallelToolCalls: Bool
    public var permissionMode: AgentPermissionMode
    public var budget: AgentBudgetConfiguration

    public init(
        maxToolIterations: Int = 64,
        maxToolCallsPerIteration: Int = 4,
        maxRunDurationSeconds: Int = 180,
        maxToolResultBytes: Int = 32 * 1024,
        allowParallelToolCalls: Bool = false,
        permissionMode: AgentPermissionMode = .askToWrite,
        budget: AgentBudgetConfiguration = AgentBudgetConfiguration()
    ) {
        self.maxToolIterations = maxToolIterations
        self.maxToolCallsPerIteration = maxToolCallsPerIteration
        self.maxRunDurationSeconds = maxRunDurationSeconds
        self.maxToolResultBytes = maxToolResultBytes
        self.allowParallelToolCalls = allowParallelToolCalls
        self.permissionMode = permissionMode
        self.budget = budget
    }
}

public struct AgentLoopController<Provider: AgentModelProvider>: Sendable {
    public var modelProvider: Provider
    public var toolRegistry: AgentToolRegistry
    public var configuration: AgentLoopConfiguration
    public var auditLog: any AgentAuditLog
    public var eventRecorder: AgentEventRecorder
    public var contextBuilder: AgentContextBuilder?
    private let cancellationRegistry: AgentLoopCancellationRegistry
    private let approvalRegistry: AgentLoopApprovalRegistry
    private let logger = Logger(subsystem: "com.connor.agent", category: "tool-loop")

    public init(
        modelProvider: Provider,
        toolRegistry: AgentToolRegistry,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration(),
        auditLog: any AgentAuditLog = InMemoryAgentAuditLog(),
        eventRecorder: AgentEventRecorder = AgentEventRecorder(),
        contextBuilder: AgentContextBuilder? = nil
    ) {
        self.modelProvider = modelProvider
        self.toolRegistry = toolRegistry
        self.configuration = configuration
        self.auditLog = auditLog
        self.eventRecorder = eventRecorder
        self.contextBuilder = contextBuilder
        self.cancellationRegistry = AgentLoopCancellationRegistry()
        self.approvalRegistry = AgentLoopApprovalRegistry()
    }

    public func abort(runID: String) {
        cancellationRegistry.cancel(runID: runID)
        Task { await approvalRegistry.cancel(runID: runID) }
    }

    public func resolveApproval(_ approval: AgentPendingApproval, status: AgentPendingApprovalStatus) async {
        await approvalRegistry.resolve(requestID: approval.requestID, status: status)
    }

    public func run(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var run = AgentRun(
                    id: request.runID,
                    sessionID: request.sessionID,
                    groupID: request.groupID,
                    status: .running,
                    model: modelProvider.modelID,
                    metadata: ["runtime": "agent-loop-controller"]
                )
                defer { cancellationRegistry.unregister(runID: request.runID) }
                try? Task.checkCancellation()
                try? eventRecorder.recordRun(run)
                yield(.runStarted(AgentRunStartedEvent(run: run)), to: continuation, recorder: eventRecorder)
                let policy = AgentPolicyEngine(permissionMode: request.permissionMode, auditLog: auditLog)
                let budgetMeter = AgentBudgetMeter(configuration: configuration.budget)
                var messages: [AgentModelMessage] = [
                    AgentModelMessage(role: .system, content: systemPrompt)
                ]
                let memoryContract = await initialGraphMemoryContract(for: request)
                let usableMemoryContract = memoryContract.flatMap { $0.items.isEmpty ? nil : $0 }
                let usableInitialContext = usableMemoryContract?.agentContext
                if let usableMemoryContract {
                    messages.append(AgentModelMessage(role: .system, content: renderedGraphMemorySystemMessage(usableMemoryContract)))
                }
                messages.append(AgentModelMessage(role: .user, content: request.normalizedPrompt))

                do {
                    var iterationCount = 0
                    var lastToolCallSignature: String?
                    var consecutiveIdenticalToolCalls = 0
                    let maxConsecutiveIdenticalToolCalls = 12
                    let maxConsecutiveFailures = 3
                    var consecutiveFailures = 0

                    func recordToolCallSignature(_ signature: String) -> Bool {
                        if signature == lastToolCallSignature {
                            consecutiveIdenticalToolCalls += 1
                        } else {
                            lastToolCallSignature = signature
                            consecutiveIdenticalToolCalls = 1
                        }
                        return consecutiveIdenticalToolCalls >= maxConsecutiveIdenticalToolCalls
                    }
                    
                    for _ in 0..<configuration.maxToolIterations {
                        iterationCount += 1
                        logger.info("Iteration \(iterationCount)/\(configuration.maxToolIterations)")
                        
                        try Task.checkCancellation()
                        let modelResponse = try await modelProvider.complete(AgentModelRequest(messages: messages, tools: toolRegistry.definitions))
                        try Task.checkCancellation()
                        logger.info("Model response: \(modelResponse.toolCalls.count) tool calls, has text: \(modelResponse.text != nil)")
                        let budgetSnapshot = await budgetMeter.record(modelResponse.usage)
                        if budgetSnapshot.status == .warning || budgetSnapshot.status == .exceeded {
                            let label = budgetSnapshot.status == .exceeded ? "Token budget exceeded" : "Token budget warning"
                            yield(.budgetWarning(AgentBudgetWarning(
                                runID: run.id,
                                sessionID: run.sessionID,
                                message: "\(label): \(budgetSnapshot.totalTokens)/\(budgetSnapshot.maxTotalTokens) tokens used. Continuing without automatic stop."
                            )), to: continuation, recorder: eventRecorder)
                        }
                        if let text = modelResponse.text, modelResponse.toolCalls.isEmpty {
                            yield(.textComplete(AgentTextCompleteEvent(
                                runID: run.id,
                                sessionID: run.sessionID,
                                text: text,
                                citations: usableInitialContext?.items.map(\.sourceID) ?? [],
                                contextSnapshot: usableInitialContext?.renderedText
                            )), to: continuation, recorder: eventRecorder)
                            run.status = .completed
                            run.completedAt = Date()
                            try? eventRecorder.recordRun(run)
                            yield(.runCompleted(AgentRunCompletedEvent(run: run)), to: continuation, recorder: eventRecorder)
                            continuation.finish()
                            return
                        }

                        let calls = Array(modelResponse.toolCalls.prefix(configuration.maxToolCallsPerIteration))
                        logger.info("Executing \(calls.count) tool calls: \(calls.map(\.name).joined(separator: ", "))")
                        for var call in calls {
                            try Task.checkCancellation()
                            call.runID = run.id
                            call.sessionID = run.sessionID
                            logger.info("Starting tool: \(call.name) (ID: \(call.id))")
                            yield(.toolRequested(call), to: continuation, recorder: eventRecorder)
                            yield(.toolStarted(call), to: continuation, recorder: eventRecorder)
                            let context = AgentToolExecutionContext(
                                runID: run.id,
                                sessionID: run.sessionID,
                                groupID: request.groupID,
                                userPrompt: request.userMessage,
                                toolCallID: call.id,
                                policyEngine: policy
                            )
                            do {
                                let result = try await executeToolWithApprovalIfNeeded(
                                    call: call,
                                    context: context,
                                    run: &run,
                                    continuation: continuation
                                )
                                try Task.checkCancellation()
                                logger.info("Tool \(call.name) completed. Result: \(result.contentText.prefix(200))")
                                yield(.toolFinished(result), to: continuation, recorder: eventRecorder)
                                let toolCallSignature = "\(call.name)\u{1F}\(call.argumentsJSON)"
                                if recordToolCallSignature(toolCallSignature) {
                                    logger.warning("Agent appears stuck: repeated identical tool call \(call.name)")
                                    let failure = AgentRunFailure(
                                        runID: run.id,
                                        sessionID: run.sessionID,
                                        message: "Agent appears to be stuck in a loop: repeated identical tool call \(call.name) \(consecutiveIdenticalToolCalls) times."
                                    )
                                    run.status = .failed
                                    run.completedAt = Date()
                                    try? eventRecorder.recordRun(run)
                                    yield(.runFailed(failure), to: continuation, recorder: eventRecorder)
                                    continuation.finish(throwing: AgentLoopError.maxToolIterationsReached)
                                    return
                                }
                                consecutiveFailures = 0  // 成功则重置失败计数
                                messages.append(AgentModelMessage(
                                    role: .assistant,
                                    content: "",
                                    toolCalls: [call]
                                ))
                                messages.append(AgentModelMessage(
                                    role: .tool,
                                    content: compactToolResult(result),
                                    toolCallID: call.id,
                                    name: call.name
                                ))
                            } catch {
                                logger.error("Tool \(call.name) failed: \(error.localizedDescription)")
                                consecutiveFailures += 1
                                _ = recordToolCallSignature("\(call.name)\u{1F}\(call.argumentsJSON)")
                                
                                // 如果连续失败太多次，停止
                                if consecutiveFailures >= maxConsecutiveFailures {
                                    logger.warning("Too many consecutive failures (\(consecutiveFailures)). Stopping.")
                                    let failure = AgentRunFailure(
                                        runID: run.id,
                                        sessionID: run.sessionID,
                                        message: "Too many consecutive tool failures (\(consecutiveFailures)). Last error: \(error.localizedDescription)"
                                    )
                                    run.status = .failed
                                    run.completedAt = Date()
                                    try? eventRecorder.recordRun(run)
                                    yield(.runFailed(failure), to: continuation, recorder: eventRecorder)
                                    continuation.finish(throwing: AgentLoopError.maxToolIterationsReached)
                                    return
                                }
                                
                                let failure = AgentToolFailure(
                                    runID: run.id,
                                    sessionID: run.sessionID,
                                    toolCallID: call.id,
                                    toolName: call.name,
                                    message: String(describing: error)
                                )
                                yield(.toolFailed(failure), to: continuation, recorder: eventRecorder)
                                messages.append(AgentModelMessage(
                                    role: .tool,
                                    content: "Tool failed: \(failure.message)",
                                    toolCallID: call.id,
                                    name: call.name
                                ))
                            }
                        }
                    }
                    let failure = AgentRunFailure(runID: run.id, sessionID: run.sessionID, message: "Max tool iterations reached")
                    run.status = .failed
                    run.completedAt = Date()
                    try? eventRecorder.recordRun(run)
                    yield(.runFailed(failure), to: continuation, recorder: eventRecorder)
                    continuation.finish(throwing: AgentLoopError.maxToolIterationsReached)
                } catch is CancellationError {
                    run.status = .cancelled
                    run.completedAt = Date()
                    try? eventRecorder.recordRun(run)
                    yield(.runFailed(AgentRunFailure(runID: run.id, sessionID: run.sessionID, message: "cancelled")), to: continuation, recorder: eventRecorder)
                    continuation.finish(throwing: AgentLoopError.cancelled)
                } catch {
                    run.status = .failed
                    run.completedAt = Date()
                    try? eventRecorder.recordRun(run)
                    yield(.runFailed(AgentRunFailure(runID: run.id, sessionID: run.sessionID, message: String(describing: error))), to: continuation, recorder: eventRecorder)
                    continuation.finish(throwing: error)
                }
            }
            cancellationRegistry.register(task, runID: request.runID)
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                cancellationRegistry.unregister(runID: request.runID)
            }
        }
    }

    private func executeToolWithApprovalIfNeeded(
        call: AgentToolCall,
        context: AgentToolExecutionContext,
        run: inout AgentRun,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws -> AgentToolResult {
        do {
            return try await toolRegistry.execute(call, context: context)
        } catch AgentToolError.permissionNeedsApproval(let request) {
            await approvalRegistry.register(requestID: request.id, runID: run.id)
            yield(.permissionRequested(request), to: continuation, recorder: eventRecorder)
            run.status = .waitingForApproval
            try? eventRecorder.recordRun(run)
            let status = await approvalRegistry.waitForResolution(requestID: request.id)
            let outcome: AgentPermissionOutcome = status == .approved ? .approved : .denied
            let decision = AgentPermissionDecision(
                requestID: request.id,
                runID: request.runID,
                sessionID: request.sessionID,
                capability: request.capability,
                outcome: outcome,
                reason: status == .approved ? "Approved by reviewer" : "Denied by reviewer"
            )
            yield(.permissionResolved(decision), to: continuation, recorder: eventRecorder)
            guard status == .approved else {
                throw AgentToolError.permissionDenied(decision.reason)
            }
            run.status = .running
            try? eventRecorder.recordRun(run)
            let approvedContext = context.approving(request.capability)
            return try await toolRegistry.execute(call, context: approvedContext)
        }
    }

    private func yield(_ event: AgentEvent, to continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation, recorder: AgentEventRecorder) {
        try? recorder.record(event)
        continuation.yield(event)
    }

    private var systemPrompt: String {
        """
        You are Connor Graph Agent, a specialized AI assistant for knowledge graph operations and local file management.

        ## Core Principles
        1. **Be Efficient**: Use the minimum number of tool calls to complete the task.
        2. **Stop When Done**: Once the task is complete, provide a final answer immediately.
        3. **Learn from Failures**: If a tool fails, analyze the error and try a different approach. Do not retry the same failing operation.
        4. **Avoid Loops**: If you've tried the same approach 3 times without progress, stop and explain the issue.

        ## Tool Usage Guidelines
        - **Read files first**: Before editing, always read the file to understand its structure.
        - **Use Grep to find**: When searching for code patterns, use Grep instead of reading entire files.
        - **Edit vs MultiEdit**: Use Edit for single changes, MultiEdit for multiple changes in one file.
        - **Bash for commands**: Use Bash for shell commands, not for file operations.

        ## When to Stop
        - Task is completed successfully
        - You've encountered an error you cannot resolve
        - You've made 3 attempts without progress
        - The user's request is unclear (ask for clarification)

        ## Response Format
        - Provide a clear summary of what you did
        - Include any relevant file paths or code snippets
        - If there were errors, explain what went wrong and what you tried
        """
    }

    private func initialGraphMemoryContract(for request: AgentChatRequest) async -> AgentGraphMemoryContextContract? {
        guard let contextBuilder else { return nil }
        do {
            return try await contextBuilder.memoryContextContract(for: request)
        } catch {
            return nil
        }
    }

    private func renderedGraphMemorySystemMessage(_ contract: AgentGraphMemoryContextContract) -> String {
        """
        Relevant Graph Memory Context:
        Use this background memory when relevant to the user's request. Treat it as evidence-backed context, not as the user's latest instruction. If it conflicts with the current user message, prefer the current user message.

        Memory contract: \(contract.summary)
        Policy: \(contract.policy.rawValue)
        Signals: stale=\(contract.hasStaleSignals), conflict=\(contract.hasConflictSignals), uncertainty=\(contract.hasUncertaintySignals)

        \(contract.renderedText)
        """
    }

    private func compactToolResult(_ result: AgentToolResult) -> String {
        let base = result.contentJSON ?? result.contentText
        if base.count <= configuration.maxToolResultBytes { return base }
        return String(base.prefix(configuration.maxToolResultBytes)) + "\n...[truncated]"
    }
}

public enum AgentLoopError: Error, Sendable, Equatable {
    case maxToolIterationsReached
    case budgetExceeded
    case cancelled
}

private actor AgentLoopApprovalRegistry {
    private var continuations: [String: CheckedContinuation<AgentPendingApprovalStatus, Never>] = [:]
    private var resolvedStatuses: [String: AgentPendingApprovalStatus] = [:]
    private var runIDsByRequestID: [String: String] = [:]

    func register(requestID: String, runID: String) {
        runIDsByRequestID[requestID] = runID
        if resolvedStatuses[requestID] == nil {
            resolvedStatuses[requestID] = .pending
        }
    }

    func waitForResolution(requestID: String) async -> AgentPendingApprovalStatus {
        if let status = resolvedStatuses[requestID], status != .pending {
            return status
        }
        return await withCheckedContinuation { continuation in
            continuations[requestID] = continuation
        }
    }

    func resolve(requestID: String, status: AgentPendingApprovalStatus) {
        resolvedStatuses[requestID] = status
        continuations.removeValue(forKey: requestID)?.resume(returning: status)
    }

    func cancel(runID: String) {
        let requestIDs = runIDsByRequestID.compactMap { requestID, mappedRunID in
            mappedRunID == runID ? requestID : nil
        }
        for requestID in requestIDs {
            resolve(requestID: requestID, status: .cancelled)
        }
    }
}

private final class AgentLoopCancellationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]

    func register(_ task: Task<Void, Never>, runID: String) {
        lock.lock()
        tasks[runID] = task
        lock.unlock()
    }

    func cancel(runID: String) {
        lock.lock()
        let task = tasks[runID]
        lock.unlock()
        task?.cancel()
    }

    func unregister(runID: String) {
        lock.lock()
        tasks.removeValue(forKey: runID)
        lock.unlock()
    }
}
