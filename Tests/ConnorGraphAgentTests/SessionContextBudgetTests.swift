import Testing
@testable import ConnorGraphAgent

@Suite("Session context budget")
struct SessionContextBudgetTests {
    @Test func infersCurrentProviderContextWindowsDeterministically() {
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "gpt-4.1") == 1_047_576)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "gpt-5.4") == 1_050_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "openai/gpt-5.6-sol") == 272_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "deepseek-v4-pro") == 1_000_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "deepseek-chat") == 128_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "unknown-model") == 200_000)
    }

    @Test func explicitEndpointContextWindowOverridesCatalog() {
        #expect(SessionContextBudget.resolvedContextWindowSize(
            modelID: "gpt-5.6-sol",
            configuredOverride: 1_000_000
        ) == 1_000_000)
    }

    @Test func infersCurrentGLMContextWindows() {
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-5.2") == 1_000_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4-long") == 1_000_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4.5-air") == 128_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4.6v") == 128_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4.1v-thinking-flash") == 64_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4v-flash") == 16_000)
    }

    @Test func defaultCompressionThresholdIsHalfOfContextWindow() {
        let budget = SessionContextBudget(contextWindowSize: 200_000)
        #expect(budget.warningThreshold == 50_000)
        #expect(budget.compressionThreshold == 100_000)
        #expect(budget.safetyNetThreshold == 120_000)
        #expect(budget.status(tokenCount: 99_999) == .warning)
        #expect(budget.status(tokenCount: 100_000) == .shouldCompress)
        #expect(budget.status(tokenCount: 120_000) == .safetyNet)
    }

    @Test func configurableCompressionRatioShiftsThreshold() {
        let budget = SessionContextBudget(contextWindowSize: 200_000, compressionRatio: 0.60, safetyNetRatio: 0.75)
        #expect(budget.compressionThreshold == 120_000)
        #expect(budget.safetyNetThreshold == 150_000)
        #expect(budget.status(tokenCount: 100_000) == .warning)
        #expect(budget.status(tokenCount: 120_000) == .shouldCompress)
        #expect(budget.status(tokenCount: 150_000) == .safetyNet)
    }

    @Test func ratiosStayOrderedWhenMisconfigured() {
        let budget = SessionContextBudget(
            contextWindowSize: 100_000,
            warningRatio: 0.80,
            compressionRatio: 0.40,
            safetyNetRatio: 0.30
        )
        #expect(budget.warningRatio <= budget.compressionRatio)
        #expect(budget.compressionRatio <= budget.safetyNetRatio)
        #expect(budget.status(tokenCount: 0) == .normal)
    }
}
