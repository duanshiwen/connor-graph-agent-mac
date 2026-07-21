import Testing
@testable import ConnorGraphAgentMac

@Suite("AI connection naming")
struct AIConnectionNamingTests {
    @Test func compatibleProtocolsUseConciseNameComponents() {
        #expect(AIConnectionCustomProtocol.openAICompatible.connectionNameComponent == "OpenAI")
        #expect(AIConnectionCustomProtocol.anthropicCompatible.connectionNameComponent == "Anthropic")
    }
}
