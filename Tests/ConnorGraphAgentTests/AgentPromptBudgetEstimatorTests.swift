import Testing
import ConnorGraphAgent

@Test func agentPromptBudgetEstimatorReturnsZeroForEmptyPrompt() {
    let estimate = AgentPromptBudgetEstimator().estimate("")

    #expect(estimate.characterCount == 0)
    #expect(estimate.estimatedTokenCount == 0)
}

@Test func agentPromptBudgetEstimatorRoundsOneCharacterUpToOneToken() {
    let estimate = AgentPromptBudgetEstimator().estimate("a")

    #expect(estimate.characterCount == 1)
    #expect(estimate.estimatedTokenCount == 1)
}

@Test func agentPromptBudgetEstimatorUsesEnglishHeuristicForLatinText() {
    let estimate = AgentPromptBudgetEstimator().estimate("abcdefgh")

    #expect(estimate.characterCount == 8)
    #expect(estimate.estimatedTokenCount == 3)
}

@Test func agentPromptBudgetEstimatorUsesCJKAwareHeuristicForChineseText() {
    let estimate = AgentPromptBudgetEstimator().estimate("继续推进上下文治理")

    #expect(estimate.characterCount == 9)
    #expect(estimate.estimatedTokenCount == 5)
}

@Test func sessionTokenCounterUsesPromptBudgetEstimatorForMessages() {
    let messages = [
        AgentMessage(role: .user, content: "abcdefgh"),
        AgentMessage(role: .assistant, content: "继续推进上下文治理")
    ]

    let estimate = SessionTokenCounter().estimate(messages: messages)

    #expect(estimate.messageCount == 2)
    #expect(estimate.totalTokenCount == 8)
    #expect(estimate.lastMessageTokenCount == 5)
}

@Test func agentPromptBudgetEstimatorClassifiesBudgetStatusThresholds() {
    let estimator = AgentPromptBudgetEstimator()

    #expect(estimator.status(estimatedTokenCount: 5_999) == .safe)
    #expect(estimator.status(estimatedTokenCount: 6_000) == .warning)
    #expect(estimator.status(estimatedTokenCount: 7_999) == .warning)
    #expect(estimator.status(estimatedTokenCount: 8_000) == .over)
}
