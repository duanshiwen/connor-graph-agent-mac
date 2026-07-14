import AppKit
import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct AppViewModelSessionFilterSelectionTests {
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

        #expect(fixture.viewModel.selectedChatSessionID == hiddenSession.id)
        #expect(fixture.viewModel.transcript.map(\.content) == ["Hidden transcript"])

        fixture.viewModel.setSessionListFilter(.status(.todo))

        #expect(fixture.viewModel.chatSessions.map(\.id).contains(visibleSession.id))
        #expect(!fixture.viewModel.chatSessions.map(\.id).contains(hiddenSession.id))
        #expect(fixture.viewModel.selectedChatSessionID == nil)
        #expect(fixture.viewModel.transcript.isEmpty)
        #expect(fixture.viewModel.agentEventTimeline.isEmpty)
        #expect(fixture.viewModel.latestChatSummary == nil)
        #expect(fixture.viewModel.selectedSessionArtifactDirectories == nil)
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

        #expect(fixture.viewModel.chatSessions.map(\.id).contains(selectedSession.id))
        #expect(!fixture.viewModel.chatSessions.map(\.id).contains(otherSession.id))
        #expect(fixture.viewModel.selectedChatSessionID == selectedSession.id)
        #expect(fixture.viewModel.transcript.map(\.content) == ["Selected transcript"])
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

        #expect(fixture.viewModel.chatSessions.map(\.id).contains(visibleSession.id))
        #expect(!fixture.viewModel.chatSessions.map(\.id).contains(hiddenSession.id))
        #expect(fixture.viewModel.selectedChatSessionID == nil)
        #expect(fixture.viewModel.transcript.isEmpty)
        #expect(fixture.viewModel.agentEventTimeline.isEmpty)
    }

    @Test func selectingExistingSessionTracksLoadingUntilDetailIsApplied() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var session = try fixture.repository.createSession(title: "Existing", now: Date(timeIntervalSince1970: 2_000))
        session.messages = [AgentMessage(role: .user, content: "Loaded transcript")]
        session = try fixture.repository.saveSession(session)

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession(session.id)

        #expect(fixture.viewModel.selectedChatSessionID == session.id)
        #expect(fixture.viewModel.loadingChatSessionDetailID == session.id)
        #expect(fixture.viewModel.isLoadingSelectedChatSessionDetail)
        #expect(fixture.viewModel.transcript.isEmpty)

        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.loadingChatSessionDetailID == nil)
        #expect(!fixture.viewModel.isLoadingSelectedChatSessionDetail)
        #expect(fixture.viewModel.transcript.map(\.content) == ["Loaded transcript"])
    }

    @Test func selectingPersistedEmptySessionFinishesLoadingWithEmptyTranscript() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = try fixture.repository.createSession(title: "Persisted empty", now: Date(timeIntervalSince1970: 2_000))

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession(session.id)

        #expect(fixture.viewModel.loadingChatSessionDetailID == session.id)
        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.selectedChatSessionID == session.id)
        #expect(fixture.viewModel.transcript.isEmpty)
        #expect(fixture.viewModel.loadingChatSessionDetailID == nil)
    }

    @Test(arguments: [true, false])
    func detailLoadDoesNotOverwriteComposerEdit(autoSaveDraftsEnabled: Bool) async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = try fixture.repository.createSession(title: "Composer race", now: Date(timeIntervalSince1970: 2_000))
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.inputSettingsModel.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        fixture.viewModel.selectChatSession(session.id)
        #expect(fixture.viewModel.loadingChatSessionDetailID == session.id)

        fixture.viewModel.updateSelectedChatInputDraft("a")
        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.chatInput == "a")
        #expect(fixture.viewModel.currentSelectedChatInputDraftForSpeech() == "a")
    }

    @Test(arguments: [true, false])
    func sameSessionReloadDoesNotOverwriteComposerEdit(autoSaveDraftsEnabled: Bool) throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.selectedChatSessionID)
        fixture.viewModel.inputSettingsModel.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        fixture.viewModel.updateSelectedChatInputDraft("draft in progress")

        fixture.viewModel.reloadChatSessions()

        #expect(fixture.viewModel.selectedChatSessionID == sessionID)
        #expect(fixture.viewModel.chatInput == "draft in progress")
        #expect(fixture.viewModel.currentSelectedChatInputDraftForSpeech() == "draft in progress")
    }

    @Test(arguments: [true, false])
    func sessionSwitchRestoresDraftOnlyWhenAutoSaveIsEnabled(autoSaveDraftsEnabled: Bool) async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let firstSessionID = try #require(fixture.viewModel.selectedChatSessionID)
        let secondSession = try fixture.repository.createSession(title: "Second composer", now: Date(timeIntervalSince1970: 3_000))
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.inputSettingsModel.autoSaveDraftsEnabled = autoSaveDraftsEnabled
        fixture.viewModel.updateSelectedChatInputDraft("first draft")

        fixture.viewModel.selectChatSession(secondSession.id)
        try await waitForLoadingToFinish(fixture.viewModel)
        #expect(fixture.viewModel.chatInput == "")
        fixture.viewModel.updateSelectedChatInputDraft("second draft")

        fixture.viewModel.selectChatSession(firstSessionID)
        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.chatInput == (autoSaveDraftsEnabled ? "first draft" : ""))
        #expect(fixture.viewModel.currentSelectedChatInputDraftForSpeech() == (autoSaveDraftsEnabled ? "first draft" : ""))
    }

    @Test func creatingNewSessionDoesNotEnterDetailLoadingState() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.newChatSession()

        #expect(fixture.viewModel.selectedChatSessionID != nil)
        #expect(fixture.viewModel.transcript.isEmpty)
        #expect(fixture.viewModel.loadingChatSessionDetailID == nil)
        #expect(!fixture.viewModel.isLoadingSelectedChatSessionDetail)
    }

    @Test func selectingMissingSessionDoesNotLeaveLoadingStuck() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession("missing-session")

        #expect(fixture.viewModel.loadingChatSessionDetailID == "missing-session")
        try await waitForLoadingToFinish(fixture.viewModel)

        #expect(fixture.viewModel.loadingChatSessionDetailID == nil)
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
        let revisionAfterReload = fixture.viewModel.selectedChatTranscriptRevision

        fixture.viewModel.selectChatSession(firstSession.id)
        try await waitForTranscript(fixture.viewModel, expectedContents: ["First transcript"])
        #expect(fixture.viewModel.selectedChatSessionID == firstSession.id)
        #expect(fixture.viewModel.transcript.map(\.content) == ["First transcript"])
        let revisionAfterFirstSelection = fixture.viewModel.selectedChatTranscriptRevision
        #expect(revisionAfterFirstSelection > revisionAfterReload)

        fixture.viewModel.selectChatSession(secondSession.id)
        try await waitForTranscript(fixture.viewModel, expectedContents: ["Second transcript", "Second response"])
        #expect(fixture.viewModel.selectedChatSessionID == secondSession.id)
        #expect(fixture.viewModel.transcript.map(\.content) == ["Second transcript", "Second response"])
        let revisionAfterSecondSelection = fixture.viewModel.selectedChatTranscriptRevision
        #expect(revisionAfterSecondSelection > revisionAfterFirstSelection)

        fixture.viewModel.selectChatSession(firstSession.id)
        try await waitForTranscript(fixture.viewModel, expectedContents: ["First transcript"])
        #expect(fixture.viewModel.selectedChatSessionID == firstSession.id)
        #expect(fixture.viewModel.transcript.map(\.content) == ["First transcript"])
        #expect(fixture.viewModel.selectedChatTranscriptRevision > revisionAfterSecondSelection)
    }

    private func waitForTranscript(_ viewModel: AppViewModel, expectedContents: [String]) async throws {
        for _ in 0..<100 {
            if viewModel.transcript.map(\.content) == expectedContents { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for transcript: \(expectedContents)")
    }

    private func waitForLoadingToFinish(_ viewModel: AppViewModel) async throws {
        for _ in 0..<100 {
            if viewModel.loadingChatSessionDetailID == nil { return }
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
        let viewModel = AppViewModel(
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
        var viewModel: AppViewModel
        var repository: AppChatSessionRepository

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
