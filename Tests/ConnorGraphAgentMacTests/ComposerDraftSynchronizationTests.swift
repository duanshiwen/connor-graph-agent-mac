import Foundation
import Testing
import ConnorGraphAppSupport
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

    @Test func persistedDraftSurvivesCoordinatorRecreation() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()

        let firstModel = ChatComposerModel()
        let first = ChatComposerCoordinator(model: firstModel, storagePaths: paths, draftSaveDelay: 60)
        first.selectedSessionID = { "session" }
        first.updateSelectedDraft("跨启动草稿")
        first.shutdown()

        let restoredModel = ChatComposerModel()
        let restored = ChatComposerCoordinator(model: restoredModel, storagePaths: paths)
        restored.selectedSessionID = { "session" }
        restored.restore(sessionID: "session")

        #expect(restoredModel.input == "跨启动草稿")
    }

    @Test func silentPersistenceNeverPublishesDuringTyping() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let model = ChatComposerModel()
        model.input = "published value"
        let coordinator = ChatComposerCoordinator(model: model, storagePaths: paths, draftSaveDelay: 0)
        coordinator.selectedSessionID = { "session" }

        coordinator.updateSelectedDraft("a")
        coordinator.updateSelectedDraft("ab")
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.input == "published value")
        #expect(ChatComposerDraftRepository(storagePaths: paths).load(sessionID: "session") == "ab")
        coordinator.shutdown()
    }

    @Test func repeatedRestoreForSameDisplayedSessionDoesNotWriteBack() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        try ChatComposerDraftRepository(storagePaths: paths).save("stored draft", sessionID: "session")
        let model = ChatComposerModel()
        let coordinator = ChatComposerCoordinator(model: model, storagePaths: paths)
        coordinator.selectedSessionID = { "session" }

        coordinator.restore(sessionID: "session")
        #expect(model.input == "stored draft")
        model.input = "new in-memory input"
        coordinator.restore(sessionID: "session")

        #expect(model.input == "new in-memory input")
    }

    @Test func submissionClearsPersistedDraft() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let coordinator = ChatComposerCoordinator(model: ChatComposerModel(), storagePaths: paths, draftSaveDelay: 60)
        coordinator.selectedSessionID = { "session" }
        coordinator.updateSelectedDraft("will be sent")
        coordinator.consumeForSubmission(sessionID: "session")
        coordinator.shutdown()

        #expect(ChatComposerDraftRepository(storagePaths: paths).load(sessionID: "session") == nil)
    }

    private func makeFixture(autoSaveDraftsEnabled: Bool = true) -> (model: ChatComposerModel, coordinator: ChatComposerCoordinator) {
        let model = ChatComposerModel()
        let coordinator = ChatComposerCoordinator(model: model, storagePaths: nil)
        coordinator.selectedSessionID = { "session" }
        coordinator.autoSaveDraftsEnabled = { autoSaveDraftsEnabled }
        return (model, coordinator)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("composer-draft-persistence-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
