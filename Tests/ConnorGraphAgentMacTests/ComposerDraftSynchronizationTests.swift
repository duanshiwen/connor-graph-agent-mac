import AppKit
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Composer Draft Synchronization Tests")
struct ComposerDraftSynchronizationTests {
    @Test func manualComposerEditUpdatesPublishedChatInputForNextSpeechRun() {
        _ = NSApplication.shared
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: []
        )

        viewModel.chatInput = "上一轮语音"
        viewModel.updateSelectedChatInputDraft("")

        #expect(viewModel.chatInput == "")
    }
}
