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
