import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private struct SessionOSAnswerBackend: AgentBackend {
    var answer: String = "Session OS answer"

    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let run = AgentRun(
                id: request.runID,
                sessionID: request.sessionID,
                groupID: request.groupID,
                status: .running,
                model: "session-os-test-backend",
                metadata: ["runtime": "session-os-test"]
            )
            continuation.yield(.runStarted(AgentRunStartedEvent(run: run)))
            continuation.yield(.textComplete(AgentTextCompleteEvent(
                runID: request.runID,
                sessionID: request.sessionID,
                text: answer
            )))
            var completed = run
            completed.status = .completed
            completed.completedAt = Date()
            continuation.yield(.runCompleted(AgentRunCompletedEvent(run: completed)))
            continuation.finish()
        }
    }
}

private struct SessionOSApprovalBackend: AgentBackend {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.permissionRequested(AgentPermissionRequest(
                runID: request.runID,
                sessionID: request.sessionID,
                capability: .commitGraphWrite,
                toolName: "write_file",
                payloadJSON: "{}"
            )))
            continuation.finish()
        }
    }
}

private func makeSessionOSStore(_ name: String = UUID().uuidString) throws -> SQLiteGraphKernelStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
    let store = try SQLiteGraphKernelStore(path: url.path)
    try store.migrate()
    return store
}

@Test func sessionOSPersistsPendingPlansBranchesAndRestoreSnapshot() throws {
    let store = try makeSessionOSStore()
    let repository = AppChatSessionRepository(store: store)
    let source = AgentSession(id: "session-os-source", title: "Source")
    try repository.saveSession(source)

    let plan = try repository.createPendingPlan(
        sessionID: source.id,
        title: "Commercial Train 1 Plan",
        markdownPath: "/tmp/plan.md",
        contentReference: "plans/commercial-train-1.md"
    )
    let loadedPlans = try repository.loadPendingPlans(sessionID: source.id, status: .waitingForApproval)
    #expect(loadedPlans.map(\.id) == [plan.id])

    let accepted = try repository.resolvePendingPlan(id: plan.id, status: .accepted, reason: "approved for execution")
    #expect(accepted.status == .accepted)
    #expect(accepted.resolvedAt != nil)
    #expect(accepted.resolutionReason == "human-reviewer: approved for execution")

    let branch = try repository.branchSession(
        sourceSessionID: source.id,
        title: "Source Branch",
        reason: "explore alternate session path"
    )
    let branchRecords = try repository.loadBranchRecords(sourceSessionID: source.id)
    #expect(branch.title == "Source Branch")
    #expect(branchRecords.count == 1)
    #expect(branchRecords.first?.targetSessionID == branch.id)

    let queuedRun = AgentRun(id: "queued-run", sessionID: source.id, groupID: "default", status: .queued)
    try repository.saveRun(queuedRun)
    let snapshot = try repository.restoreSnapshot(sessionID: source.id)
    #expect(snapshot.activeRuns.map(\.id).contains("queued-run"))
    #expect(snapshot.pendingPlans.isEmpty)
}

@Test func nativeSessionManagerRecordsRunLifecycleJournalAndHydratesState() async throws {
    let store = try makeSessionOSStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "session-os-manager", title: "Session OS Manager")
    try repository.saveSession(session)
    var manager = NativeSessionManager(
        backend: SessionOSAnswerBackend(),
        sessionRepository: repository,
        session: session
    )

    let response = try await manager.submit("Make the session durable")
    let runID = try #require(manager.runtimeState.lastRunID)
    let run = try #require(try repository.loadRun(id: runID))
    let journal = try repository.loadRecentJournalEvents(sessionID: session.id, limit: 20)

    #expect(response.assistantMessage?.content == "Session OS answer")
    #expect(run.status == .completed)
    #expect(run.metadata["user_message_id"] != nil)
    #expect(journal.contains { $0.kind == .runStarted })
    #expect(journal.map(\.kind).contains(AgentEventKind.runCompleted))

    var restored = NativeSessionManager(
        backend: SessionOSAnswerBackend(),
        sessionRepository: repository,
        session: try #require(try repository.loadSession(id: session.id))
    )
    let snapshot = try restored.hydrateRuntimeState()
    #expect(snapshot.activeRuns.isEmpty)
    #expect(restored.runtimeState.isProcessing == false)
}

@Test func nativeSessionManagerPersistsPendingApprovalForRestore() async throws {
    let store = try makeSessionOSStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "session-os-approval", title: "Session OS Approval")
    try repository.saveSession(session)
    var manager = NativeSessionManager(
        backend: SessionOSApprovalBackend(),
        sessionRepository: repository,
        session: session,
        pendingApprovalRepository: store
    )

    _ = try await manager.submit("Request approval")
    let runID = try #require(manager.runtimeState.lastRunID)
    let run = try #require(try repository.loadRun(id: runID))
    let approvals = try repository.loadPendingApprovals(limit: 20).filter { $0.sessionID == session.id }
    let snapshot = try repository.restoreSnapshot(sessionID: session.id)

    #expect(run.status == .completed || run.status == .waitingForApproval)
    #expect(approvals.count == 1)
    #expect(snapshot.pendingApprovalCount == 1)
}

@Test func sessionGovernanceFanoutWritesJournalEvents() throws {
    let store = try makeSessionOSStore()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "session-os-governance", title: "Governance")
    try repository.saveSession(session)

    _ = try repository.setStatus(sessionID: session.id, status: .inProgress)
    _ = try repository.setLabels(sessionID: session.id, labels: [AgentSessionLabel(id: "project", value: "graph-agent")])
    _ = try repository.archive(sessionID: session.id)
    _ = try repository.restore(sessionID: session.id)

    let events = try repository.loadRecentJournalEvents(sessionID: session.id, limit: 20)
    #expect(events.map(\.kind).contains(AgentEventKind.sessionStatusChanged))
    #expect(events.map(\.kind).contains(AgentEventKind.sessionLabelsChanged))
    #expect(events.map(\.kind).contains(AgentEventKind.sessionArchived))
    #expect(events.map(\.kind).contains(AgentEventKind.sessionRestored))
}
