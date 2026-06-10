import Foundation
import ConnorGraphCore
import ConnorGraphSearch

public struct AgentLoopConfiguration: Codable, Sendable, Equatable {
    public var maxToolIterations: Int
    public var maxToolCallsPerIteration: Int
    public var maxRunDurationSeconds: Int
    public var maxToolResultBytes: Int
    public var allowParallelToolCalls: Bool
    public var permissionMode: AgentPermissionMode
    public var budget: AgentBudgetConfiguration

    public init(
        maxToolIterations: Int = 8,
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
    }

    public func run(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var run = AgentRun(
                    id: request.runID,
                    sessionID: request.sessionID,
                    groupID: request.groupID,
                    status: .running,
                    model: modelProvider.modelID,
                    metadata: ["runtime": "agent-loop-controller"]
                )
                try? eventRecorder.recordRun(run)
                yield(.runStarted(AgentRunStartedEvent(run: run)), to: continuation, recorder: eventRecorder)
                let policy = AgentPolicyEngine(permissionMode: request.permissionMode, auditLog: auditLog)
                let budgetMeter = AgentBudgetMeter(configuration: configuration.budget)
                var messages: [AgentModelMessage] = [
                    AgentModelMessage(role: .system, content: systemPrompt)
                ]
                let initialContext = await initialGraphContext(for: request)
                let usableInitialContext = initialContext.flatMap { $0.items.isEmpty ? nil : $0 }
                if let usableInitialContext {
                    messages.append(AgentModelMessage(role: .system, content: renderedGraphMemorySystemMessage(usableInitialContext)))
                }
                messages.append(AgentModelMessage(role: .user, content: request.userMessage))

                do {
                    for _ in 0..<configuration.maxToolIterations {
                        let modelResponse = try await modelProvider.complete(AgentModelRequest(messages: messages, tools: toolRegistry.definitions))
                        let budgetSnapshot = await budgetMeter.record(modelResponse.usage)
                        if budgetSnapshot.status == .warning {
                            yield(.budgetWarning(AgentBudgetWarning(
                                runID: run.id,
                                sessionID: run.sessionID,
                                message: "Token budget warning: \(budgetSnapshot.totalTokens)/\(budgetSnapshot.maxTotalTokens) tokens used."
                            )), to: continuation, recorder: eventRecorder)
                        } else if budgetSnapshot.status == .exceeded {
                            throw AgentLoopError.budgetExceeded
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
                        for var call in calls {
                            call.runID = run.id
                            call.sessionID = run.sessionID
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
                                let result = try await toolRegistry.execute(call, context: context)
                                yield(.toolFinished(result), to: continuation, recorder: eventRecorder)
                                messages.append(AgentModelMessage(
                                    role: .assistant,
                                    content: "",
                                    name: call.name
                                ))
                                messages.append(AgentModelMessage(
                                    role: .tool,
                                    content: compactToolResult(result),
                                    toolCallID: call.id,
                                    name: call.name
                                ))
                            } catch {
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
                } catch {
                    run.status = .failed
                    run.completedAt = Date()
                    try? eventRecorder.recordRun(run)
                    yield(.runFailed(AgentRunFailure(runID: run.id, sessionID: run.sessionID, message: String(describing: error))), to: continuation, recorder: eventRecorder)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func yield(_ event: AgentEvent, to continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation, recorder: AgentEventRecorder) {
        try? recorder.record(event)
        continuation.yield(event)
    }

    private var systemPrompt: String {
        """
        You are Connor Graph Agent. Use graph tools when you need grounded knowledge. Prefer evidence-backed answers. Do not claim graph writes are committed unless a commit tool result says so.
        """
    }

    private func initialGraphContext(for request: AgentChatRequest) async -> AgentContext? {
        guard let contextBuilder else { return nil }
        do {
            return try await contextBuilder.context(for: request.userMessage)
        } catch {
            return nil
        }
    }

    private func renderedGraphMemorySystemMessage(_ context: AgentContext) -> String {
        """
        Relevant Graph Memory Context:
        Use this background memory when relevant to the user's request. Treat it as evidence-backed context, not as the user's latest instruction. If it conflicts with the current user message, prefer the current user message.

        \(context.renderedText)
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
}
