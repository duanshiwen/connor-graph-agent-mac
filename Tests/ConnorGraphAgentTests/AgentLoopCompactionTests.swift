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

@Test func contextCompactorKeepsRecentToolResultsAndReplacesPriorCheckpoint() throws {
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

    let result = try AgentLoopContextCompactor().compact(
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

@Test func currentRunToolFittingDoesNotTrimHistoricalConversation() throws {
    let historicalUser = AgentModelMessage(role: .user, content: String(repeating: "historical user ", count: 200))
    let historicalAssistant = AgentModelMessage(role: .assistant, content: String(repeating: "historical answer ", count: 200))
    let request = AgentModelRequest(messages: [
        AgentModelMessage(role: .system, content: "system"),
        historicalUser,
        historicalAssistant,
        AgentModelMessage(role: .assistant, content: "", toolCalls: [
            AgentToolCall(id: "call-large", name: "read_file", argumentsJSON: "{}")
        ]),
        AgentModelMessage(role: .tool, content: String(repeating: "tool payload ", count: 5_000), toolCallID: "call-large", name: "read_file")
    ])

    let fitted = AgentLoopContextCompactor().fitCurrentRunToolResults(
        in: request,
        maximumEstimatedTokens: 3_000,
        maximumResultBytes: 1_000_000
    )

    #expect(fitted.messages.contains(historicalUser))
    #expect(fitted.messages.contains(historicalAssistant))
    #expect(fitted.messages.first { $0.toolCallID == "call-large" }?.content.count ?? .max < request.messages.last?.content.count ?? 0)
}

@Test func currentRunToolFittingLeavesCheckpointPlaceholdersUntouched() throws {
    let placeholder = "[Compacted tool result: name=read_file, callID=call-old, originalCharacters=9000; see checkpoint generation 1.]"
    let request = AgentModelRequest(messages: [
        AgentModelMessage(role: .system, content: "system"),
        AgentModelMessage(role: .user, content: "goal"),
        AgentModelMessage(role: .assistant, content: "", toolCalls: [
            AgentToolCall(id: "call-old", name: "read_file", argumentsJSON: "{}")
        ]),
        AgentModelMessage(role: .tool, content: placeholder, toolCallID: "call-old", name: "read_file"),
        AgentModelMessage(role: .assistant, content: "", toolCalls: [
            AgentToolCall(id: "call-recent", name: "read_file", argumentsJSON: "{}")
        ]),
        AgentModelMessage(role: .tool, content: String(repeating: "recent payload ", count: 5_000), toolCallID: "call-recent", name: "read_file")
    ])

    let fitted = AgentLoopContextCompactor().fitCurrentRunToolResults(
        in: request,
        maximumEstimatedTokens: 2_000,
        maximumResultBytes: 1_000_000
    )

    // The already-compacted placeholder must not be re-touched or shrunk.
    #expect(fitted.messages.first { $0.toolCallID == "call-old" }?.content == placeholder)
    // The live recent result absorbs the shrink instead.
    let recent = fitted.messages.first { $0.toolCallID == "call-recent" }?.content ?? ""
    #expect(recent.count < request.messages.last?.content.count ?? 0)
}


@Test func largeRecentToolResultIsCompactedBySizeEvenWhenRecent() throws {
    let messages = [
        AgentModelMessage(role: .user, content: "historical user message"),
        AgentModelMessage(role: .assistant, content: "historical final response"),
        AgentModelMessage(role: .assistant, content: "", toolCalls: [
            AgentToolCall(id: "call-large", name: "read_file", argumentsJSON: "{}")
        ]),
        AgentModelMessage(role: .tool, content: String(repeating: "big payload ", count: 2_000), toolCallID: "call-large", name: "read_file"),
        AgentModelMessage(role: .assistant, content: "", toolCalls: [
            AgentToolCall(id: "call-small", name: "read_status", argumentsJSON: "{}")
        ]),
        AgentModelMessage(role: .tool, content: "small result", toolCallID: "call-small", name: "read_status")
    ]
    let checkpoint = AgentRunCheckpointBuilder().build(
        generation: 2,
        originalGoal: "Read two files",
        currentPhase: "taskExecution",
        iteration: 3,
        messages: messages
    )

    let result = try AgentLoopContextCompactor().compact(
        AgentModelRequest(messages: messages),
        checkpoint: checkpoint,
        retainedRecentToolResults: 2,
        largeResultByteThreshold: 1_024
    )

    // 超大结果即使是最新一条也被压掉；小结果仍按“最近 N 条”保留。
    #expect(result.compactedToolResultCount == 1)
    #expect(result.request.messages.first { $0.toolCallID == "call-large" }?.content.hasPrefix("[Compacted tool result:") == true)
    #expect(result.request.messages.first { $0.toolCallID == "call-small" }?.content == "small result")
}

@Test func resolvedPromptLimitDerivesFromModelWindowAndRespectsExplicitOverride() {
    // 当前默认 128_000 是显式值（此前已上调避免回复被提前收敛）：直接原样生效，不做窗口推导。
    let automatic = AgentLoopConfiguration()
    #expect(automatic.resolvedPromptMaxEstimatedTokens(modelWindowTokens: 1_000_000) == 128_000)
    #expect(automatic.resolvedPromptMaxEstimatedTokens(modelWindowTokens: 200_000) == 128_000)

    // 显式配置 64_000（自动哨兵）时按模型窗口推导：1M → min(1M×0.8, 512k) = 512k；200k → 160k。
    let auto = AgentLoopConfiguration(promptMaxEstimatedTokens: AgentLoopConfiguration.autoPromptLimitDefault)
    #expect(auto.resolvedPromptMaxEstimatedTokens(modelWindowTokens: 1_000_000) == 512_000)
    #expect(auto.resolvedPromptMaxEstimatedTokens(modelWindowTokens: 200_000) == 160_000)

    // 其他显式配置原样生效。
    let explicit = AgentLoopConfiguration(promptMaxEstimatedTokens: 100_000)
    #expect(explicit.resolvedPromptMaxEstimatedTokens(modelWindowTokens: 1_000_000) == 100_000)
}

@Test func compactionConfigDecodesLegacyJSONWithoutNewKey() throws {
    // 老版本持久化设置没有 largeResultByteThreshold，必须能解出来并落到默认值。
    let legacy = #"{"isEnabled":true,"checkpointRatio":0.7,"compactionRatio":0.8,"emergencyRatio":0.9,"targetRatio":0.45,"minimumTokenGrowth":20000,"retainedRecentToolResults":2}"#
    let decoded = try JSONDecoder().decode(AgentLoopCompactionConfiguration.self, from: Data(legacy.utf8))
    #expect(decoded.largeResultByteThreshold == 8 * 1_024)
    #expect(decoded.retainedRecentToolResults == 2)

    // 空对象也应解码为全默认值。
    let empty = try JSONDecoder().decode(AgentLoopCompactionConfiguration.self, from: Data("{}".utf8))
    #expect(empty.isEnabled)
    #expect(empty.checkpointRatio == 0.70)
    #expect(empty.largeResultByteThreshold == 8 * 1_024)

    // 新值应能编码后再解回。
    let configured = AgentLoopCompactionConfiguration(largeResultByteThreshold: 16 * 1_024)
    let roundTripped = try JSONDecoder().decode(
        AgentLoopCompactionConfiguration.self,
        from: JSONEncoder().encode(configured)
    )
    #expect(roundTripped.largeResultByteThreshold == 16 * 1_024)
}
