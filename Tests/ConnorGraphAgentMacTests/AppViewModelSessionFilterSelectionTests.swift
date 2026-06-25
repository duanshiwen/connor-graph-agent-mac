import AppKit
import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct AppViewModelSessionFilterSelectionTests {
    @Test func statusFilterClearsDetailWhenSelectedSessionIsNoLongerVisible() throws {
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

    @Test func statusFilterKeepsDetailWhenSelectedSessionRemainsVisible() throws {
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

        fixture.viewModel.setSessionListFilter(.status(.todo))

        #expect(fixture.viewModel.chatSessions.map(\.id).contains(selectedSession.id))
        #expect(!fixture.viewModel.chatSessions.map(\.id).contains(otherSession.id))
        #expect(fixture.viewModel.selectedChatSessionID == selectedSession.id)
        #expect(fixture.viewModel.transcript.map(\.content) == ["Selected transcript"])
    }

    @Test func labelFilterClearsDetailWhenSelectedSessionDoesNotHaveLabel() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        var hiddenSession = try fixture.repository.createSession(title: "Unlabelled selected", now: Date(timeIntervalSince1970: 2_000))
        hiddenSession.messages = [AgentMessage(role: .user, content: "Unlabelled transcript")]
        hiddenSession = try fixture.repository.saveSession(hiddenSession)

        let visibleSession = try fixture.repository.createSession(title: "Important", now: Date(timeIntervalSince1970: 3_000))
        _ = try fixture.repository.setLabels(sessionID: visibleSession.id, labels: [AgentSessionLabel(id: "important")])

        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.selectChatSession(hiddenSession.id)

        fixture.viewModel.setSessionListFilter(.label("important"))

        #expect(fixture.viewModel.chatSessions.map(\.id).contains(visibleSession.id))
        #expect(!fixture.viewModel.chatSessions.map(\.id).contains(hiddenSession.id))
        #expect(fixture.viewModel.selectedChatSessionID == nil)
        #expect(fixture.viewModel.transcript.isEmpty)
        #expect(fixture.viewModel.agentEventTimeline.isEmpty)
    }

    @Test func selectingDifferentChatSessionsKeepsSelectedIDAndTranscriptInSync() throws {
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
        #expect(fixture.viewModel.selectedChatSessionID == firstSession.id)
        #expect(fixture.viewModel.transcript.map(\.content) == ["First transcript"])
        let revisionAfterFirstSelection = fixture.viewModel.selectedChatTranscriptRevision
        #expect(revisionAfterFirstSelection > revisionAfterReload)

        fixture.viewModel.selectChatSession(secondSession.id)
        #expect(fixture.viewModel.selectedChatSessionID == secondSession.id)
        #expect(fixture.viewModel.transcript.map(\.content) == ["Second transcript", "Second response"])
        let revisionAfterSecondSelection = fixture.viewModel.selectedChatTranscriptRevision
        #expect(revisionAfterSecondSelection > revisionAfterFirstSelection)

        fixture.viewModel.selectChatSession(firstSession.id)
        #expect(fixture.viewModel.selectedChatSessionID == firstSession.id)
        #expect(fixture.viewModel.transcript.map(\.content) == ["First transcript"])
        #expect(fixture.viewModel.selectedChatTranscriptRevision > revisionAfterSecondSelection)
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
