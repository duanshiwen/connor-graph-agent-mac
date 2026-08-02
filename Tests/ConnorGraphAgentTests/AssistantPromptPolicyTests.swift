import Testing
@testable import ConnorGraphAgent

@Test func stableAssistantPromptIsCompactAndContainsRuntimeBoundaries() {
    let prompt = AssistantPromptPolicy.stableInstruction

    #expect(AgentPromptBudgetEstimator().estimate(prompt).estimatedTokenCount < 3_000)
    #expect(prompt.contains("assistant_tool_search"))
    #expect(prompt.contains("discovers schemas only"))
    #expect(prompt.contains("user's language"))
    #expect(prompt.contains("Do not rediscover or reread those sources solely for that check"))
    #expect(prompt.contains("Policy Engine is authoritative"))
    #expect(prompt.contains("Runtime deterministically loads bounded recent memory"))
    #expect(!prompt.contains("prepare_final_output"))
    #expect(!prompt.contains("memory_query"))
}
