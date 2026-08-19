import Foundation

public struct AgentLoopCompactionConfiguration: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var checkpointRatio: Double
    public var compactionRatio: Double
    public var emergencyRatio: Double
    public var targetRatio: Double
    public var minimumTokenGrowth: Int
    public var retainedRecentToolResults: Int
    /// 工具结果超过该字节数时，即使是“最近 N 条”也一律压成 checkpoint 占位符。
    /// 避免超大结果（例如整页草稿 15k–30k 字符）永远留在上下文里，导致压缩无效。
    public var largeResultByteThreshold: Int

    public init(
        isEnabled: Bool = true,
        checkpointRatio: Double = 0.70,
        compactionRatio: Double = 0.80,
        emergencyRatio: Double = 0.90,
        targetRatio: Double = 0.45,
        minimumTokenGrowth: Int = 15_000,
        retainedRecentToolResults: Int = 2,
        largeResultByteThreshold: Int = 8 * 1_024
    ) {
        self.isEnabled = isEnabled
        self.checkpointRatio = Self.clamped(checkpointRatio)
        self.compactionRatio = max(self.checkpointRatio, Self.clamped(compactionRatio))
        self.emergencyRatio = max(self.compactionRatio, Self.clamped(emergencyRatio))
        self.targetRatio = min(self.checkpointRatio, Self.clamped(targetRatio))
        self.minimumTokenGrowth = max(0, minimumTokenGrowth)
        self.retainedRecentToolResults = max(0, retainedRecentToolResults)
        self.largeResultByteThreshold = max(1, largeResultByteThreshold)
    }

    private static func clamped(_ ratio: Double) -> Double {
        min(max(ratio, 0.05), 1.0)
    }

    /// 容错解码：老版本持久化的设置 JSON 没有 largeResultByteThreshold（以及可能缺其它键）时，
    /// 用默认值补齐，避免整个设置加载失败（此前合成 Codable 要求所有键都存在）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            checkpointRatio: try container.decodeIfPresent(Double.self, forKey: .checkpointRatio) ?? 0.70,
            compactionRatio: try container.decodeIfPresent(Double.self, forKey: .compactionRatio) ?? 0.80,
            emergencyRatio: try container.decodeIfPresent(Double.self, forKey: .emergencyRatio) ?? 0.90,
            targetRatio: try container.decodeIfPresent(Double.self, forKey: .targetRatio) ?? 0.45,
            minimumTokenGrowth: try container.decodeIfPresent(Int.self, forKey: .minimumTokenGrowth) ?? 15_000,
            retainedRecentToolResults: try container.decodeIfPresent(Int.self, forKey: .retainedRecentToolResults) ?? 2,
            largeResultByteThreshold: try container.decodeIfPresent(Int.self, forKey: .largeResultByteThreshold) ?? 8 * 1_024
        )
    }
}

public enum AgentLoopCompactionDecision: String, Sendable, Equatable {
    case none
    case checkpoint
    case compact
    case emergency
}

public struct AgentLoopCompactionSnapshot: Sendable, Equatable {
    public var estimatedInputTokens: Int
    public var maximumInputTokens: Int
    public var tokensAddedSinceLastCompaction: Int

    public init(
        estimatedInputTokens: Int,
        maximumInputTokens: Int,
        tokensAddedSinceLastCompaction: Int
    ) {
        self.estimatedInputTokens = max(0, estimatedInputTokens)
        self.maximumInputTokens = max(1, maximumInputTokens)
        self.tokensAddedSinceLastCompaction = max(0, tokensAddedSinceLastCompaction)
    }

    public var pressureRatio: Double {
        Double(estimatedInputTokens) / Double(maximumInputTokens)
    }
}

public struct AgentLoopCompactionPolicy: Sendable, Equatable {
    public var configuration: AgentLoopCompactionConfiguration

    public init(configuration: AgentLoopCompactionConfiguration = .init()) {
        self.configuration = configuration
    }

    public func decision(for snapshot: AgentLoopCompactionSnapshot, hasCheckpointForCurrentPressure: Bool) -> AgentLoopCompactionDecision {
        guard configuration.isEnabled else { return .none }
        if snapshot.pressureRatio >= configuration.emergencyRatio { return .emergency }
        if snapshot.pressureRatio >= configuration.compactionRatio,
           snapshot.tokensAddedSinceLastCompaction >= configuration.minimumTokenGrowth {
            return .compact
        }
        if snapshot.pressureRatio >= configuration.checkpointRatio, !hasCheckpointForCurrentPressure {
            return .checkpoint
        }
        return .none
    }

    public func targetTokens(maximumInputTokens: Int) -> Int {
        max(1, Int(Double(max(1, maximumInputTokens)) * configuration.targetRatio))
    }
}

public struct AgentRunCheckpointTool: Codable, Sendable, Equatable {
    public var callID: String
    public var name: String
    public var arguments: String
    public var resultExcerpt: String
    public var resultCharacterCount: Int

    public init(callID: String, name: String, arguments: String, resultExcerpt: String, resultCharacterCount: Int) {
        self.callID = callID
        self.name = name
        self.arguments = arguments
        self.resultExcerpt = resultExcerpt
        self.resultCharacterCount = max(0, resultCharacterCount)
    }
}

public struct AgentRunCheckpoint: Codable, Sendable, Equatable {
    public var generation: Int
    public var originalGoal: String
    public var currentPhase: String
    public var iteration: Int
    public var completedToolCalls: [AgentRunCheckpointTool]
    public var nextAction: String
    public var createdAt: Date

    public init(
        generation: Int,
        originalGoal: String,
        currentPhase: String,
        iteration: Int,
        completedToolCalls: [AgentRunCheckpointTool],
        nextAction: String,
        createdAt: Date = Date()
    ) {
        self.generation = max(1, generation)
        self.originalGoal = originalGoal
        self.currentPhase = currentPhase
        self.iteration = max(1, iteration)
        self.completedToolCalls = completedToolCalls
        self.nextAction = nextAction
        self.createdAt = createdAt
    }

    public var modelContext: String {
        var lines = [
            "[AGENT RUN CHECKPOINT - TRUSTED RUNTIME STATE]",
            "Generation: \(generation)",
            "Original goal: \(originalGoal)",
            "Current phase: \(currentPhase)",
            "Completed through iteration: \(iteration)",
            "Next action: \(nextAction)",
            "Completed tool calls:"
        ]
        lines.append(contentsOf: completedToolCalls.map {
            "- \($0.name) [\($0.callID)] args=\($0.arguments) result=\($0.resultExcerpt) [original characters: \($0.resultCharacterCount)]"
        })
        lines.append("Continue the original task from this checkpoint. Historical tool payloads may have been compacted; do not repeat completed side effects unless verification requires it.")
        return lines.joined(separator: "\n")
    }
}

public struct AgentRunCheckpointBuilder: Sendable {
    public var maximumCheckpointCharacters: Int
    public var maximumFieldCharacters: Int

    public init(maximumCheckpointCharacters: Int = 12_000, maximumFieldCharacters: Int = 320) {
        self.maximumCheckpointCharacters = max(1_000, maximumCheckpointCharacters)
        self.maximumFieldCharacters = max(80, maximumFieldCharacters)
    }

    public func build(
        generation: Int,
        originalGoal: String,
        currentPhase: String,
        iteration: Int,
        messages: [AgentModelMessage],
        previousCheckpoint: AgentRunCheckpoint? = nil
    ) -> AgentRunCheckpoint {
        var calls: [String: AgentToolCall] = [:]
        for call in messages.flatMap({ $0.toolCalls ?? [] }) {
            calls[call.id] = call
        }
        var remainingCharacters = maximumCheckpointCharacters
        var completed = previousCheckpoint?.completedToolCalls ?? []
        var completedIndices = Dictionary(uniqueKeysWithValues: completed.enumerated().map { ($0.element.callID, $0.offset) })
        remainingCharacters = max(0, remainingCharacters - completed.reduce(0) {
            $0 + $1.name.count + $1.arguments.count + $1.resultExcerpt.count + 64
        })
        for message in messages where message.role == .tool {
            guard remainingCharacters > 0 else { break }
            let callID = message.toolCallID ?? "unknown"
            let call = calls[callID]
            let name = message.name ?? call?.name ?? "tool"
            let arguments = bounded(call?.argumentsJSON ?? "{}", limit: maximumFieldCharacters)
            let excerpt = bounded(message.content, limit: min(maximumFieldCharacters, remainingCharacters))
            let item = AgentRunCheckpointTool(
                callID: callID,
                name: name,
                arguments: arguments,
                resultExcerpt: excerpt,
                resultCharacterCount: message.content.count
            )
            if let existingIndex = completedIndices[callID] {
                if !message.content.hasPrefix("[Compacted tool result:") {
                    completed[existingIndex] = item
                }
            } else {
                completedIndices[callID] = completed.count
                completed.append(item)
            }
            remainingCharacters -= name.count + arguments.count + excerpt.count + 64
        }
        return AgentRunCheckpoint(
            generation: generation,
            originalGoal: bounded(originalGoal, limit: 2_000),
            currentPhase: currentPhase,
            iteration: iteration,
            completedToolCalls: completed,
            nextAction: "Resume from the current phase using the retained recent trace."
        )
    }

    private func bounded(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let headCount = max(1, limit * 2 / 3)
        let tailCount = max(1, limit - headCount - 1)
        return String(value.prefix(headCount)) + "…" + String(value.suffix(tailCount))
    }
}

public struct AgentLoopCompactionResult: Sendable, Equatable {
    public var request: AgentModelRequest
    public var compactedToolResultCount: Int

    public init(request: AgentModelRequest, compactedToolResultCount: Int) {
        self.request = request
        self.compactedToolResultCount = compactedToolResultCount
    }
}

public struct AgentLoopContextCompactor: Sendable {
    public init() {}

    public func compact(
        _ request: AgentModelRequest,
        checkpoint: AgentRunCheckpoint,
        retainedRecentToolResults: Int,
        largeResultByteThreshold: Int = 8 * 1_024
    ) throws -> AgentLoopCompactionResult {
        var compacted = request
        compacted.messages.removeAll {
            $0.role == .system && $0.content.hasPrefix("[AGENT RUN CHECKPOINT - TRUSTED RUNTIME STATE]")
        }

        let checkpointIndex = min(1, compacted.messages.count)
        compacted.messages.insert(
            AgentModelMessage(role: .system, content: checkpoint.modelContext),
            at: checkpointIndex
        )

        // 按“大小 + 新旧”双条件决定保留：最近 N 条里只有小结果原样保留；
        // 任何超过阈值的超大结果（整页草稿、大文件读取等）一律压成 checkpoint 占位符，
        // 否则它们会永远留在“最近结果”窗口里，压缩形同虚设。
        let toolIndices = compacted.messages.indices.filter { compacted.messages[$0].role == .tool }
        let retainedCount = max(0, retainedRecentToolResults)
        var compactCount = 0
        for (offset, index) in toolIndices.enumerated() {
            let isRecent = offset >= toolIndices.count - retainedCount
            let message = compacted.messages[index]
            let isLarge = message.content.utf8.count >= largeResultByteThreshold
            if isRecent && !isLarge { continue }
            compacted.messages[index].content = "\(Self.compactedToolResultPrefix) name=\(message.name ?? "tool"), callID=\(message.toolCallID ?? "unknown"), originalCharacters=\(message.content.count); see checkpoint generation \(checkpoint.generation).]"
            compacted.messages[index].contentParts = nil
            compacted.messages[index].providerMetadata = nil
            compactCount += 1
        }
        return AgentLoopCompactionResult(request: compacted, compactedToolResultCount: compactCount)
    }

    /// Marker prefix used by ``compact(_:checkpoint:retainedRecentToolResults:)`` when it
    /// replaces an older tool result with a reference back to the run checkpoint.
    static let compactedToolResultPrefix = "[Compacted tool result:"

    /// Best-effort second-stage reduction used when a checkpoint compaction is still above the
    /// target. It only shrinks the *live* (non-placeholder) tool-result bodies of the current run,
    /// distributing the remaining token budget across them by demand. It never trims persisted
    /// conversation history and never re-touches results that were already reduced to a checkpoint
    /// reference, so previously compacted tokens stay stable (cache-friendly) and the retained
    /// recent results absorb the shrink first.
    public func fitCurrentRunToolResults(
        in request: AgentModelRequest,
        maximumEstimatedTokens: Int,
        maximumResultBytes: Int,
        contextGuard: AgentModelContextGuard = .init()
    ) -> AgentModelRequest {
        var fitted = request
        let liveToolIndices = fitted.messages.indices.filter {
            fitted.messages[$0].role == .tool
                && !fitted.messages[$0].content.hasPrefix(Self.compactedToolResultPrefix)
        }
        guard !liveToolIndices.isEmpty else { return fitted }

        // Treat everything except the live tool bodies (including already-compacted placeholders)
        // as fixed, so the remaining budget is reserved for the results we are allowed to shrink.
        var requestWithoutLiveToolBodies = fitted
        for index in liveToolIndices {
            requestWithoutLiveToolBodies.messages[index].content = ""
        }
        let fixedTokens = contextGuard.estimatedInputTokens(requestWithoutLiveToolBodies)
        let availableToolTokens = max(0, maximumEstimatedTokens - fixedTokens)
        let demands = liveToolIndices.map {
            contextGuard.estimator.estimate(fitted.messages[$0].content).estimatedTokenCount
        }
        let totalDemand = max(1, demands.reduce(0, +))
        let gate = AgentToolResultGate(configuration: .init(maxResultCharacters: maximumResultBytes))
        for (offset, index) in liveToolIndices.enumerated() {
            let message = fitted.messages[index]
            let allocatedTokens = Int(Double(availableToolTokens) * Double(demands[offset]) / Double(totalDemand))
            fitted.messages[index].content = gate.gatedContent(
                for: AgentToolResult(
                    toolCallID: message.toolCallID ?? "compaction",
                    toolName: message.name ?? "tool",
                    contentText: message.content
                ),
                maximumEstimatedTokens: allocatedTokens,
                estimator: contextGuard.estimator
            )
        }
        return fitted
    }
}
