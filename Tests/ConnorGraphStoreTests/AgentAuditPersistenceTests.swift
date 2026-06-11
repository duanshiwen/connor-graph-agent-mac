import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func storePersistsAgentAuditEvents() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let run = AgentRun(sessionID: "session-audit", groupID: "group-audit", status: .running)
    try store.upsert(run: run)

    let decision = AgentPermissionDecision(
        requestID: "request-1",
        runID: run.id,
        sessionID: run.sessionID,
        capability: .readGraph,
        outcome: .approved,
        reason: "test"
    )
    let event = AgentAuditEvent(
        runID: run.id,
        sessionID: run.sessionID,
        eventType: .permissionDecision,
        capability: .readGraph,
        toolName: "graph_search",
        decision: decision,
        payloadJSON: "{}"
    )
    try store.append(auditEvent: event)

    let loaded = try store.agentAuditEvents(runID: run.id)
    #expect(loaded.count == 1)
    #expect(loaded.first?.decision?.outcome == .approved)
    #expect(loaded.first?.toolName == "graph_search")
}

@Test func storePersistsAgentPendingApprovals() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let approval = AgentPendingApproval(
        id: "approval-1",
        requestID: "permission-tool-1",
        runID: "run-approval",
        sessionID: "session-approval",
        capability: .commitGraphWrite,
        toolName: "graph_write_candidate_commit",
        payloadJSON: "{\"candidate_id\":\"candidate-1\"}",
        status: .pending,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )

    try store.upsert(pendingApproval: approval)

    let byRun = try store.pendingApprovals(runID: "run-approval")
    let byStatus = try store.pendingApprovals(status: .pending)
    let byRequest = try store.pendingApproval(requestID: "permission-tool-1")

    #expect(byRun == [approval])
    #expect(byStatus == [approval])
    #expect(byRequest == approval)
}

@Test func storeResolvesPendingApprovalWithAuditAndTimelineEvent() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let run = AgentRun(id: "run-resolution", sessionID: "session-resolution", groupID: "group-resolution", status: .running)
    try store.upsert(run: run)
    try store.append(event: PersistedAgentEvent(
        id: "event-permission-requested",
        runID: run.id,
        sessionID: run.sessionID,
        kind: .permissionRequested,
        payloadJSON: "{}",
        sequence: 0,
        createdAt: Date(timeIntervalSince1970: 1_000)
    ))
    try store.upsert(pendingApproval: AgentPendingApproval(
        id: "approval-resolution",
        requestID: "permission-tool-resolution",
        runID: run.id,
        sessionID: run.sessionID,
        capability: .commitGraphWrite,
        toolName: "graph_write_candidate_commit",
        payloadJSON: "{\"candidate_id\":\"candidate-1\"}",
        status: .pending,
        createdAt: Date(timeIntervalSince1970: 1_001),
        updatedAt: Date(timeIntervalSince1970: 1_001)
    ))

    let resolved = try store.resolvePendingApproval(
        requestID: "permission-tool-resolution",
        status: .approved,
        reason: "Human approved graph commit",
        actor: "human-reviewer"
    )

    #expect(resolved.status == .approved)
    #expect(resolved.requestID == "permission-tool-resolution")
    #expect(try store.pendingApproval(requestID: "permission-tool-resolution")?.status == .approved)

    let auditEvents = try store.agentAuditEvents(runID: run.id)
    #expect(auditEvents.count == 1)
    #expect(auditEvents.first?.eventType == .permissionDecision)
    #expect(auditEvents.first?.actor == "human-reviewer")
    #expect(auditEvents.first?.capability == .commitGraphWrite)
    #expect(auditEvents.first?.toolName == "graph_write_candidate_commit")
    #expect(auditEvents.first?.decision?.requestID == "permission-tool-resolution")
    #expect(auditEvents.first?.decision?.outcome == .approved)
    #expect(auditEvents.first?.decision?.reason == "Human approved graph commit")

    let timelineEvents = try store.events(runID: run.id)
    #expect(timelineEvents.map(\.kind) == [.permissionRequested, .permissionResolved])
    #expect(timelineEvents.map(\.sequence) == [0, 1])
    #expect(timelineEvents.last?.payloadJSON.contains("permission-tool-resolution") == true)
}
