import Testing
@testable import ConnorGraphAgentMac

@Suite("Xiaomi MiMo connection mode presets")
struct XiaomiMiMoConnectionModePresetTests {
    @Test func payAsYouGoUsesOfficialOpenAIEndpointAndSKPlaceholder() {
        let preset = XiaomiMiMoConnectionModePreset.payAsYouGo

        #expect(preset.title == "按量付费 API")
        #expect(preset.openAIEndpoint == "https://api.xiaomimimo.com/v1")
        #expect(preset.keyPlaceholder == "sk-...")
        #expect(preset.keyPrefixHint == "sk-...")
    }

    @Test func tokenPlanUsesOfficialOpenAIEndpointAndTPPlaceholder() {
        let preset = XiaomiMiMoConnectionModePreset.tokenPlan

        #expect(preset.title == "Token Plan")
        #expect(preset.openAIEndpoint == "https://token-plan-cn.xiaomimimo.com/v1")
        #expect(preset.keyPlaceholder == "tp-...")
        #expect(preset.keyPrefixHint == "tp-...")
        #expect(preset.purchaseURLString == "https://platform.xiaomimimo.com/#/token-plan")
        #expect(preset.managementURLString == "https://platform.xiaomimimo.com/#/console/plan-manage")
        #expect(preset.restrictionNotice?.contains("AI 编程工具") == true)
    }

    @Test func detectsTokenPlanKeyUsedWithPayAsYouGoMode() {
        let warning = XiaomiMiMoConnectionModePreset.payAsYouGo.keyEndpointMismatchWarning(for: "tp-secret")

        #expect(warning?.contains("Token Plan") == true)
        #expect(warning?.contains("https://token-plan-cn.xiaomimimo.com/v1") == true)
    }

    @Test func detectsPayAsYouGoKeyUsedWithTokenPlanMode() {
        let warning = XiaomiMiMoConnectionModePreset.tokenPlan.keyEndpointMismatchWarning(for: "sk-secret")

        #expect(warning?.contains("按量付费") == true)
        #expect(warning?.contains("https://api.xiaomimimo.com/v1") == true)
    }

    @Test func matchingKeyPrefixDoesNotWarn() {
        #expect(XiaomiMiMoConnectionModePreset.payAsYouGo.keyEndpointMismatchWarning(for: "sk-secret") == nil)
        #expect(XiaomiMiMoConnectionModePreset.tokenPlan.keyEndpointMismatchWarning(for: "tp-secret") == nil)
    }
}
