import Testing
@testable import ConnorGraphAgentMac

@Suite("Kimi connection mode presets")
struct KimiConnectionModePresetTests {
    @Test func payAsYouGoUsesMoonshotEndpointAndModels() {
        let preset = KimiConnectionModePreset.payAsYouGo

        #expect(preset.title == "按量付费 API")
        #expect(preset.openAIEndpoint == "https://api.moonshot.cn/v1")
        #expect(preset.defaultModel == "kimi-k2.6")
        #expect(preset.availableModels.contains("kimi-k2.7-code"))
        #expect(preset.keyPlaceholder == "sk-...")
    }

    @Test func codingPlanUsesDedicatedEndpointAndModels() {
        let preset = KimiConnectionModePreset.codingPlan

        #expect(preset.title == "Coding Plan")
        #expect(preset.openAIEndpoint == "https://api.kimi.com/coding/v1")
        #expect(preset.defaultModel == "kimi-for-coding")
        #expect(preset.availableModels == ["kimi-for-coding", "kimi-for-coding-highspeed", "k3"])
        #expect(preset.keyPlaceholder == "Kimi Code API Key")
        #expect(preset.purchaseURLString == "https://www.kimi.com/membership/pricing?from=kfc_docs_overview")
        #expect(preset.managementURLString == "https://www.kimi.com/code/console")
    }
}
