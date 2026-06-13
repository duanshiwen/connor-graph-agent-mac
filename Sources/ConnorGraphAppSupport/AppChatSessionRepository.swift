import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public enum AppChatSessionRepositoryError: Error, Equatable, CustomStringConvertible {
    case sessionNotFound(String)

    public var description: String {
        switch self {
        case .sessionNotFound(let id): "sessionNotFound: \(id)"
        }
    }
}

public struct AppChatSessionRepository: Sendable {
    public var store: SQLiteGraphKernelStore
    public var storagePaths: AppStoragePaths?
    public var governanceConfig: AppSessionGovernanceConfig

    public init(store: SQLiteGraphKernelStore, storagePaths: AppStoragePaths? = nil, governanceConfig: AppSessionGovernanceConfig = .default) {
        self.store = store
        self.storagePaths = storagePaths
        self.governanceConfig = governanceConfig
    }

    public func loadRecentSessions(limit: Int = 50, includeArchived: Bool = false) throws -> [AgentSession] {
        try store.recentSessions(limit: limit, includeArchived: includeArchived)
    }

    public func loadSessions(filter: AgentSessionListFilter, limit: Int = 100) throws -> [AgentSession] {
        switch filter {
        case .inbox:
            try store.recentSessions(limit: limit, includeArchived: false)
        case .archived:
            try store.sessions(archived: true, limit: limit)
        case .status(let status):
            try store.sessions(status: status, archived: false, limit: limit)
        case .label(let labelID):
            try store.sessions(labelID: labelID, archived: false, limit: limit)
        case .all:
            try store.recentSessions(limit: limit, includeArchived: true)
        }
    }

    public func loadSession(id: String) throws -> AgentSession? {
        try store.session(id: id)
    }

    public func makeNewSession(title: String = "New Chat", now: Date = Date()) throws -> AgentSession {
        let session = AgentSession(id: UUID().uuidString, title: title, messages: [], createdAt: now, updatedAt: now, governance: .default)
        try store.upsertSession(session)
        _ = try storagePaths?.ensureSessionArtifactDirectories(sessionID: session.id)
        return session
    }

    public func createSession(title: String = "New Chat", now: Date = Date()) throws -> AgentSession {
        try makeNewSession(title: title, now: now)
    }

    @discardableResult
    public func saveSession(_ session: AgentSession, previousMessageCount: Int = 0) throws -> AgentSession {
        try store.upsertSession(session)
        _ = try storagePaths?.ensureSessionArtifactDirectories(sessionID: session.id)
        return session
    }

    @discardableResult
    public func updateGovernance(sessionID: String, mutate: (inout AgentSessionGovernanceMetadata) throws -> Void) throws -> AgentSession {
        guard var session = try loadSession(id: sessionID) else { throw AppChatSessionRepositoryError.sessionNotFound(sessionID) }
        var governance = session.governance
        try mutate(&governance)
        for label in governance.labels { try governanceConfig.validate(label: label) }
        session.governance = governance
        session.updatedAt = Date()
        try store.upsertSession(session)
        return session
    }

    @discardableResult
    public func setStatus(sessionID: String, status: AgentSessionStatus) throws -> AgentSession {
        let updated = try updateGovernance(sessionID: sessionID) { governance in
            governance.status = status
            if status == .archived {
                governance.isArchived = true
                governance.archivedAt = Date()
            }
        }
        try appendJournalEvent(runID: UUID().uuidString, sessionID: sessionID, kind: .sessionStatusChanged, action: "session_status_changed", message: "Session status changed to \(status.rawValue)", metadata: ["status": status.rawValue])
        return updated
    }

    @discardableResult
    public func setLabels(sessionID: String, labels: [AgentSessionLabel]) throws -> AgentSession {
        let updated = try updateGovernance(sessionID: sessionID) { governance in governance.labels = labels }
        try appendJournalEvent(runID: UUID().uuidString, sessionID: sessionID, kind: .sessionLabelsChanged, action: "session_labels_changed", message: "Session labels changed", metadata: ["labels": labels.map(\.stableID).joined(separator: ",")])
        return updated
    }

    @discardableResult
    public func toggleFlag(sessionID: String) throws -> AgentSession {
        try updateGovernance(sessionID: sessionID) { governance in governance.isFlagged.toggle() }
    }

    @discardableResult
    public func archive(sessionID: String, now: Date = Date()) throws -> AgentSession {
        let updated = try updateGovernance(sessionID: sessionID) { governance in
            governance.isArchived = true
            governance.status = .archived
            governance.archivedAt = now
        }
        try appendJournalEvent(runID: UUID().uuidString, sessionID: sessionID, kind: .sessionArchived, action: "session_archived", message: "Session archived", metadata: ["status": AgentSessionStatus.archived.rawValue])
        return updated
    }

    @discardableResult
    public func restore(sessionID: String) throws -> AgentSession {
        let updated = try updateGovernance(sessionID: sessionID) { governance in
            governance.isArchived = false
            governance.status = .todo
            governance.archivedAt = nil
        }
        try appendJournalEvent(runID: UUID().uuidString, sessionID: sessionID, kind: .sessionRestored, action: "session_restored", message: "Session restored", metadata: ["status": AgentSessionStatus.todo.rawValue])
        return updated
    }

    public func artifactDirectories(sessionID: String) throws -> AgentSessionArtifactDirectories? {
        try storagePaths?.ensureSessionArtifactDirectories(sessionID: sessionID)
    }

    public func sessionCapsuleRepository() -> AppSessionCapsuleRepository? {
        guard let storagePaths else { return nil }
        return AppSessionCapsuleRepository(storagePaths: storagePaths)
    }

    public func loadSessionState(sessionID: String) throws -> AppSessionStateSnapshot? {
        try sessionCapsuleRepository()?.loadState(sessionID: sessionID)
    }

    public func saveSessionState(_ state: AppSessionStateSnapshot, sessionID: String) throws {
        try sessionCapsuleRepository()?.saveState(state, sessionID: sessionID)
    }

    public func appendSessionRecord(_ record: AppSessionRecord, sessionID: String) throws {
        try sessionCapsuleRepository()?.appendRecord(record, sessionID: sessionID)
    }

    public func loadSessionRecords(sessionID: String, limit: Int? = nil) throws -> [AppSessionRecord] {
        try sessionCapsuleRepository()?.loadRecords(sessionID: sessionID, limit: limit) ?? []
    }

    public func loadBrowserState(sessionID: String) throws -> AppBrowserStateSnapshot? {
        try sessionCapsuleRepository()?.loadBrowserState(sessionID: sessionID)
    }

    public func saveBrowserState(_ state: AppBrowserStateSnapshot, sessionID: String) throws {
        try sessionCapsuleRepository()?.saveBrowserState(state, sessionID: sessionID)
    }

    @discardableResult
    public func refreshSessionManifest(sessionID: String) throws -> AppSessionManifest? {
        try sessionCapsuleRepository()?.refreshManifest(sessionID: sessionID)
    }

    public func loadActivityTimelineCache(sessionID: String) throws -> [AgentEventPresentation] {
        guard let directories = try storagePaths?.ensureSessionArtifactDirectories(sessionID: sessionID) else { return [] }
        let url = directories.logs.appendingPathComponent("activity-timeline.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([AgentEventPresentation].self, from: data)
    }

    public func saveActivityTimelineCache(sessionID: String, timeline: [AgentEventPresentation]) throws {
        guard let directories = try storagePaths?.ensureSessionArtifactDirectories(sessionID: sessionID) else { return }
        try FileManager.default.createDirectory(at: directories.logs, withIntermediateDirectories: true)
        let url = directories.logs.appendingPathComponent("activity-timeline.json")
        let data = try JSONEncoder().encode(timeline)
        try data.write(to: url, options: [.atomic])
    }


    // MARK: - Session OS

    public func saveRun(_ run: AgentRun) throws {
        try store.upsert(run: run)
    }

    public func loadRun(id: String) throws -> AgentRun? {
        try store.run(id: id)
    }

    public func loadRuns(sessionID: String, statuses: [AgentRunStatus]? = nil, limit: Int = 100) throws -> [AgentRun] {
        try store.runs(sessionID: sessionID, statuses: statuses, limit: limit)
    }

    public func appendJournalEvent(runID: String, sessionID: String, kind: AgentEventKind, action: String, message: String, metadata: [String: String] = [:]) throws {
        try store.appendJournalEvent(
            runID: runID,
            sessionID: sessionID,
            kind: kind,
            payload: SessionOSJournalPayload(action: action, message: message, metadata: metadata)
        )
    }

    public func loadRecentJournalEvents(sessionID: String, limit: Int = 100) throws -> [PersistedAgentEvent] {
        try store.recentEvents(sessionID: sessionID, limit: limit)
    }

    public func loadRunEvents(runID: String, limit: Int = 200) throws -> [PersistedAgentEvent] {
        try store.events(runID: runID, limit: limit)
    }

    public func savePendingApproval(_ approval: AgentPendingApproval) throws {
        try store.upsert(pendingApproval: approval)
    }

    public func loadPendingApprovals(runID: String, limit: Int = 100) throws -> [AgentPendingApproval] {
        try store.pendingApprovals(runID: runID, limit: limit)
    }

    public func loadPendingApprovals(limit: Int = 100) throws -> [AgentPendingApproval] {
        try store.pendingApprovals(status: .pending, limit: limit)
    }

    @discardableResult
    public func createPendingPlan(sessionID: String, title: String, markdownPath: String? = nil, contentReference: String? = nil, now: Date = Date()) throws -> SessionPendingPlan {
        let plan = SessionPendingPlan(
            sessionID: sessionID,
            title: title,
            markdownPath: markdownPath,
            contentReference: contentReference,
            status: .waitingForApproval,
            createdAt: now,
            updatedAt: now
        )
        try store.upsert(pendingPlan: plan)
        try appendJournalEvent(
            runID: plan.id,
            sessionID: sessionID,
            kind: .artifactCreated,
            action: "pending_plan_created",
            message: "Pending plan created: \(title)",
            metadata: ["plan_id": plan.id, "status": plan.status.rawValue]
        )
        return plan
    }

    public func loadPendingPlans(sessionID: String, status: SessionPendingPlanStatus? = nil, limit: Int = 100) throws -> [SessionPendingPlan] {
        try store.pendingPlans(sessionID: sessionID, status: status, limit: limit)
    }

    @discardableResult
    public func resolvePendingPlan(id: String, status: SessionPendingPlanStatus, reason: String, actor: String = "human-reviewer", now: Date = Date()) throws -> SessionPendingPlan {
        let plan = try store.resolvePendingPlan(id: id, status: status, reason: "\(actor): \(reason)", now: now)
        try appendJournalEvent(
            runID: plan.id,
            sessionID: plan.sessionID,
            kind: .artifactCreated,
            action: "pending_plan_\(status.rawValue)",
            message: "Pending plan \(status.rawValue): \(plan.title)",
            metadata: ["plan_id": plan.id, "status": plan.status.rawValue, "actor": actor]
        )
        return plan
    }

    @discardableResult
    public func branchSession(sourceSessionID: String, title: String? = nil, branchPointMessageID: String? = nil, branchPointEventID: String? = nil, reason: String = "session branch", now: Date = Date()) throws -> AgentSession {
        guard let source = try loadSession(id: sourceSessionID) else { throw AppChatSessionRepositoryError.sessionNotFound(sourceSessionID) }
        let target = AgentSession(
            id: UUID().uuidString,
            title: title ?? "Branch: \(source.title)",
            messages: source.messages,
            createdAt: now,
            updatedAt: now,
            governance: source.governance
        )
        try store.upsertSession(target)
        _ = try storagePaths?.ensureSessionArtifactDirectories(sessionID: target.id)
        let record = SessionBranchRecord(
            sourceSessionID: sourceSessionID,
            targetSessionID: target.id,
            branchPointMessageID: branchPointMessageID,
            branchPointEventID: branchPointEventID,
            reason: reason,
            createdAt: now
        )
        try store.upsert(branchRecord: record)
        try appendJournalEvent(
            runID: record.id,
            sessionID: sourceSessionID,
            kind: .artifactCreated,
            action: "session_branched",
            message: "Session branched to \(target.id)",
            metadata: ["branch_id": record.id, "target_session_id": target.id]
        )
        try appendJournalEvent(
            runID: record.id,
            sessionID: target.id,
            kind: .artifactCreated,
            action: "session_branch_created",
            message: "Session branch created from \(sourceSessionID)",
            metadata: ["branch_id": record.id, "source_session_id": sourceSessionID]
        )
        return target
    }

    public func loadBranchRecords(sourceSessionID: String? = nil, targetSessionID: String? = nil, limit: Int = 100) throws -> [SessionBranchRecord] {
        try store.branchRecords(sourceSessionID: sourceSessionID, targetSessionID: targetSessionID, limit: limit)
    }

    public func restoreSnapshot(sessionID: String, now: Date = Date()) throws -> SessionOSRestoreSnapshot {
        let activeRuns = try loadRuns(sessionID: sessionID, statuses: [.queued, .pending, .running, .waitingForApproval], limit: 20)
        let pendingPlans = try loadPendingPlans(sessionID: sessionID, status: .waitingForApproval, limit: 20)
        let pendingApprovalCount = try loadPendingApprovals(limit: 200).filter { $0.sessionID == sessionID }.count
        return SessionOSRestoreSnapshot(
            sessionID: sessionID,
            activeRuns: activeRuns,
            pendingPlans: pendingPlans,
            pendingApprovalCount: pendingApprovalCount,
            restoredAt: now
        )
    }

    public func loadLatestSummary(sessionID: String) throws -> AgentSessionSummary? { nil }

    @discardableResult
    public func saveSummary(_ summary: AgentSessionSummary) throws -> AgentSessionSummary { summary }

    public func summarizeSession<Provider: LLMProvider>(id: String, using summarizer: AgentSessionSummarizer<Provider>) async throws -> AgentSessionSummary {
        try await summarizer.summarize(session: AgentSession(id: id))
    }
}
