import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func appPendingApprovalRepositoryResolvesApprovalsWithProductSemantics() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let repository = AppAgentPendingApprovalRepository(store: store)
    try store.upsert(pendingApproval: AgentPendingApproval(
        requestID: "approval-service-approve",
        runID: "run-service",
        sessionID: "session-service",
        capability: .externalNetwork,
        toolName: "web_fetch",
        payloadJSON: "{\"url\":\"https://example.com\"}"
    ))
    try store.upsert(pendingApproval: AgentPendingApproval(
        requestID: "approval-service-deny",
        runID: "run-service",
        sessionID: "session-service",
        capability: .commitGraphWrite,
        toolName: "graph_write_candidate_commit",
        payloadJSON: "{}"
    ))
    try store.upsert(pendingApproval: AgentPendingApproval(
        requestID: "approval-service-cancel",
        runID: "run-service",
        sessionID: "session-service",
        capability: .costlyModelCall,
        toolName: "expensive_model_call",
        payloadJSON: "{}"
    ))

    #expect(try repository.loadPending().count == 3)

    let approved = try repository.approve(requestID: "approval-service-approve", reason: "Allowed read-only fetch")
    let denied = try repository.deny(requestID: "approval-service-deny", reason: "Graph commit not reviewed")
    let cancelled = try repository.cancel(requestID: "approval-service-cancel", reason: "Run cancelled")

    #expect(approved.status == .approved)
    #expect(denied.status == .denied)
    #expect(cancelled.status == .cancelled)
    #expect(try repository.loadPending().isEmpty)
    #expect(try store.agentAuditEvents(runID: "run-service").map(\.decision?.outcome) == [.approved, .denied, .denied])
}
