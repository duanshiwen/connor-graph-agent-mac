import Foundation
import Testing
@testable import ConnorGraphAgent

@Test func compactionPolicyUsesEarlyWatermarksAndHysteresis() {
    let policy = AgentLoopCompactionPolicy(configuration: .init(
        checkpointRatio: 0.70,
        compactionRatio: 0.80,
        emergencyRatio: 0.90,
        targetRatio: 0.45,
        minimumTokenGrowth: 20_000
    ))

    #expect(policy.decision(for: .init(
        estimatedInputTokens: 69_000,
        maximumInputTokens: 100_000,
        tokensAddedSinceLastCompaction: 100_000
    ), hasCheckpointForCurrentPressure: false) == .none)
    #expect(policy.decision(for: .init(
        estimatedInputTokens: 72_000,
        maximumInputTokens: 100_000,
        tokensAddedSinceLastCompaction: 10_000
    ), hasCheckpointForCurrentPressure: false) == .checkpoint)
    #expect(policy.decision(for: .init(
        estimatedInputTokens: 82_000,
        maximumInputTokens: 100_000,
        tokensAddedSinceLastCompaction: 19_999
    ), hasCheckpointForCurrentPressure: true) == .none)
    #expect(policy.decision(for: .init(
        estimatedInputTokens: 82_000,
        maximumInputTokens: 100_000,
        tokensAddedSinceLastCompaction: 20_000
    ), hasCheckpointForCurrentPressure: true) == .compact)
    #expect(policy.decision(for: .init(
        estimatedInputTokens: 91_000,
        maximumInputTokens: 100_000,
        tokensAddedSinceLastCompaction: 1
    ), hasCheckpointForCurrentPressure: true) == .emergency)
    #expect(policy.targetTokens(maximumInputTokens: 100_000) == 45_000)
}

@Test func runCheckpointPreservesGoalPhaseAndCompletedToolEvidence() {
    let messages = [
        AgentModelMessage(
            role: .assistant,
            content: "",
            toolCalls: [AgentToolCall(id: "call-1", name: "read_file", argumentsJSON: #"{"path":"README.md"}"#)]
        ),
        AgentModelMessage(
            role: .tool,
            content: "README contents",
            toolCallID: "call-1",
            name: "read_file"
        )
    ]

    let checkpoint = AgentRunCheckpointBuilder().build(
        generation: 2,
        originalGoal: "Inspect the repository",
        currentPhase: "taskExecution",
        iteration: 4,
        messages: messages
    )

    #expect(checkpoint.generation == 2)
    #expect(checkpoint.originalGoal == "Inspect the repository")
    #expect(checkpoint.currentPhase == "taskExecution")
    #expect(checkpoint.completedToolCalls.count == 1)
    #expect(checkpoint.completedToolCalls[0].callID == "call-1")
    #expect(checkpoint.completedToolCalls[0].arguments.contains("README.md"))
    #expect(checkpoint.modelContext.contains("do not repeat completed side effects"))
}
