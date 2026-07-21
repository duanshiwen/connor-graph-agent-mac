import Testing
@testable import ConnorGraphAgentMac

@Suite("GLM connection provider preset")
struct GLMConnectionProviderPresetTests {
    private var preset: AIConnectionProviderPreset {
        AIConnectionProviderPreset.otherProviderPresets.first { $0.id == "zhipu" }!
    }

    @Test func usesCurrentFlagshipModelAndOfficialEndpoint() {
        #expect(preset.endpoint == "https://open.bigmodel.cn/api/paas/v4")
        #expect(preset.defaultModel == "glm-5.2")
        #expect(preset.supportedModels.first == "glm-5.2")
    }

    @Test func includesCurrentChatModelsAndRemovesDeprecatedModels() {
        #expect(preset.supportedModels.contains("glm-5.2"))
        #expect(preset.supportedModels.contains("glm-4.7-flash"))
        #expect(preset.supportedModels.contains("glm-4.6v-flash"))
        #expect(preset.supportedModels.contains("glm-z1-air") == false)
        #expect(preset.supportedModels.contains("glm-4.5-flash") == false)
    }

    @Test func marksCurrentVisualModelsAsVisionCapable() {
        #expect(preset.defaultVisionModels.contains("glm-5v-turbo"))
        #expect(preset.defaultVisionModels.contains("glm-4.6v"))
        #expect(preset.defaultVisionModels.contains("glm-4.1v-thinking-flash"))
        #expect(Set(preset.defaultVisionModels).isSubset(of: Set(preset.supportedModels)))
    }
}
