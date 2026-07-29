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
}
