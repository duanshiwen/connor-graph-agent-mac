import Testing
@testable import ConnorGraphAgent

@Suite("Session context budget")
struct SessionContextBudgetTests {
    @Test func infersCurrentGLMContextWindows() {
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-5.2") == 1_000_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4-long") == 1_000_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4.5-air") == 128_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4.6v") == 128_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4.1v-thinking-flash") == 64_000)
        #expect(SessionContextBudget.inferContextWindowSize(modelID: "glm-4v-flash") == 16_000)
    }
}
