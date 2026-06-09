import Foundation
import Testing
import ConnorGraphAgent

@Test func budgetMeterTracksTokensAndDeniesWhenLimitExceeded() async throws {
    let meter = AgentBudgetMeter(configuration: AgentBudgetConfiguration(maxTotalTokens: 100, warningThresholdRatio: 0.8))
    let first = await meter.record(AgentModelUsage(promptTokens: 30, completionTokens: 40))
    #expect(first.totalTokens == 70)
    #expect(first.status == .ok)

    let second = await meter.record(AgentModelUsage(promptTokens: 20, completionTokens: 5))
    #expect(second.totalTokens == 95)
    #expect(second.status == .warning)

    let third = await meter.record(AgentModelUsage(promptTokens: 10, completionTokens: 1))
    #expect(third.status == .exceeded)
}
