import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Composer Model Selection Presentation Tests")
struct ComposerModelSelectionPresentationTests {
    @Test func emptyModelFallsBackToUnselectedTitle() {
        let presentation = ComposerModelSelectionPresentation(
            selectedModel: "",
            sessionHasOverride: false
        )

        #expect(presentation.title == "未选择模型")
        #expect(presentation.accessibilityLabel == "模型：未选择模型")
        #expect(presentation.showsSessionOverrideIndicator == false)
    }

    @Test func longModelNameIsPreservedForAccessibility() {
        let model = "claude-sonnet-4-20250514-very-long-provider-specific-model-id"

        let presentation = ComposerModelSelectionPresentation(
            selectedModel: model,
            sessionHasOverride: false
        )

        #expect(presentation.title == model)
        #expect(presentation.accessibilityLabel == "模型：\(model)")
        #expect(presentation.showsSessionOverrideIndicator == false)
    }

    @Test func sessionOverrideAddsIndicatorAndAccessibilityContext() {
        let presentation = ComposerModelSelectionPresentation(
            selectedModel: "gpt-5.4-high-reasoning",
            sessionHasOverride: true
        )

        #expect(presentation.title == "gpt-5.4-high-reasoning")
        #expect(presentation.showsSessionOverrideIndicator == true)
        #expect(presentation.accessibilityLabel == "模型：gpt-5.4-high-reasoning，此会话使用自定义模型")
    }
}
