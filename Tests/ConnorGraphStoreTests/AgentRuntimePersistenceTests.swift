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

@Test func storeDeletesOnlyToolCallEventsForCompletedTurn() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let run = AgentRun(sessionID: "session-cleanup", groupID: "default", status: .completed)
    try store.upsert(run: run)
    for (index, kind) in [AgentEventKind.runStarted, .toolStarted, .toolFinished, .runCompleted].enumerated() {
        try store.append(event: PersistedAgentEvent(
            runID: run.id,
            sessionID: run.sessionID,
            kind: kind,
            payloadJSON: "{}",
            sequence: index
        ))
    }

    try store.deleteToolCallEvents(runID: run.id)

    #expect(try store.events(runID: run.id, limit: nil).map(\.kind) == [.runStarted, .runCompleted])
}

@Test func migrationDeletesExistingToolCallEventsFromTerminalRuns() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let completed = AgentRun(sessionID: "completed-session", groupID: "default", status: .completed)
    let running = AgentRun(sessionID: "running-session", groupID: "default", status: .running)
    try store.upsert(run: completed)
    try store.upsert(run: running)
    for run in [completed, running] {
        try store.append(event: PersistedAgentEvent(
            runID: run.id,
            sessionID: run.sessionID,
            kind: .toolFinished,
            payloadJSON: #"{"large":"tool output"}"#
        ))
    }

    try store.migrate()

    #expect(try store.events(runID: completed.id, limit: nil).isEmpty)
    #expect(try store.events(runID: running.id, limit: nil).count == 1)
}
