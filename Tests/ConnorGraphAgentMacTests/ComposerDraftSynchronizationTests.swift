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

        viewModel.chatInput = "上一轮语音"
        viewModel.updateSelectedChatInputDraft("")

        #expect(viewModel.chatInput == "上一轮语音")
    }

    @Test func speechInputUsesLatestManualDraftInsteadOfPublishedChatInput() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )

        viewModel.chatInput = "上一轮语音"
        viewModel.updateSelectedChatInputDraft("")

        #expect(viewModel.currentSelectedChatInputDraftForSpeech() == "")
    }

    @Test func manualComposerEditKeepsLiveDraftWhenAutoSaveIsDisabled() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )
        viewModel.autoSaveDraftsEnabled = false
        viewModel.chatInput = ""

        viewModel.updateSelectedChatInputDraft("a")

        #expect(viewModel.currentSelectedChatInputDraftForSpeech() == "a")
        #expect(viewModel.chatInput == "")
    }

    @Test func repeatedManualEditsReplaceLiveDraftWithoutPublishingChatInput() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )
        viewModel.autoSaveDraftsEnabled = false
        viewModel.chatInput = "published value"

        viewModel.updateSelectedChatInputDraft("a")
        viewModel.updateSelectedChatInputDraft("ab")

        #expect(viewModel.currentSelectedChatInputDraftForSpeech() == "ab")
        #expect(viewModel.chatInput == "published value")
    }

    @Test(arguments: [true, false])
    func externalContextAppendPreservesLatestManualDraft(autoSaveDraftsEnabled: Bool) {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )
        viewModel.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        viewModel.chatInput = "stale published value"
        viewModel.updateSelectedChatInputDraft("current manual draft")

        viewModel.appendToSelectedChatInputDraft("external browser context")

        #expect(viewModel.chatInput == "current manual draft\n\nexternal browser context")
        #expect(viewModel.currentSelectedChatInputDraftForSpeech() == "current manual draft\n\nexternal browser context")
    }
}
