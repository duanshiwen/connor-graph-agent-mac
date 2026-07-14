import AppKit
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Composer Draft Synchronization Tests")
struct ComposerDraftSynchronizationTests {
    @Test func manualComposerEditDoesNotPublishChatInputOnEveryKeystroke() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )

        viewModel.chatFeatureModel.composer.input = "上一轮语音"
        viewModel.chatComposerCoordinator.updateSelectedDraft("")

        #expect(viewModel.chatFeatureModel.composer.input == "上一轮语音")
    }

    @Test func speechInputUsesLatestManualDraftInsteadOfPublishedChatInput() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )

        viewModel.chatFeatureModel.composer.input = "上一轮语音"
        viewModel.chatComposerCoordinator.updateSelectedDraft("")

        #expect(viewModel.chatComposerCoordinator.currentSelectedDraft() == "")
    }

    @Test func manualComposerEditKeepsLiveDraftWhenAutoSaveIsDisabled() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )
        viewModel.inputSettingsModel.autoSaveDraftsEnabled = false
        viewModel.chatFeatureModel.composer.input = ""

        viewModel.chatComposerCoordinator.updateSelectedDraft("a")

        #expect(viewModel.chatComposerCoordinator.currentSelectedDraft() == "a")
        #expect(viewModel.chatFeatureModel.composer.input == "")
    }

    @Test func repeatedManualEditsReplaceLiveDraftWithoutPublishingChatInput() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )
        viewModel.inputSettingsModel.autoSaveDraftsEnabled = false
        viewModel.chatFeatureModel.composer.input = "published value"

        viewModel.chatComposerCoordinator.updateSelectedDraft("a")
        viewModel.chatComposerCoordinator.updateSelectedDraft("ab")

        #expect(viewModel.chatComposerCoordinator.currentSelectedDraft() == "ab")
        #expect(viewModel.chatFeatureModel.composer.input == "published value")
    }

    @Test(arguments: [true, false])
    func externalContextAppendPreservesLatestManualDraft(autoSaveDraftsEnabled: Bool) {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )
        viewModel.inputSettingsModel.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        viewModel.chatFeatureModel.composer.input = "stale published value"
        viewModel.chatComposerCoordinator.updateSelectedDraft("current manual draft")

        viewModel.chatComposerCoordinator.appendToSelectedDraft("external browser context")

        #expect(viewModel.chatFeatureModel.composer.input == "current manual draft\n\nexternal browser context")
        #expect(viewModel.chatComposerCoordinator.currentSelectedDraft() == "current manual draft\n\nexternal browser context")
    }
}
