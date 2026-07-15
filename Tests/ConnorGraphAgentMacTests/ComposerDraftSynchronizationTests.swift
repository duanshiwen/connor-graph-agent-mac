import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Composer Draft Synchronization Tests")
struct ComposerDraftSynchronizationTests {
    @Test func manualComposerEditDoesNotPublishChatInputOnEveryKeystroke() {
        let fixture = makeFixture()
        fixture.model.input = "上一轮语音"

        fixture.coordinator.updateSelectedDraft("")

        #expect(fixture.model.input == "上一轮语音")
    }

    @Test func speechInputUsesLatestManualDraftInsteadOfPublishedChatInput() {
        let fixture = makeFixture()
        fixture.model.input = "上一轮语音"

        fixture.coordinator.updateSelectedDraft("")

        #expect(fixture.coordinator.currentSelectedDraft() == "")
    }

    @Test func manualComposerEditKeepsLiveDraftWhenAutoSaveIsDisabled() {
        let fixture = makeFixture(autoSaveDraftsEnabled: false)
        fixture.model.input = ""

        fixture.coordinator.updateSelectedDraft("a")

        #expect(fixture.coordinator.currentSelectedDraft() == "a")
        #expect(fixture.model.input == "")
    }

    @Test func repeatedManualEditsReplaceLiveDraftWithoutPublishingChatInput() {
        let fixture = makeFixture(autoSaveDraftsEnabled: false)
        fixture.model.input = "published value"

        fixture.coordinator.updateSelectedDraft("a")
        fixture.coordinator.updateSelectedDraft("ab")

        #expect(fixture.coordinator.currentSelectedDraft() == "ab")
        #expect(fixture.model.input == "published value")
    }

    @Test(arguments: [true, false])
    func externalContextAppendPreservesLatestManualDraft(autoSaveDraftsEnabled: Bool) {
        let fixture = makeFixture(autoSaveDraftsEnabled: autoSaveDraftsEnabled)
        fixture.model.input = "stale published value"
        fixture.coordinator.updateSelectedDraft("current manual draft")

        fixture.coordinator.appendToSelectedDraft("external browser context")

        #expect(fixture.model.input == "current manual draft\n\nexternal browser context")
        #expect(fixture.coordinator.currentSelectedDraft() == "current manual draft\n\nexternal browser context")
    }

    private func makeFixture(autoSaveDraftsEnabled: Bool = true) -> (model: ChatComposerModel, coordinator: ChatComposerCoordinator) {
        let model = ChatComposerModel()
        let coordinator = ChatComposerCoordinator(model: model, storagePaths: nil)
        coordinator.selectedSessionID = { "session" }
        coordinator.autoSaveDraftsEnabled = { autoSaveDraftsEnabled }
        return (model, coordinator)
    }
}
