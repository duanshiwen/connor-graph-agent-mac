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

    @Test func approvalCoordinatorShowsHardGatedApprovalInEveryModeAndStopsAfterShutdown() {
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: nil)
        coordinator.permissionMode = { .trustedWrite }
        let publish = AgentPendingApproval(
            requestID: "publish",
            runID: "run",
            sessionID: "session",
            capability: .publishInteractiveWeb,
            toolName: "interactive_web_publish"
        )

        // 执行模式下硬性门禁请求（publishInteractiveWeb）不会被自动放行：必须展示审批卡，
        // 否则 run 会一直阻塞且用户无处确认。
        coordinator.install([publish])
        #expect(coordinator.activeApprovals(sessionID: "session").map(\.requestID) == ["publish"])
        coordinator.permissionMode = { .allowAll }
        #expect(coordinator.activeApprovals(sessionID: "session").map(\.requestID) == ["publish"])

        coordinator.shutdown()
        coordinator.install([])
        #expect(model.pendingApprovals.count == 1)
    }

    @Test func approvalCoordinatorSurfacesNewlyArrivedPendingApprovals() {
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: nil)
        var surfaced: [[AgentPendingApproval]] = []
        coordinator.onNewPendingApprovals = { surfaced.append($0) }
        let first = AgentPendingApproval(requestID: "approval-1", runID: "run", sessionID: "session", capability: .readSession)
        let second = AgentPendingApproval(requestID: "approval-2", runID: "run", sessionID: "session", capability: .writeWorkspaceFile)

        coordinator.install([first])
        #expect(surfaced.count == 1)
        #expect(surfaced[0].map(\.requestID) == ["approval-1"])

        // 同一批请求再次加载（例如刷新）不应重复提示。
        coordinator.install([first])
        #expect(surfaced.count == 1)

        // 只有新到达的请求才提示。
        coordinator.install([first, second])
        #expect(surfaced.count == 2)
        #expect(surfaced[1].map(\.requestID) == ["approval-2"])
    }

    @Test func approvalCoordinatorSurfacesPendingApprovalsInExecutionModeWithoutSilentAutoApprove() {
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: nil)
        coordinator.permissionMode = { .trustedWrite }
        var surfaced: [[AgentPendingApproval]] = []
        coordinator.onNewPendingApprovals = { surfaced.append($0) }
        let approval = AgentPendingApproval(
            requestID: "publish",
            runID: "run",
            sessionID: "session",
            capability: .publishInteractiveWeb,
            toolName: "interactive_web_publish"
        )

        // 执行模式下硬性门禁请求（publishInteractiveWeb）仍然到达待审批状态：
        // 必须通知外层并展示卡片，加载本身不得静默自动批准（run 侧策略没有放行它，
        // App 侧不能替用户决定）。
        coordinator.install([approval])
        #expect(surfaced.count == 1)
        #expect(surfaced[0].map(\.requestID) == ["publish"])
        #expect(coordinator.activeApprovals(sessionID: "session").map(\.requestID) == ["publish"])
        #expect(model.pendingApprovals.count == 1)
    }

    @Test func permissionModeSwitchToExecutionAutoApprovesPendingApprovals() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let approval = AgentPendingApproval(
            requestID: "switch-exec",
            runID: "run",
            sessionID: "session",
            capability: .mutateCalendar
        )
        try fixture.approvalRepository.store.upsert(pendingApproval: approval)
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: fixture.approvalRepository)
        coordinator.permissionMode = { .askToWrite }
        let resolvedStatuses = ResolvedApprovalStatusBox()
        let backend = AnyAgentBackend(
            chat: { _ in AsyncThrowingStream { _ in } },
            resolveApproval: { _, status, _, _ in resolvedStatuses.append(status) }
        )
        coordinator.backendForApproval = { _ in backend }
        coordinator.install([approval])
        #expect(coordinator.activeApprovals(sessionID: "session").count == 1)

        // 用户主动切到“执行”模式：已挂起的待审批请求按新模式自动放行。
        coordinator.permissionMode = { .trustedWrite }
        coordinator.permissionModeDidChange()
        for _ in 0..<50 where resolvedStatuses.values.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(resolvedStatuses.values == [.approved])
        let persisted = try #require(fixture.approvalRepository.load(runID: approval.runID).first)
        #expect(persisted.status == .approved)
    }

    @Test func approvalCoordinatorAutoApprovesOrdinaryPendingApprovalsOnLoadInExecutionMode() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let approval = AgentPendingApproval(
            requestID: "auto-exec-load",
            runID: "run",
            sessionID: "session",
            capability: .mutateCalendar
        )
        try fixture.approvalRepository.store.upsert(pendingApproval: approval)
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: fixture.approvalRepository)
        coordinator.permissionMode = { .trustedWrite }
        let resolvedStatuses = ResolvedApprovalStatusBox()
        let backend = AnyAgentBackend(
            chat: { _ in AsyncThrowingStream { _ in } },
            resolveApproval: { _, status, _, _ in resolvedStatuses.append(status) }
        )
        coordinator.backendForApproval = { _ in backend }

        // 执行模式下加载待审批列表即自动放行普通权限：不展示卡片，直接批准并恢复 run。
        coordinator.install([approval])
        #expect(coordinator.activeApprovals(sessionID: "session").isEmpty)

        for _ in 0..<50 where resolvedStatuses.values.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(resolvedStatuses.values == [.approved])
        let persisted = try #require(fixture.approvalRepository.load(runID: approval.runID).first)
        #expect(persisted.status == .approved)
    }

    @Test func approvalCoordinatorDoesNotAutoApproveHardGatedApprovalOnLoadInExecutionMode() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let approval = AgentPendingApproval(
            requestID: "hard-gate-load",
            runID: "run",
            sessionID: "session",
            capability: .publishInteractiveWeb,
            toolName: "interactive_web_publish"
        )
        try fixture.approvalRepository.store.upsert(pendingApproval: approval)
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: fixture.approvalRepository)
        coordinator.permissionMode = { .trustedWrite }
        let resolvedStatuses = ResolvedApprovalStatusBox()
        let backend = AnyAgentBackend(
            chat: { _ in AsyncThrowingStream { _ in } },
            resolveApproval: { _, status, _, _ in resolvedStatuses.append(status) }
        )
        coordinator.backendForApproval = { _ in backend }

        // 执行模式下硬性门禁请求即使有在线 backend 也绝不自动放行：保持待审批并展示卡片。
        coordinator.install([approval])
        #expect(coordinator.activeApprovals(sessionID: "session").map(\.requestID) == [approval.requestID])
        try await Task.sleep(for: .milliseconds(100))
        #expect(resolvedStatuses.values.isEmpty)
        let persisted = try #require(fixture.approvalRepository.load(runID: approval.runID).first)
        #expect(persisted.status == .pending)
    }

    @Test func approvalCoordinatorDoesNotAutoApproveMailSendApprovalOnLoadInExecutionMode() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let approval = AgentPendingApproval(
            requestID: "mail-hard-gate-load",
            runID: "run",
            sessionID: "session",
            capability: .sendMail,
            toolName: "mail_send_draft"
        )
        try fixture.approvalRepository.store.upsert(pendingApproval: approval)
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: fixture.approvalRepository)
        coordinator.permissionMode = { .trustedWrite }
        let resolvedStatuses = ResolvedApprovalStatusBox()
        let backend = AnyAgentBackend(
            chat: { _ in AsyncThrowingStream { _ in } },
            resolveApproval: { _, status, _, _ in resolvedStatuses.append(status) }
        )
        coordinator.backendForApproval = { _ in backend }

        // 发送邮件是硬性门禁：即使执行模式加载待审批列表，也必须保留审批卡片等待用户确认。
        coordinator.install([approval])
        #expect(coordinator.activeApprovals(sessionID: "session").map(\.requestID) == [approval.requestID])
        try await Task.sleep(for: .milliseconds(100))
        #expect(resolvedStatuses.values.isEmpty)
        let persisted = try #require(fixture.approvalRepository.load(runID: approval.runID).first)
        #expect(persisted.status == .pending)
    }

    @Test func approvalCoordinatorCancelsPersistedApprovalsWhenRunStops() throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let approval = AgentPendingApproval(
            requestID: "request-stop",
            runID: "run-stop",
            sessionID: "session-stop",
            capability: .writeWorkspaceFile
        )
        try fixture.approvalRepository.store.upsert(pendingApproval: approval)
        let model = ChatApprovalModel()
        model.pendingApprovals = [approval]
        let coordinator = ChatApprovalCoordinator(model: model, repository: fixture.approvalRepository)

        let cancelledCount = coordinator.cancelPendingApprovals(runID: approval.runID, reason: "cancelled by user")

        #expect(cancelledCount == 1)
        #expect(model.pendingApprovals.isEmpty)
        let persisted = try #require(fixture.approvalRepository.load(runID: approval.runID).first)
        #expect(persisted.status == .cancelled)
        let audit = try fixture.approvalRepository.store.agentAuditEvents(runID: approval.runID)
        #expect(audit.last?.eventType == .permissionDecision)
        #expect(audit.last?.actor == "run-cancellation")
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
        coordinator.onReloadSelectedSession = { _, _, _, _ in detailReloadCount += 1 }
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

    @Test func approvalCoordinatorRevealsHiddenPendingApprovalWhenSwitchingToAskMode() {
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: nil)
        coordinator.permissionMode = { .trustedWrite }
        let approval = AgentPendingApproval(
            requestID: "ordinary-request",
            runID: "run",
            sessionID: "session",
            capability: .writeWorkspaceFile
        )

        // 执行模式下普通权限请求由自动放行策略覆盖：不展示审批卡片（连续自动审批语义），
        // run 侧策略引擎会直接放行，不会让这类请求滞留待审批。
        coordinator.install([approval])
        #expect(coordinator.activeApprovals(sessionID: "session").isEmpty)

        // 用户切到“询问”模式：同一请求必须立即出现在审批面板，
        // 否则 run 真正阻塞时（例如先切换模式、后执行任务）用户无处确认。
        coordinator.permissionMode = { .askToWrite }
        #expect(coordinator.activeApprovals(sessionID: "session").map(\.requestID) == ["ordinary-request"])
    }

    @Test func approvalCoordinatorReloadSurfacesHardGatedApprovalInExecutionMode() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.cleanup() }
        let approval = AgentPendingApproval(
            requestID: "publish-reload",
            runID: "run",
            sessionID: "session",
            capability: .publishInteractiveWeb,
            toolName: "interactive_web_publish"
        )
        try fixture.approvalRepository.store.upsert(pendingApproval: approval)
        let model = ChatApprovalModel()
        let coordinator = ChatApprovalCoordinator(model: model, repository: fixture.approvalRepository)
        coordinator.permissionMode = { .trustedWrite }
        let resolvedStatuses = ResolvedApprovalStatusBox()
        let backend = AnyAgentBackend(
            chat: { _ in AsyncThrowingStream { _ in } },
            resolveApproval: { _, status, _, _ in resolvedStatuses.append(status) }
        )
        coordinator.backendForApproval = { _ in backend }
        var surfaced: [[AgentPendingApproval]] = []
        coordinator.onNewPendingApprovals = { surfaced.append($0) }

        // 模拟真实运行流：run 侧把硬性门禁请求写入待审批存储，客户端 reload 拉取。
        // 执行模式下该请求必须出现在审批面板、触发外层通知，且绝不被自动放行。
        coordinator.reload()
        for _ in 0..<50 where model.pendingApprovals.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.activeApprovals(sessionID: "session").map(\.requestID) == ["publish-reload"])
        #expect(surfaced.flatMap { $0.map(\.requestID) }.contains("publish-reload"))
        #expect(resolvedStatuses.values.isEmpty)
        let persisted = try #require(fixture.approvalRepository.load(runID: approval.runID).first)
        #expect(persisted.status == .pending)
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
    let approvalRepository: AppAgentPendingApprovalRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("chat-runtime-coordinator-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: directory)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        let graphRepository = try AppGraphRepository.bootstrap(paths: paths)
        repository = AppChatSessionRepository(store: graphRepository.store, storagePaths: paths)
        approvalRepository = AppAgentPendingApprovalRepository(store: graphRepository.store)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

/// @Sendable 闭包内记录审批结果的线程安全容器（测试用）。
private final class ResolvedApprovalStatusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AgentPendingApprovalStatus] = []

    var values: [AgentPendingApprovalStatus] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ status: AgentPendingApprovalStatus) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(status)
    }
}
