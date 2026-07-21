import AppKit
import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
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

    @Test func runCoordinatorOwnsSubmissionCancellationAndShutdownState() {
        let model = ChatRunModel()
        let coordinator = ChatRunCoordinator(model: model, fallbackSession: AgentSession(id: "session"))
        coordinator.selectedSessionID = { "session" }
        let backend = AnyAgentBackend(CoordinatorTestBackend())

        #expect(coordinator.begin(sessionID: "session", backend: backend))
        #expect(!coordinator.begin(sessionID: "session", backend: backend))
        #expect(model.submittingSessionIDs == ["session"])
        if case .queued = coordinator.requestCancellation(sessionID: "session", reason: "cancel") {} else { Issue.record("Expected queued cancellation") }
        if case .alreadyQueued = coordinator.requestCancellation(sessionID: "session", reason: "cancel") {} else { Issue.record("Expected deduplicated cancellation") }
        #expect(coordinator.registerRun(sessionID: "session", runID: "run", backend: backend) == "cancel")

        coordinator.shutdown()
        #expect(model.submittingSessionIDs.isEmpty)
        #expect(!model.isSubmitting)
        #expect(!coordinator.begin(sessionID: "session", backend: backend))
    }

    @Test func completedRunDoesNotRestoreManagerReplacedDuringSubmission() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let completedSession = AgentSession(
            id: "session",
            messages: [AgentMessage(role: .assistant, content: "completed")]
        )
        let submittedManager = NativeSessionManager(
            backend: CoordinatorTestBackend(),
            sessionRepository: fixture.repository,
            session: completedSession,
            permissionMode: .askToWrite
        )
        let replacementManager = NativeSessionManager(
            backend: CoordinatorTestBackend(),
            sessionRepository: fixture.repository,
            session: AgentSession(id: "session"),
            permissionMode: .trustedWrite
        )
        let model = ChatRunModel()
        let coordinator = ChatRunCoordinator(model: model, fallbackSession: completedSession)
        coordinator.installManager(submittedManager)
        let submittedRevision = coordinator.managerRevision
        coordinator.installManager(replacementManager)

        let restored = coordinator.applyCompletedRun(
            manager: submittedManager,
            session: completedSession,
            summary: nil,
            submittedManagerRevision: submittedRevision
        )

        #expect(!restored)
        #expect(coordinator.manager?.permissionMode == .trustedWrite)
        #expect(model.transcript.map(\.content) == ["completed"])
    }

    @Test func failedRunDoesNotRestoreManagerReplacedDuringSubmission() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let session = AgentSession(id: "session")
        let submittedManager = NativeSessionManager(
            backend: CoordinatorTestBackend(),
            sessionRepository: fixture.repository,
            session: session,
            permissionMode: .askToWrite
        )
        let replacementManager = NativeSessionManager(
            backend: CoordinatorTestBackend(),
            sessionRepository: fixture.repository,
            session: session,
            permissionMode: .trustedWrite
        )
        let recoveredTranscript = [AgentMessage(role: .user, content: "recover me")]
        let model = ChatRunModel()
        let coordinator = ChatRunCoordinator(model: model, fallbackSession: session)
        coordinator.installManager(submittedManager)
        let submittedRevision = coordinator.managerRevision
        coordinator.installManager(replacementManager)

        let restored = coordinator.applyRecoveredRun(
            manager: submittedManager,
            session: session,
            transcript: recoveredTranscript,
            submittedManagerRevision: submittedRevision
        )

        #expect(!restored)
        #expect(coordinator.manager?.permissionMode == .trustedWrite)
        #expect(model.transcript.map(\.content) == ["recover me"])
    }

    @Test func composerCoordinatorPreservesLiveDraftAndConsumesSubmissionState() {
        let model = ChatComposerModel()
        let coordinator = ChatComposerCoordinator(model: model, storagePaths: nil)
        var selectedID: String? = "session"
        var autosave = false
        coordinator.selectedSessionID = { selectedID }
        coordinator.autoSaveDraftsEnabled = { autosave }
        model.input = "published"

        coordinator.updateSelectedDraft("manual")
        #expect(model.input == "published")
        #expect(coordinator.currentSelectedDraft() == "manual")

        selectedID = "other"
        autosave = true
        coordinator.restore(sessionID: "other")
        #expect(model.input == "")
        model.pendingAttachmentRefs = [AgentMessageAttachmentRef(
            id: "attachment",
            displayName: "file.txt",
            kind: .text,
            byteCount: 1,
            lifecycleStatus: .ready,
            extractionStatus: .extracted,
            manifestRelativePath: "attachments/attachment/manifest.json"
        )]
        coordinator.consumeForSubmission(sessionID: "other")
        #expect(model.input == "")
        #expect(model.pendingAttachmentRefs.isEmpty)
    }

    @Test func composerCoordinatorShutdownPreventsNewToast() {
        let model = ChatComposerModel()
        let coordinator = ChatComposerCoordinator(model: model, storagePaths: nil)
        coordinator.showToast(title: "Before", message: "Visible")
        #expect(model.attachmentToast?.title == "Before")
        coordinator.shutdown()
        coordinator.showToast(title: "After", message: "Ignored")
        #expect(model.attachmentToast?.title == "Before")
    }

    @Test func approvalCoordinatorFiltersAutoApprovedCapabilitiesAndStopsAfterShutdown() {
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: nil)
        coordinator.permissionMode = { .trustedWrite }
        let readable = AgentPendingApproval(requestID: "read", runID: "run", sessionID: "session", capability: .readSession)
        let destructive = AgentPendingApproval(requestID: "delete", runID: "run", sessionID: "session", capability: .deleteGraphObject)

        coordinator.install([readable, destructive])
        #expect(coordinator.activeApprovals(sessionID: "session").map(\.requestID) == ["delete"])

        coordinator.shutdown()
        coordinator.install([])
        #expect(model.pendingApprovals.count == 2)
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

    @Test func sessionCoordinatorSynchronizesUpdatedMessageCountIntoCardSnapshot() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        var session = try fixture.repository.createSession(title: "Count")
        session.messages = (1...3).map { AgentMessage(role: .user, content: "message-\($0)") }
        session = try fixture.repository.saveSession(session)
        let model = ChatSessionListModel()
        let coordinator = ChatSessionCoordinator(model: model, repository: fixture.repository)
        coordinator.installStartupSessions([session], allSessions: [session])
        session.messages.append(AgentMessage(role: .assistant, content: "message-4"))

        coordinator.synchronize(session)

        #expect(model.sessions.first?.messages.count == 4)
        #expect(model.allSessions.first?.messages.count == 4)
        #expect(AgentChatSessionPresentation(session: try #require(model.sessions.first)).messageCount == 4)
    }

    @Test func importedSessionBatchUpdatesListsWithoutChangingSelectionOrLoadingDetail() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let selected = try fixture.repository.createSession(title: "Selected", now: Date(timeIntervalSince1970: 1_000))
        let model = ChatSessionListModel()
        model.selectedSessionID = selected.id
        let coordinator = ChatSessionCoordinator(model: model, repository: fixture.repository)
        coordinator.installStartupSessions([selected], allSessions: [selected])
        var selectionChangeCount = 0
        var detailReloadCount = 0
        coordinator.onSelectionWillChange = { _, _ in selectionChangeCount += 1 }
        coordinator.onReloadSelectedSession = { _, _ in detailReloadCount += 1 }
        var noteGovernance = AgentSessionGovernanceMetadata.default
        noteGovernance.kind = .note
        let olderNote = AgentSession(id: "note-older", title: "Older", createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 2_000), governance: noteGovernance)
        let newerNote = AgentSession(id: "note-newer", title: "Newer", createdAt: Date(timeIntervalSince1970: 3_000), updatedAt: Date(timeIntervalSince1970: 3_000), governance: noteGovernance)

        coordinator.installImportedSessions([olderNote, newerNote])

        #expect(model.allSessions.map(\.id) == [newerNote.id, olderNote.id, selected.id])
        #expect(model.sessions.map(\.id) == [newerNote.id, olderNote.id, selected.id])
        #expect(model.selectedSessionID == selected.id)
        #expect(model.loadingSessionDetailID == nil)
        #expect(selectionChangeCount == 0)
        #expect(detailReloadCount == 0)
    }
}

private struct CoordinatorTestBackend: AgentBackend {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
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
