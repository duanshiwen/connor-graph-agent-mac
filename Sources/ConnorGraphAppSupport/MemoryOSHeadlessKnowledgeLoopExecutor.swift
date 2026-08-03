import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct MemoryOSBackgroundToolLoopConfiguration: Codable, Sendable, Equatable {
    public var maxToolIterations: Int
    public var maxToolCallsPerIteration: Int
    public var maxRunDurationSeconds: Int
    public var maxToolResultBytes: Int
    public var maxTotalTokens: Int
    public var retainedDetailedMessageCount: Int

    public init(
        maxToolIterations: Int = 24,
        maxToolCallsPerIteration: Int = 8,
        maxRunDurationSeconds: Int = 1800,
        maxToolResultBytes: Int = 16 * 1024,
        maxTotalTokens: Int = 300_000,
        retainedDetailedMessageCount: Int = 8
    ) {
        self.maxToolIterations = maxToolIterations
        self.maxToolCallsPerIteration = maxToolCallsPerIteration
        self.maxRunDurationSeconds = maxRunDurationSeconds
        self.maxToolResultBytes = maxToolResultBytes
        self.maxTotalTokens = max(1, maxTotalTokens)
        self.retainedDetailedMessageCount = max(2, retainedDetailedMessageCount)
    }

    private enum CodingKeys: String, CodingKey {
        case maxToolIterations
        case maxToolCallsPerIteration
        case maxRunDurationSeconds
        case maxToolResultBytes
        case maxTotalTokens
        case retainedDetailedMessageCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxToolIterations: try container.decodeIfPresent(Int.self, forKey: .maxToolIterations) ?? 24,
            maxToolCallsPerIteration: try container.decodeIfPresent(Int.self, forKey: .maxToolCallsPerIteration) ?? 8,
            maxRunDurationSeconds: try container.decodeIfPresent(Int.self, forKey: .maxRunDurationSeconds) ?? 1_800,
            maxToolResultBytes: try container.decodeIfPresent(Int.self, forKey: .maxToolResultBytes) ?? 16 * 1_024,
            maxTotalTokens: try container.decodeIfPresent(Int.self, forKey: .maxTotalTokens) ?? 300_000,
            retainedDetailedMessageCount: try container.decodeIfPresent(Int.self, forKey: .retainedDetailedMessageCount) ?? 8
        )
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
    public var metadata: [String: String]

    public init(assistantText: String = "", toolCalls: [MemoryOSBackgroundToolCall] = [], metadata: [String: String] = [:]) {
        self.assistantText = assistantText
        self.toolCalls = toolCalls
        self.metadata = metadata
    }
}

public protocol MemoryOSBackgroundToolLoopModel: Sendable {
    var modelID: String { get }
    func complete(_ request: MemoryOSBackgroundLoopModelRequest) async throws -> MemoryOSBackgroundLoopModelResponse
}

public enum MemoryOSHeadlessKnowledgeLoopError: Error, Sendable, Equatable, CustomStringConvertible {
    case exceededMaxIterations(Int)
    case exceededMaxRunDuration(Int)
    case exceededTokenBudget(Int)

    public var description: String {
        switch self {
        case .exceededMaxIterations(let value): "exceededMaxIterations: \(value)"
        case .exceededMaxRunDuration(let value): "exceededMaxRunDuration: \(value)"
        case .exceededTokenBudget(let value): "exceededTokenBudget: \(value)"
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

    public func execute(_ request: MemoryOSBackgroundModelRequest) async throws -> MemoryOSBackgroundModelResponse {
        let startedAt = now()
        let runID = request.metadata["background_run_id"] ?? UUID().uuidString
        let source: String
        if MemoryOSBackgroundJobKind.isL1KnowledgeKind(request.kind) {
            source = "l1_capture_events"
        } else {
            source = "l2_statements"
        }
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
        var totalTokens = 0

        do {
            for iteration in 1...configuration.maxToolIterations {
                if Int(now().timeIntervalSince(startedAt)) > configuration.maxRunDurationSeconds {
                    throw MemoryOSHeadlessKnowledgeLoopError.exceededMaxRunDuration(configuration.maxRunDurationSeconds)
                }
                log("--- Iteration \(iteration) ---")
                log("Sending \(messages.count) messages to model...")
                let response = try await model.complete(MemoryOSBackgroundLoopModelRequest(runID: runID, job: request, messages: messages, availableTools: request.availableTools))
                totalTokens += Int(response.metadata["total_tokens"] ?? "0") ?? 0
                mergedMetadata.merge(response.metadata) { _, new in new }
                let calls = Array(response.toolCalls.prefix(configuration.maxToolCallsPerIteration))

                if calls.isEmpty {
                    if !response.assistantText.isEmpty {
                        log("Final artifact (\(response.assistantText.count) chars):")
                        log(capped(response.assistantText))
                    }
                    log("\n✅ LLM completed (\(toolCallCount) tool calls total).")
                    run.status = .succeeded
                    run.finishedAt = now()
                    run.iterationCount = iteration
                    run.toolCallCount = toolCallCount
                    run.metadata = mergedMetadata
                    try store.save(backgroundRun: run)
                    return MemoryOSBackgroundModelResponse(rawArtifactJSON: response.assistantText.isEmpty ? "{}" : response.assistantText, metadata: mergedMetadata.merging([
                        "background_run_id": runID,
                        "tool_trace_count": String(toolCallCount),
                        "stateless_batch": "true"
                    ]) { _, new in new })
                }
                if totalTokens >= configuration.maxTotalTokens {
                    throw MemoryOSHeadlessKnowledgeLoopError.exceededTokenBudget(configuration.maxTotalTokens)
                }

                let joinedToolNames = calls.map(\.name).joined(separator: ",")
                let truncatedToolName = String(joinedToolNames.prefix(64))
                let memoryOSToolCalls: [MemoryOSBackgroundToolCall] = calls.map { MemoryOSBackgroundToolCall(id: $0.id, name: $0.name, argumentsJSON: $0.argumentsJSON) }
                let assistantMessage = MemoryOSBackgroundLoopMessage(role: .assistant, content: response.assistantText, toolName: truncatedToolName, toolCalls: memoryOSToolCalls)
                messages.append(assistantMessage)
                try store.save(backgroundMessage: MemoryOSBackgroundMessageRecord(id: assistantMessage.id, runID: runID, sequence: sequence, role: assistantMessage.role, content: assistantMessage.content, toolName: assistantMessage.toolName, metadata: ["iteration": String(iteration)]))
                sequence += 1
                if !response.assistantText.isEmpty {
                    log("Assistant response (\(response.assistantText.count) chars):")
                    log(capped(response.assistantText))
                }
                log("Tool calls: \(calls.map(\.name).joined(separator: ", "))")
                for call in calls {
                    let toolStartedAt = now()
                    toolCallCount += 1
                    do {
                        log("  → \(call.name)(\(truncateJSON(call.argumentsJSON, max: 200)))")
                        let replayedResult = try replayableToolResult(for: call, runID: runID)
                        let result = try replayedResult ?? toolExecutor.execute(call, context: MemoryOSBackgroundToolExecutionContext(runID: runID, iteration: iteration))
                        let resultJSON = capped(result.contentJSON)
                        try store.save(backgroundToolCall: MemoryOSBackgroundToolCallRecord(id: call.id, runID: runID, iteration: iteration, toolName: call.name, argumentsJSON: call.argumentsJSON, resultJSON: resultJSON, status: result.error == nil ? .succeeded : .failed, startedAt: toolStartedAt, finishedAt: now(), errorMessage: result.error, metadata: [
                            "citations": result.citations.joined(separator: ","),
                            "content_text": capped(result.contentText),
                            "idempotent_replay": String(replayedResult != nil)
                        ]))
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
                messages = compactedHistory(messages)
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

    private func replayableToolResult(for call: MemoryOSBackgroundToolCall, runID: String) throws -> MemoryOSBackgroundToolResult? {
        let writeTools: Set<String> = [
            "memory_os_l2_update_entities",
            "memory_os_update_current_user_profile",
            "memory_os_l3_update_beliefs",
            "memory_os_l4_update_entities"
        ]
        guard writeTools.contains(call.name) else { return nil }
        let arguments = try toolExecutor.normalizedArgumentsJSON(for: call)
        let previous = try store.backgroundToolCalls(runID: runID).reversed().first { candidate in
            guard candidate.status == .succeeded,
                  candidate.toolName == call.name,
                  candidate.resultJSON != nil
            else { return false }
            let previousCall = MemoryOSBackgroundToolCall(
                id: candidate.id,
                name: candidate.toolName,
                argumentsJSON: candidate.argumentsJSON
            )
            return (try? toolExecutor.normalizedArgumentsJSON(for: previousCall)) == arguments
        }
        guard let previous else { return nil }
        let citations = previous.metadata["citations"]?
            .split(separator: ",")
            .map(String.init) ?? []
        return MemoryOSBackgroundToolResult(
            callID: call.id,
            name: call.name,
            contentJSON: previous.resultJSON ?? "{}",
            contentText: previous.metadata["content_text"] ?? "Reused the successful result from an earlier attempt of this background job.",
            citations: citations
        )
    }

    private func capped(_ value: String) -> String {
        if value.count <= configuration.maxToolResultBytes { return value }
        let index = value.index(value.startIndex, offsetBy: configuration.maxToolResultBytes)
        return String(value[..<index])
    }

    private func compactedHistory(_ messages: [MemoryOSBackgroundLoopMessage]) -> [MemoryOSBackgroundLoopMessage] {
        let retained = configuration.retainedDetailedMessageCount
        guard messages.count > retained + 1 else { return messages }
        let detailedStart = messages.count - retained
        return messages.enumerated().map { index, message in
            guard index > 0, index < detailedStart else { return message }
            var compacted = message
            switch message.role {
            case .tool:
                compacted.content = "Earlier successful tool result omitted from detailed context: \(message.toolName ?? "tool")."
            case .assistant:
                compacted.content = String(message.content.prefix(256))
                compacted.toolCalls = message.toolCalls?.map {
                    MemoryOSBackgroundToolCall(id: $0.id, name: $0.name, argumentsJSON: "{}")
                }
            case .system, .user:
                break
            }
            return compacted
        }
    }

    private func log(_ message: String) {
        logHandler?(message)
    }

    private func truncateJSON(_ json: String, max: Int) -> String {
        guard json.count > max else { return json }
        return String(json.prefix(max)) + "..."
    }
}
