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

@Test func agentPromptBudgetEstimatorCountsFourCharactersAsOneToken() {
    let estimate = AgentPromptBudgetEstimator().estimate("abcd")

    #expect(estimate.characterCount == 4)
    #expect(estimate.estimatedTokenCount == 1)
}

@Test func agentPromptBudgetEstimatorRoundsFiveCharactersUpToTwoTokens() {
    let estimate = AgentPromptBudgetEstimator().estimate("abcde")

    #expect(estimate.characterCount == 5)
    #expect(estimate.estimatedTokenCount == 2)
}

@Test func agentPromptBudgetEstimatorClassifiesBudgetStatusThresholds() {
    let estimator = AgentPromptBudgetEstimator()

    #expect(estimator.status(estimatedTokenCount: 5_999) == .safe)
    #expect(estimator.status(estimatedTokenCount: 6_000) == .warning)
    #expect(estimator.status(estimatedTokenCount: 7_999) == .warning)
    #expect(estimator.status(estimatedTokenCount: 8_000) == .over)
}
