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

@Test func appPendingApprovalRepositoryPagesAllPendingApprovalsStably() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let repository = AppAgentPendingApprovalRepository(store: store)
    let createdAt = Date(timeIntervalSince1970: 1_000)
    for index in 0..<137 {
        try store.upsert(pendingApproval: AgentPendingApproval(
            id: String(format: "approval-%03d", index),
            requestID: String(format: "request-%03d", index),
            runID: "run-pagination",
            sessionID: "session-pagination",
            capability: .externalNetwork,
            status: .pending,
            createdAt: createdAt.addingTimeInterval(TimeInterval(index / 5)),
            updatedAt: createdAt
        ))
    }

    var cursor: String?
    var loaded: [AgentPendingApproval] = []
    repeat {
        let page = try repository.loadPendingPage(limit: 23, cursor: cursor)
        #expect(page.approvals.count <= 23)
        loaded.append(contentsOf: page.approvals)
        cursor = page.nextCursor
    } while cursor != nil

    #expect(loaded.count == 137)
    #expect(Set(loaded.map(\.id)).count == 137)
    #expect(loaded.map(\.id) == (0..<137).map { String(format: "approval-%03d", $0) })
}

@Test func appPendingApprovalRepositoryPagingToleratesConcurrentResolution() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let repository = AppAgentPendingApprovalRepository(store: store)
    let createdAt = Date(timeIntervalSince1970: 2_000)
    for index in 0..<12 {
        try store.upsert(pendingApproval: AgentPendingApproval(
            id: String(format: "approval-%02d", index),
            requestID: String(format: "request-%02d", index),
            runID: "run-concurrent",
            sessionID: "session-concurrent",
            capability: .externalNetwork,
            createdAt: createdAt,
            updatedAt: createdAt
        ))
    }

    let first = try repository.loadPendingPage(limit: 5)
    _ = try repository.approve(requestID: "request-07", reason: "Resolved while paging")
    let second = try repository.loadPendingPage(limit: 10, cursor: first.nextCursor)

    #expect(first.approvals.map(\.id) == (0..<5).map { String(format: "approval-%02d", $0) })
    #expect(!second.approvals.contains { $0.requestID == "request-07" })
    #expect(Set((first.approvals + second.approvals).map(\.id)).count == 11)
}
