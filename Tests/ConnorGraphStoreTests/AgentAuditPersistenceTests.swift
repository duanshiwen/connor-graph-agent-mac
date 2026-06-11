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
