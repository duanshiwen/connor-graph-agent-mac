import Testing
@testable import ConnorGraphAppSupport

@Suite("Xiaomi MiMo speech availability")
struct XiaomiMiMOSpeechAvailabilityTests {
    @Test func requiresOfficialEndpointMiMoModelAndAPIKey() {
        let available = connection(
            endpoint: "https://api.xiaomimimo.com/v1",
            model: "mimo-v2.5-pro",
            hasAPIKey: true
        )

        #expect(available.supportsXiaomiMiMOSpeech)
        #expect(available.isXiaomiMiMOConnection)
        #expect(!connection(endpoint: available.baseURLString, model: available.model, hasAPIKey: false).supportsXiaomiMiMOSpeech)
        let tokenPlan = connection(endpoint: "https://token-plan-cn.xiaomimimo.com/v1", model: available.model, hasAPIKey: true)
        #expect(tokenPlan.isXiaomiMiMOConnection)
        #expect(tokenPlan.supportsXiaomiMiMOSpeech)
        #expect(!connection(endpoint: available.baseURLString, model: "deepseek-v4", hasAPIKey: true).supportsXiaomiMiMOSpeech)
    }

    @Test func supportsOfficialAnthropicTokenPlanForSpeech() {
        let connection = AppLLMConnectionConfig(
            id: "mimo-token-plan",
            name: "Xiaomi MiMo",
            providerMode: .anthropicMessages,
            connectionKind: .anthropicCompatible,
            baseURLString: "https://token-plan-cn.xiaomimimo.com/anthropic",
            model: "mimo-v2.5-pro, mimo-v2.5",
            selectedModel: "mimo-v2.5-pro",
            hasAPIKey: true
        )

        #expect(connection.isXiaomiMiMOConnection)
        #expect(connection.supportsXiaomiMiMOSpeech)
    }

    @Test func settingsPreferDefaultAvailableConnectionThenFallBackToAnotherMiMoConnection() {
        let unavailableDefault = connection(endpoint: "https://api.deepseek.com", model: "deepseek-v4", hasAPIKey: true, id: "default")
        let mimo = connection(endpoint: "https://api.xiaomimimo.com/v1", model: "mimo-v2.5", hasAPIKey: true, id: "mimo")
        let settings = AppLLMSettings(connections: [unavailableDefault, mimo], defaultConnectionID: unavailableDefault.id)

        #expect(settings.xiaomiMiMOSpeechConnection?.id == mimo.id)
    }

    private func connection(
        endpoint: String,
        model: String,
        hasAPIKey: Bool,
        id: String = "mimo"
    ) -> AppLLMConnectionConfig {
        AppLLMConnectionConfig(
            id: id,
            name: id,
            providerMode: .openAICompatible,
            baseURLString: endpoint,
            model: model,
            selectedModel: model,
            hasAPIKey: hasAPIKey
        )
    }
}
