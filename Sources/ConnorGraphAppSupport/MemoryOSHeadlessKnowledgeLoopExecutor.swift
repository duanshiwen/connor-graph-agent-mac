import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct MemoryOSBackgroundToolLoopConfiguration: Codable, Sendable, Equatable {
    public var maxToolIterations: Int
    public var maxToolCallsPerIteration: Int
    public var maxRunDurationSeconds: Int
    public var maxToolResultBytes: Int

    public init(
        maxToolIterations: Int = 256,
        maxToolCallsPerIteration: Int = 4,
        maxRunDurationSeconds: Int = 1800,
        maxToolResultBytes: Int = 32 * 1024
    ) {
        self.maxToolIterations = maxToolIterations
        self.maxToolCallsPerIteration = maxToolCallsPerIteration
        self.maxRunDurationSeconds = maxRunDurationSeconds
        self.maxToolResultBytes = maxToolResultBytes
    }
}

public struct MemoryOSBackgroundLoopMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var role: MemoryOSBackgroundMessageRole
    public var content: String
    public var toolCallID: String?
    public var toolName: String?
    public var toolCalls: [MemoryOSBackgroundToolCall]?

    public init(id: String = UUID().uuidString, role: MemoryOSBackgroundMessageRole, content: String, toolCallID: String? = nil, toolName: String? = nil, toolCalls: [MemoryOSBackgroundToolCall]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolCalls = toolCalls
    }
}

public struct MemoryOSBackgroundLoopModelRequest: Sendable, Equatable {
    public var runID: String
    public var job: MemoryOSBackgroundModelRequest
    public var messages: [MemoryOSBackgroundLoopMessage]
    public var availableTools: [MemoryOSBackgroundToolDescriptor]

    public init(runID: String, job: MemoryOSBackgroundModelRequest, messages: [MemoryOSBackgroundLoopMessage], availableTools: [MemoryOSBackgroundToolDescriptor]) {
        self.runID = runID
        self.job = job
        self.messages = messages
        self.availableTools = availableTools
    }
}

public struct MemoryOSBackgroundLoopModelResponse: Sendable, Equatable {
    public var assistantText: String
    public var toolCalls: [MemoryOSBackgroundToolCall]
    public var finalArtifactJSON: String?
    public var metadata: [String: String]

    public init(assistantText: String = "", toolCalls: [MemoryOSBackgroundToolCall] = [], finalArtifactJSON: String? = nil, metadata: [String: String] = [:]) {
        self.assistantText = assistantText
        self.toolCalls = toolCalls
        self.finalArtifactJSON = finalArtifactJSON
        self.metadata = metadata
    }
}

public protocol MemoryOSBackgroundToolLoopModel: Sendable {
    var modelID: String { get }
    func complete(_ request: MemoryOSBackgroundLoopModelRequest) throws -> MemoryOSBackgroundLoopModelResponse
}

public enum MemoryOSHeadlessKnowledgeLoopError: Error, Sendable, Equatable, CustomStringConvertible {
    case exceededMaxIterations(Int)
    case exceededMaxRunDuration(Int)
    case missingFinalArtifact

    public var description: String {
        switch self {
        case .exceededMaxIterations(let value): "exceededMaxIterations: \(value)"
        case .exceededMaxRunDuration(let value): "exceededMaxRunDuration: \(value)"
        case .missingFinalArtifact: "missingFinalArtifact"
        }
    }
}

public typealias MemoryOSLoopLogHandler = @Sendable (_ message: String) -> Void

public struct MemoryOSHeadlessKnowledgeLoopExecutor<Model: MemoryOSBackgroundToolLoopModel>: MemoryOSBackgroundModelExecutor, @unchecked Sendable {
    public var model: Model
    public var toolExecutor: MemoryOSBackgroundToolExecutor
    public var store: SQLiteMemoryOSStore
    public var configuration: MemoryOSBackgroundToolLoopConfiguration
    public var now: @Sendable () -> Date
    public var logHandler: MemoryOSLoopLogHandler?

    public init(
        model: Model,
        toolExecutor: MemoryOSBackgroundToolExecutor,
        store: SQLiteMemoryOSStore,
        configuration: MemoryOSBackgroundToolLoopConfiguration = MemoryOSBackgroundToolLoopConfiguration(),
        now: @escaping @Sendable () -> Date = Date.init,
        logHandler: MemoryOSLoopLogHandler? = nil
    ) {
        self.model = model
        self.toolExecutor = toolExecutor
        self.store = store
        self.configuration = configuration
        self.now = now
        self.logHandler = logHandler
    }

    public func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse {
        let startedAt = now()
        let runID = request.metadata["background_run_id"] ?? UUID().uuidString
        let source = MemoryOSBackgroundJobKind.isL1KnowledgeKind(request.kind) ? "l1_capture_events" : "l2_statements"
        var run = MemoryOSBackgroundRunRecord(
            id: runID,
            queueItemID: request.metadata["queue_item_id"],
            kind: request.kind,
            source: source,
            status: .running,
            startedAt: startedAt,
            modelID: model.modelID,
            statelessBatch: true,
            metadata: request.metadata
        )
        try store.save(backgroundRun: run)

        log("Starting background AI run: job=\(request.jobID) kind=\(request.kind) model=\(model.modelID)")
        log("Prompt length: \(request.prompt.count) chars, tools: \(request.availableTools.map(\.name).joined(separator: ", "))")

        var messages: [MemoryOSBackgroundLoopMessage] = [
            MemoryOSBackgroundLoopMessage(role: .user, content: request.prompt)
        ]
        try persist(messages: messages, runID: runID)

        var mergedMetadata = request.metadata
        var sequence = messages.count
        var toolCallCount = 0

        do {
            for iteration in 1...configuration.maxToolIterations {
                if Int(now().timeIntervalSince(startedAt)) > configuration.maxRunDurationSeconds {
                    throw MemoryOSHeadlessKnowledgeLoopError.exceededMaxRunDuration(configuration.maxRunDurationSeconds)
                }
                log("--- Iteration \(iteration) ---")
                log("Sending \(messages.count) messages to model...")
                let response = try model.complete(MemoryOSBackgroundLoopModelRequest(runID: runID, job: request, messages: messages, availableTools: request.availableTools))
                mergedMetadata.merge(response.metadata) { _, new in new }
                let calls = Array(response.toolCalls.prefix(configuration.maxToolCallsPerIteration))

                if !response.assistantText.isEmpty || !calls.isEmpty {
                    let joinedToolNames = calls.map(\.name).joined(separator: ",")
                    let truncatedToolName = String(joinedToolNames.prefix(64))
                    let memoryOSToolCalls: [MemoryOSBackgroundToolCall]? = calls.isEmpty ? nil : calls.map { MemoryOSBackgroundToolCall(id: $0.id, name: $0.name, argumentsJSON: $0.argumentsJSON) }
                    let assistantMessage = MemoryOSBackgroundLoopMessage(role: .assistant, content: response.assistantText, toolName: truncatedToolName, toolCalls: memoryOSToolCalls)
                    messages.append(assistantMessage)
                    try store.save(backgroundMessage: MemoryOSBackgroundMessageRecord(id: assistantMessage.id, runID: runID, sequence: sequence, role: assistantMessage.role, content: assistantMessage.content, toolName: assistantMessage.toolName, metadata: ["iteration": String(iteration)]))
                    sequence += 1
                    if !response.assistantText.isEmpty {
                        log("Assistant response (\(response.assistantText.count) chars):")
                        log(capped(response.assistantText))
                    }
                }

                if let artifact = response.finalArtifactJSON {
                    log("\n✅ Final artifact received (\(artifact.count) chars)")
                    run.status = .succeeded
                    run.finishedAt = now()
                    run.iterationCount = iteration
                    run.toolCallCount = toolCallCount
                    run.metadata = mergedMetadata
                    try store.save(backgroundRun: run)
                    return MemoryOSBackgroundModelResponse(rawArtifactJSON: artifact, metadata: mergedMetadata.merging([
                        "background_run_id": runID,
                        "tool_trace_count": String(toolCallCount),
                        "stateless_batch": "true"
                    ]) { _, new in new })
                }

                if calls.isEmpty {
                    // LLM returned text with no tool calls. If it previously executed
                    // tool calls successfully, treat this as a natural-language summary
                    // of completed work — not an error.
                    if toolCallCount > 0 {
                        log("\n✅ LLM completed work with \(toolCallCount) tool calls, returning text summary.")
                        run.status = .succeeded
                        run.finishedAt = now()
                        run.iterationCount = iteration
                        run.toolCallCount = toolCallCount
                        run.metadata = mergedMetadata
                        try store.save(backgroundRun: run)
                        return MemoryOSBackgroundModelResponse(rawArtifactJSON: "{}", metadata: mergedMetadata.merging([
                            "background_run_id": runID,
                            "tool_trace_count": String(toolCallCount),
                            "stateless_batch": "true"
                        ]) { _, new in new })
                    }
                    throw MemoryOSHeadlessKnowledgeLoopError.missingFinalArtifact
                }
                log("Tool calls: \(calls.map(\.name).joined(separator: ", "))")
                for call in calls {
                    let toolStartedAt = now()
                    toolCallCount += 1
                    do {
                        log("  → \(call.name)(\(truncateJSON(call.argumentsJSON, max: 200)))")
                        let result = try toolExecutor.execute(call, context: MemoryOSBackgroundToolExecutionContext(runID: runID, iteration: iteration))
                        let resultJSON = capped(result.contentJSON)
                        try store.save(backgroundToolCall: MemoryOSBackgroundToolCallRecord(id: call.id, runID: runID, iteration: iteration, toolName: call.name, argumentsJSON: call.argumentsJSON, resultJSON: resultJSON, status: .succeeded, startedAt: toolStartedAt, finishedAt: now(), metadata: ["citations": result.citations.joined(separator: ",")]))
                        let toolContent = result.contentText.isEmpty ? resultJSON : "\(result.contentText)\n\(resultJSON)"
                        let toolMessage = MemoryOSBackgroundLoopMessage(role: .tool, content: capped(toolContent), toolCallID: call.id, toolName: call.name)
                        messages.append(toolMessage)
                        try store.save(backgroundMessage: MemoryOSBackgroundMessageRecord(id: toolMessage.id, runID: runID, sequence: sequence, role: toolMessage.role, content: toolMessage.content, toolCallID: call.id, toolName: call.name, metadata: ["iteration": String(iteration)]))
                        sequence += 1
                        log("  ← Result: \(result.contentText.prefix(200))")
                    } catch {
                        log("  ✗ Tool error: \(error)")
                        try store.save(backgroundToolCall: MemoryOSBackgroundToolCallRecord(id: call.id, runID: runID, iteration: iteration, toolName: call.name, argumentsJSON: call.argumentsJSON, status: .failed, startedAt: toolStartedAt, finishedAt: now(), errorMessage: String(describing: error)))
                        throw error
                    }
                }
            }
            throw MemoryOSHeadlessKnowledgeLoopError.exceededMaxIterations(configuration.maxToolIterations)
        } catch {
            run.status = .failed
            run.finishedAt = now()
            run.toolCallCount = toolCallCount
            run.errorCode = "memory_os_headless_loop_failed"
            run.errorMessage = String(describing: error)
            run.metadata = mergedMetadata
            try store.save(backgroundRun: run)
            throw error
        }
    }

    private func persist(messages: [MemoryOSBackgroundLoopMessage], runID: String) throws {
        for (index, message) in messages.enumerated() {
            try store.save(backgroundMessage: MemoryOSBackgroundMessageRecord(id: message.id, runID: runID, sequence: index, role: message.role, content: message.content, toolCallID: message.toolCallID, toolName: message.toolName, metadata: ["scope": "initial_stateless_batch"] ))
        }
    }

    private func capped(_ value: String) -> String {
        if value.count <= configuration.maxToolResultBytes { return value }
        let index = value.index(value.startIndex, offsetBy: configuration.maxToolResultBytes)
        return String(value[..<index])
    }

    private func log(_ message: String) {
        logHandler?(message)
    }

    private func truncateJSON(_ json: String, max: Int) -> String {
        guard json.count > max else { return json }
        return String(json.prefix(max)) + "..."
    }
}
