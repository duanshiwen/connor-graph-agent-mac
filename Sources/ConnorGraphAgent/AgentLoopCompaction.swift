import Foundation

public struct AgentLoopCompactionConfiguration: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var checkpointRatio: Double
    public var compactionRatio: Double
    public var emergencyRatio: Double
    public var targetRatio: Double
    public var minimumTokenGrowth: Int
    public var retainedRecentToolResults: Int

    public init(
        isEnabled: Bool = true,
        checkpointRatio: Double = 0.70,
        compactionRatio: Double = 0.80,
        emergencyRatio: Double = 0.90,
        targetRatio: Double = 0.45,
        minimumTokenGrowth: Int = 20_000,
        retainedRecentToolResults: Int = 2
    ) {
        self.isEnabled = isEnabled
        self.checkpointRatio = Self.clamped(checkpointRatio)
        self.compactionRatio = max(self.checkpointRatio, Self.clamped(compactionRatio))
        self.emergencyRatio = max(self.compactionRatio, Self.clamped(emergencyRatio))
        self.targetRatio = min(self.checkpointRatio, Self.clamped(targetRatio))
        self.minimumTokenGrowth = max(0, minimumTokenGrowth)
        self.retainedRecentToolResults = max(0, retainedRecentToolResults)
    }

    private static func clamped(_ ratio: Double) -> Double {
        min(max(ratio, 0.05), 1.0)
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
        messages: [AgentModelMessage]
    ) -> AgentRunCheckpoint {
        var calls: [String: AgentToolCall] = [:]
        for call in messages.flatMap({ $0.toolCalls ?? [] }) {
            calls[call.id] = call
        }
        var remainingCharacters = maximumCheckpointCharacters
        var completed: [AgentRunCheckpointTool] = []
        for message in messages where message.role == .tool {
            guard remainingCharacters > 0 else { break }
            let callID = message.toolCallID ?? "unknown"
            let call = calls[callID]
            let name = message.name ?? call?.name ?? "tool"
            let arguments = bounded(call?.argumentsJSON ?? "{}", limit: maximumFieldCharacters)
            let excerpt = bounded(message.content, limit: min(maximumFieldCharacters, remainingCharacters))
            completed.append(AgentRunCheckpointTool(
                callID: callID,
                name: name,
                arguments: arguments,
                resultExcerpt: excerpt,
                resultCharacterCount: message.content.count
            ))
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
