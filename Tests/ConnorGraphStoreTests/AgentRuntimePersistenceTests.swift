import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func storePersistsAgentRunAndEvents() throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()

    var run = AgentRun(sessionID: "session-1", groupID: "group-1", status: .running, model: "test-model", metadata: ["purpose": "test"])
    try store.upsert(agentRun: run)
    try store.append(agentEvent: PersistedAgentEvent(
        runID: run.id,
        sessionID: run.sessionID,
        kind: .runStarted,
        payloadJSON: "{\"ok\":true}"
    ))

    run.status = .completed
    run.completedAt = Date()
    try store.upsert(agentRun: run)

    let loaded = try #require(store.agentRun(id: run.id))
    #expect(loaded.status == .completed)
    #expect(loaded.model == "test-model")
    #expect(loaded.metadata["purpose"] == "test")
    #expect(try store.agentEvents(runID: run.id).map(\.kind) == [.runStarted])
}

@Test func storePersistsGraphWriteCandidatesWithoutCommittingGraph() throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()

    let candidate = GraphWriteCandidate(
        groupID: "group-1",
        kind: .createFact,
        proposedByRunID: "run-1",
        proposedByToolCallID: "call-1",
        rationale: "LLM proposed candidate, not committed graph mutation.",
        confidence: 0.72,
        payloadJSON: "{\"fact\":\"A relates to B\"}",
        sourceEpisodeIDs: ["episode-1"],
        relatedNodeIDs: ["node-a", "node-b"]
    )
    try store.upsert(graphWriteCandidate: candidate)

    let loaded = try #require(store.graphWriteCandidate(id: candidate.id))
    #expect(loaded.status == .pendingValidation)
    #expect(loaded.sourceEpisodeIDs == ["episode-1"])
    #expect(loaded.relatedNodeIDs == ["node-a", "node-b"])
}
