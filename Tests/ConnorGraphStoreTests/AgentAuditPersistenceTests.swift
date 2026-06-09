import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func storePersistsAgentAuditEvents() throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    let run = AgentRun(sessionID: "session-audit", groupID: "group-audit", status: .running)
    try store.upsert(agentRun: run)

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
    try store.recordSync(event)

    let loaded = try store.agentAuditEvents(runID: run.id)
    #expect(loaded.count == 1)
    #expect(loaded.first?.decision?.outcome == .approved)
    #expect(loaded.first?.toolName == "graph_search")
}
