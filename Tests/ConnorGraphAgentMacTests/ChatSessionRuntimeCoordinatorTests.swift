import AppKit
import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Chat session runtime coordinators")
struct ChatSessionRuntimeCoordinatorTests {
    @Test func workspaceCoordinatorRemovesAllSessionOwnedState() {
        let coordinator = ChatWorkspaceCoordinator()
        let sessionID = "session"
        coordinator.installState(AppSessionStateSnapshot(sessionID: sessionID), sessionID: sessionID)
        coordinator.installRecords([], sessionID: sessionID)
        coordinator.setMode(.browser, for: sessionID)

        coordinator.removeSession(sessionID)

        #expect(coordinator.state(for: sessionID) == nil)
        #expect(coordinator.recordsBySessionID[sessionID] == nil)
        #expect(coordinator.mode(for: sessionID) == .conversation)
    }

    @Test func attentionVisibilityDependsOnlyOnChatRouteAndSelectedSession() {
        let model = ChatSessionListModel()
        model.selectedSessionID = "selected"
        let coordinator = ChatAttentionCoordinator(model: model, repository: nil)
        var route = SidebarItem.agentChat
        coordinator.selectedNavigation = { route }

        #expect(coordinator.shouldTreatUpdateAsRead(sessionID: "selected"))
        #expect(!coordinator.shouldTreatUpdateAsRead(sessionID: "other"))
        route = .search
        #expect(!coordinator.shouldTreatUpdateAsRead(sessionID: "selected"))
    }

    @Test func dockBadgeApplyAndClearRemainSafe() {
        ChatAttentionCoordinator.applyDockBadge(count: 3, application: nil)
        let application = NSApplication.shared
        let original = application.dockTile.badgeLabel
        defer { application.dockTile.badgeLabel = original }

        ChatAttentionCoordinator.applyDockBadge(count: 3, application: application)
        #expect(application.dockTile.badgeLabel == "3")
        ChatAttentionCoordinator.applyDockBadge(count: 0, application: application)
        #expect(application.dockTile.badgeLabel == nil)
    }

    @Test func backgroundLoadInterruptsPersistedTaskAfterRestart() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let session = try fixture.repository.createSession(title: "Task owner")
        let persisted = PersistedSessionBackgroundTask(
            id: "task", sessionID: session.id, kind: "generic", title: "Task", detail: "Running",
            status: .running, createdAt: Date(), updatedAt: Date(), errorMessage: nil, payloadJSON: "{}"
        )
        try fixture.repository.saveBackgroundTask(persisted)
        let model = ChatSessionListModel()
        let coordinator = ChatBackgroundTaskCoordinator(model: model, repository: fixture.repository)

        try coordinator.load(sessionID: session.id)

        let task = try #require(model.backgroundTasksBySessionID[session.id]?.first)
        #expect(task.status == .interrupted)
        #expect(task.errorMessage?.contains("不会自动继续执行") == true)
    }

    @Test func sessionCoordinatorShutdownClearsLoadingAndRejectsNewSelection() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let session = try fixture.repository.createSession(title: "Selection")
        let model = ChatSessionListModel()
        let coordinator = ChatSessionCoordinator(model: model, repository: fixture.repository)

        coordinator.select(session.id)
        #expect(model.loadingSessionDetailID == session.id)
        coordinator.shutdown()

        #expect(model.loadingSessionDetailID == nil)
        coordinator.select(session.id)
        #expect(model.loadingSessionDetailID == nil)
    }
}

private struct RepositoryFixture {
    let directory: URL
    let repository: AppChatSessionRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("chat-runtime-coordinator-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: directory)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        let graphRepository = try AppGraphRepository.bootstrap(paths: paths)
        repository = AppChatSessionRepository(store: graphRepository.store, storagePaths: paths)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
