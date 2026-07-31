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

@Test func contextCompactorKeepsRecentToolResultsAndReplacesPriorCheckpoint() {
    let oldCheckpoint = AgentModelMessage(
        role: .system,
        content: "[AGENT RUN CHECKPOINT - TRUSTED RUNTIME STATE]\nGeneration: 1"
    )
    let messages = [
        AgentModelMessage(role: .system, content: "system"),
        oldCheckpoint,
        AgentModelMessage(role: .user, content: "historical user message"),
        AgentModelMessage(role: .assistant, content: "historical final response"),
        AgentModelMessage(role: .assistant, content: "", toolCalls: [
            AgentToolCall(id: "call-1", name: "read_file", argumentsJSON: #"{"path":"one"}"#)
        ]),
        AgentModelMessage(role: .tool, content: String(repeating: "old", count: 2_000), toolCallID: "call-1", name: "read_file"),
        AgentModelMessage(role: .assistant, content: "", toolCalls: [
            AgentToolCall(id: "call-2", name: "read_file", argumentsJSON: #"{"path":"two"}"#)
        ]),
        AgentModelMessage(role: .tool, content: "recent result", toolCallID: "call-2", name: "read_file")
    ]
    let checkpoint = AgentRunCheckpointBuilder().build(
        generation: 2,
        originalGoal: "Read two files",
        currentPhase: "taskExecution",
        iteration: 3,
        messages: messages
    )

    let result = AgentLoopContextCompactor().compact(
        AgentModelRequest(messages: messages),
        checkpoint: checkpoint,
        retainedRecentToolResults: 1
    )

    #expect(result.compactedToolResultCount == 1)
    #expect(result.request.messages.filter {
        $0.role == .system && $0.content.hasPrefix("[AGENT RUN CHECKPOINT - TRUSTED RUNTIME STATE]")
    }.count == 1)
    #expect(result.request.messages.first { $0.toolCallID == "call-1" }?.content.hasPrefix("[Compacted tool result:") == true)
    #expect(result.request.messages.first { $0.toolCallID == "call-2" }?.content == "recent result")
    #expect(result.request.messages.contains { $0.role == .user && $0.content == "historical user message" })
    #expect(result.request.messages.contains { $0.role == .assistant && $0.content == "historical final response" })
    let assistantCallIDs = Set(result.request.messages.flatMap { $0.toolCalls?.map(\.id) ?? [] })
    let toolResultIDs = Set(result.request.messages.compactMap(\.toolCallID))
    #expect(toolResultIDs.isSubset(of: assistantCallIDs))
}
