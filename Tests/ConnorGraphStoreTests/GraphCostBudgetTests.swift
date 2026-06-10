import Testing
import ConnorGraphCore

@Test func graphCostBudgetDomainTracksConfiguredLimitsAndUsage() throws {
    let budget = GraphCostBudget(
        id: "budget-1",
        scopeType: .global,
        scopeID: "default",
        period: .daily,
        tokenLimit: 1_000,
        costLimitMicrounits: 10_000,
        usedPromptTokens: 60,
        usedCompletionTokens: 40,
        usedCostMicrounits: 1_000
    )

    #expect(budget.scopeType == .global)
    #expect(budget.period == .daily)
    #expect(budget.tokenLimit == 1_000)
    #expect(budget.costLimitMicrounits == 10_000)
    #expect(budget.usedPromptTokens + budget.usedCompletionTokens == 100)
    #expect(budget.usedCostMicrounits == 1_000)
}

@Test func graphCostBudgetDecisionEquatableCasesRemainStable() throws {
    #expect(GraphCostBudgetDecision.allowed == .allowed)
    #expect(GraphCostBudgetDecision.blocked(reason: "token_limit") == .blocked(reason: "token_limit"))
}
