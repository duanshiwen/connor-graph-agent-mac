import AppKit
import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct AppRuntimeOrchestratorSessionFilterSelectionTests {
    @Test func statusFilterClearsDetailWhenSelectedSessionIsNoLongerVisible() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var hiddenSession = try fixture.repository.createSession(title: "Hidden in progress", now: Date(timeIntervalSince1970: 2_000))
        hiddenSession.messages = [AgentMessage(role: .user, content: "Hidden transcript")]
        hiddenSession = try fixture.repository.saveSession(hiddenSession)
        hiddenSession = try fixture.repository.setStatus(sessionID: hiddenSession.id, status: .inProgress)

        var visibleSession = try fixture.repository.createSession(title: "Visible todo", now: Date(timeIntervalSince1970: 3_000))
        visibleSession = try fixture.repository.setStatus(sessionID: visibleSession.id, status: .todo)

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession(hiddenSession.id)
        try await waitForTranscript(fixture.viewModel, expectedContents: ["Hidden transcript"])

        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == hiddenSession.id)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.map(\.content) == ["Hidden transcript"])

        fixture.viewModel.setSessionListFilter(.status(.todo))

        #expect(fixture.viewModel.chatFeatureModel.sessions.sessions.map(\.id).contains(visibleSession.id))
        #expect(!fixture.viewModel.chatFeatureModel.sessions.sessions.map(\.id).contains(hiddenSession.id))
        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == nil)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.isEmpty)
        #expect(fixture.viewModel.chatFeatureModel.run.eventTimeline.isEmpty)
        #expect(fixture.viewModel.chatFeatureModel.run.latestSummary == nil)
        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedArtifactDirectories == nil)
    }

    @Test func statusFilterKeepsDetailWhenSelectedSessionRemainsVisible() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var selectedSession = try fixture.repository.createSession(title: "Selected todo", now: Date(timeIntervalSince1970: 2_000))
        selectedSession.messages = [AgentMessage(role: .user, content: "Selected transcript")]
        selectedSession = try fixture.repository.saveSession(selectedSession)
        selectedSession = try fixture.repository.setStatus(sessionID: selectedSession.id, status: .todo)

        let otherSession = try fixture.repository.createSession(title: "Other in progress", now: Date(timeIntervalSince1970: 3_000))
        _ = try fixture.repository.setStatus(sessionID: otherSession.id, status: .inProgress)

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession(selectedSession.id)
        try await waitForTranscript(fixture.viewModel, expectedContents: ["Selected transcript"])

        fixture.viewModel.setSessionListFilter(.status(.todo))

        #expect(fixture.viewModel.chatFeatureModel.sessions.sessions.map(\.id).contains(selectedSession.id))
        #expect(!fixture.viewModel.chatFeatureModel.sessions.sessions.map(\.id).contains(otherSession.id))
        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == selectedSession.id)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.map(\.content) == ["Selected transcript"])
    }

    @Test func labelFilterClearsDetailWhenSelectedSessionDoesNotHaveLabel() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var hiddenSession = try fixture.repository.createSession(title: "Unlabelled selected", now: Date(timeIntervalSince1970: 2_000))
        hiddenSession.messages = [AgentMessage(role: .user, content: "Unlabelled transcript")]
        hiddenSession = try fixture.repository.saveSession(hiddenSession)

        let visibleSession = try fixture.repository.createSession(title: "Important", now: Date(timeIntervalSince1970: 3_000))
        _ = try fixture.repository.setLabels(sessionID: visibleSession.id, labels: [AgentSessionLabel(id: "important")])

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession(hiddenSession.id)
        try await waitForTranscript(fixture.viewModel, expectedContents: ["Unlabelled transcript"])

        fixture.viewModel.setSessionListFilter(.label("important"))

        #expect(fixture.viewModel.chatFeatureModel.sessions.sessions.map(\.id).contains(visibleSession.id))
        #expect(!fixture.viewModel.chatFeatureModel.sessions.sessions.map(\.id).contains(hiddenSession.id))
        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == nil)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.isEmpty)
        #expect(fixture.viewModel.chatFeatureModel.run.eventTimeline.isEmpty)
    }

    @Test func selectingExistingSessionTracksLoadingUntilDetailIsApplied() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var session = try fixture.repository.createSession(title: "Existing", now: Date(timeIntervalSince1970: 2_000))
        session.messages = [AgentMessage(role: .user, content: "Loaded transcript")]
        session = try fixture.repository.saveSession(session)

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession(session.id)

        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == session.id)
        #expect(fixture.viewModel.chatFeatureModel.sessions.loadingSessionDetailID == session.id)
        #expect(fixture.viewModel.isLoadingSelectedChatSessionDetail)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.isEmpty)

        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.chatFeatureModel.sessions.loadingSessionDetailID == nil)
        #expect(!fixture.viewModel.isLoadingSelectedChatSessionDetail)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.map(\.content) == ["Loaded transcript"])
    }

    @Test func selectingPersistedEmptySessionFinishesLoadingWithEmptyTranscript() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = try fixture.repository.createSession(title: "Persisted empty", now: Date(timeIntervalSince1970: 2_000))

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession(session.id)

        #expect(fixture.viewModel.chatFeatureModel.sessions.loadingSessionDetailID == session.id)
        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == session.id)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.isEmpty)
        #expect(fixture.viewModel.chatFeatureModel.sessions.loadingSessionDetailID == nil)
    }

    @Test(arguments: [true, false])
    func detailLoadDoesNotOverwriteComposerEdit(autoSaveDraftsEnabled: Bool) async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = try fixture.repository.createSession(title: "Composer race", now: Date(timeIntervalSince1970: 2_000))
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.inputSettingsModel.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        fixture.viewModel.selectChatSession(session.id)
        #expect(fixture.viewModel.chatFeatureModel.sessions.loadingSessionDetailID == session.id)

        fixture.viewModel.chatComposerCoordinator.updateSelectedDraft("a")
        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.chatFeatureModel.composer.input == "a")
        #expect(fixture.viewModel.chatComposerCoordinator.currentSelectedDraft() == "a")
    }

    @Test(arguments: [true, false])
    func sameSessionReloadDoesNotOverwriteComposerEdit(autoSaveDraftsEnabled: Bool) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID)
        fixture.viewModel.inputSettingsModel.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        fixture.viewModel.chatComposerCoordinator.updateSelectedDraft("draft in progress")

        fixture.viewModel.reloadChatSessions()

        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == sessionID)
        #expect(fixture.viewModel.chatFeatureModel.composer.input == "draft in progress")
        #expect(fixture.viewModel.chatComposerCoordinator.currentSelectedDraft() == "draft in progress")
    }

    @Test(arguments: [true, false])
    func sessionSwitchRestoresDraftOnlyWhenAutoSaveIsEnabled(autoSaveDraftsEnabled: Bool) async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let firstSessionID = try #require(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID)
        let secondSession = try fixture.repository.createSession(title: "Second composer", now: Date(timeIntervalSince1970: 3_000))
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.inputSettingsModel.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        fixture.viewModel.chatComposerCoordinator.updateSelectedDraft("first draft")

        fixture.viewModel.selectChatSession(secondSession.id)
        try await waitForLoadingToFinish(fixture.viewModel)
        #expect(fixture.viewModel.chatFeatureModel.composer.input == "")
        fixture.viewModel.chatComposerCoordinator.updateSelectedDraft("second draft")

        fixture.viewModel.selectChatSession(firstSessionID)
        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.chatFeatureModel.composer.input == (autoSaveDraftsEnabled ? "first draft" : ""))
        #expect(fixture.viewModel.chatComposerCoordinator.currentSelectedDraft() == (autoSaveDraftsEnabled ? "first draft" : ""))
    }

    @Test func creatingNewSessionDoesNotEnterDetailLoadingState() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.newChatSession()

        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID != nil)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.isEmpty)
        #expect(fixture.viewModel.chatFeatureModel.sessions.loadingSessionDetailID == nil)
        #expect(!fixture.viewModel.isLoadingSelectedChatSessionDetail)
    }

    @Test func selectingMissingSessionDoesNotLeaveLoadingStuck() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession("missing-session")

        #expect(fixture.viewModel.chatFeatureModel.sessions.loadingSessionDetailID == "missing-session")
        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.chatFeatureModel.sessions.loadingSessionDetailID == nil)
        #expect(fixture.viewModel.errorMessage == "无法加载所选会话。")
    }

    @Test func selectingDifferentChatSessionsKeepsSelectedIDAndTranscriptInSync() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var firstSession = try fixture.repository.createSession(title: "First", now: Date(timeIntervalSince1970: 2_000))
        firstSession.messages = [
            AgentMessage(role: .user, content: "First transcript")
        ]
        firstSession = try fixture.repository.saveSession(firstSession)

        var secondSession = try fixture.repository.createSession(title: "Second", now: Date(timeIntervalSince1970: 3_000))
        secondSession.messages = [
            AgentMessage(role: .user, content: "Second transcript"),
            AgentMessage(role: .assistant, content: "Second response")
        ]
        secondSession = try fixture.repository.saveSession(secondSession)

        fixture.viewModel.reloadChatSessions()
        let revisionAfterReload = fixture.viewModel.chatFeatureModel.run.transcriptRevision

        fixture.viewModel.selectChatSession(firstSession.id)
        try await waitForTranscript(fixture.viewModel, expectedContents: ["First transcript"])
        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == firstSession.id)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.map(\.content) == ["First transcript"])
        let revisionAfterFirstSelection = fixture.viewModel.chatFeatureModel.run.transcriptRevision
        #expect(revisionAfterFirstSelection > revisionAfterReload)

        fixture.viewModel.selectChatSession(secondSession.id)
        try await waitForTranscript(fixture.viewModel, expectedContents: ["Second transcript", "Second response"])
        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == secondSession.id)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.map(\.content) == ["Second transcript", "Second response"])
        let revisionAfterSecondSelection = fixture.viewModel.chatFeatureModel.run.transcriptRevision
        #expect(revisionAfterSecondSelection > revisionAfterFirstSelection)

        fixture.viewModel.selectChatSession(firstSession.id)
        try await waitForTranscript(fixture.viewModel, expectedContents: ["First transcript"])
        #expect(fixture.viewModel.chatFeatureModel.sessions.selectedSessionID == firstSession.id)
        #expect(fixture.viewModel.chatFeatureModel.run.transcript.map(\.content) == ["First transcript"])
        #expect(fixture.viewModel.chatFeatureModel.run.transcriptRevision > revisionAfterSecondSelection)
    }

    private func waitForTranscript(_ viewModel: AppRuntimeOrchestrator, expectedContents: [String]) async throws {
        for _ in 0..<100 {
            if viewModel.chatFeatureModel.run.transcript.map(\.content) == expectedContents { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for transcript: \(expectedContents)")
    }

    private func waitForLoadingToFinish(_ viewModel: AppRuntimeOrchestrator) async throws {
        for _ in 0..<100 {
            if viewModel.chatFeatureModel.sessions.loadingSessionDetailID == nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for session detail loading to finish")
    }

    private func makeFixture() throws -> Fixture {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-app-vm-session-filter-selection-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        let graphRepository = try AppGraphRepository.bootstrap(paths: paths)
        let viewModel = AppRuntimeOrchestrator(
            entities: [],
            statements: [],
            observeLogEntries: [],
            repository: graphRepository,
            databasePath: paths.databaseURL.path,
            storagePaths: paths
        )
        let sessionRepository = AppChatSessionRepository(store: graphRepository.store, storagePaths: paths)
        return Fixture(root: root, viewModel: viewModel, repository: sessionRepository)
    }

    private struct Fixture {
        var root: URL
        var viewModel: AppRuntimeOrchestrator
        var repository: AppChatSessionRepository

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
