import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func storePersistsAgentRunAndEvents() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()

    var run = AgentRun(sessionID: "session-1", groupID: "group-1", status: .running, model: "test-model", metadata: ["purpose": "test"])
    try store.upsert(run: run)
    try store.append(event: PersistedAgentEvent(
        runID: run.id,
        sessionID: run.sessionID,
        kind: .runStarted,
        payloadJSON: "{\"ok\":true}"
    ))

    run.status = .completed
    run.completedAt = Date()
    try store.upsert(run: run)

    let loadedRun = try store.run(id: run.id)
    let loaded = try #require(loadedRun)
    #expect(loaded.status == .completed)
    #expect(loaded.model == "test-model")
    #expect(loaded.metadata["purpose"] == "test")
    #expect(try store.events(runID: run.id).map(\.kind) == [.runStarted])
}

@Test func storeLoadsAllRunEventsWhenLimitIsNil() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()

    let run = AgentRun(sessionID: "session-many-events", groupID: "default", status: .running, model: "test-model")
    try store.upsert(run: run)

    for index in 0..<350 {
        try store.append(event: PersistedAgentEvent(
            runID: run.id,
            sessionID: run.sessionID,
            kind: .toolStarted,
            payloadJSON: "{\"index\":\(index)}",
            sequence: index
        ))
    }

    #expect(try store.events(runID: run.id, limit: 300).count == 300)
    #expect(try store.events(runID: run.id, limit: nil).count == 350)
}
