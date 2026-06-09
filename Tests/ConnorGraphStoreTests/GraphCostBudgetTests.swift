import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryBudgetDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphCostBudgetAllowsUsageWithinLimitsAndRecordsUsage() throws {
    let store = try SQLiteGraphStore(path: temporaryBudgetDatabaseURL().path)
    try store.migrate()
    let budget = GraphCostBudget(id: "budget-1", scopeType: .global, scopeID: "default", period: .daily, tokenLimit: 1_000, costLimitMicrounits: 10_000)
    try store.upsert(costBudget: budget)

    let decision = try store.checkCostBudget(scopeType: .global, scopeID: "default", period: .daily, estimatedTokens: 100, estimatedCostMicrounits: 1_000)
    #expect(decision == .allowed)

    try store.recordCostUsage(scopeType: .global, scopeID: "default", period: .daily, promptTokens: 60, completionTokens: 40, costMicrounits: 1_000)
    let loaded = try #require(try store.costBudget(scopeType: .global, scopeID: "default", period: .daily))
    #expect(loaded.usedPromptTokens == 60)
    #expect(loaded.usedCompletionTokens == 40)
    #expect(loaded.usedCostMicrounits == 1_000)
}

@Test func graphCostBudgetBlocksWhenTokenLimitWouldBeExceeded() throws {
    let store = try SQLiteGraphStore(path: temporaryBudgetDatabaseURL().path)
    try store.migrate()
    try store.upsert(costBudget: GraphCostBudget(id: "budget-1", scopeType: .global, scopeID: "default", period: .daily, tokenLimit: 100, costLimitMicrounits: 10_000, usedPromptTokens: 90))

    let decision = try store.checkCostBudget(scopeType: .global, scopeID: "default", period: .daily, estimatedTokens: 11, estimatedCostMicrounits: 1)

    #expect(decision == .blocked(reason: "token_limit_exceeded"))
}

@Test func graphCostBudgetBlocksWhenCostLimitWouldBeExceeded() throws {
    let store = try SQLiteGraphStore(path: temporaryBudgetDatabaseURL().path)
    try store.migrate()
    try store.upsert(costBudget: GraphCostBudget(id: "budget-1", scopeType: .global, scopeID: "default", period: .daily, tokenLimit: 1_000, costLimitMicrounits: 100, usedCostMicrounits: 95))

    let decision = try store.checkCostBudget(scopeType: .global, scopeID: "default", period: .daily, estimatedTokens: 1, estimatedCostMicrounits: 6)

    #expect(decision == .blocked(reason: "cost_limit_exceeded"))
}

@Test func graphCostBudgetMissingBudgetDefaultsToAllowed() throws {
    let store = try SQLiteGraphStore(path: temporaryBudgetDatabaseURL().path)
    try store.migrate()

    let decision = try store.checkCostBudget(scopeType: .global, scopeID: "missing", period: .daily, estimatedTokens: 10, estimatedCostMicrounits: 10)

    #expect(decision == .allowed)
}
