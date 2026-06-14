import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@Test func agentEventPresentationRestorerKeepsUnsequencedLoopEventsWhenJournalEventsAreSequenced() throws {
    let runID = "run-activity-restore"
    let sessionID = "session-activity-restore"
    let baseDate = try #require(ISO8601DateFormatter().date(from: "2026-06-13T12:00:00Z"))
    let run = AgentRun(
        id: runID,
        sessionID: sessionID,
        groupID: "default",
        status: .running,
        startedAt: baseDate,
        model: "test-model"
    )
    let completedRun = AgentRun(
        id: runID,
        sessionID: sessionID,
        groupID: "default",
        status: .completed,
        startedAt: baseDate,
        completedAt: baseDate.addingTimeInterval(4),
        model: "test-model"
    )

    let events: [PersistedAgentEvent] = [
        persisted(
            .runStarted(AgentRunStartedEvent(run: run)),
            id: "journal-started",
            sequence: 0,
            createdAt: baseDate
        ),
        persisted(
            .toolRequested(AgentToolCall(
                id: "tool-1",
                runID: runID,
                sessionID: sessionID,
                name: "web_search",
                argumentsJSON: "{\"query\":\"Uruguay continent\"}"
            )),
            id: "loop-tool-requested",
            sequence: nil,
            createdAt: baseDate.addingTimeInterval(1)
        ),
        persisted(
            .toolFinished(AgentToolResult(
                id: "result-1",
                runID: runID,
                sessionID: sessionID,
                toolCallID: "tool-1",
                toolName: "web_search",
                contentText: "Uruguay is in South America."
            )),
            id: "loop-tool-finished",
            sequence: nil,
            createdAt: baseDate.addingTimeInterval(2)
        ),
        persisted(
            .textComplete(AgentTextCompleteEvent(
                runID: runID,
                sessionID: sessionID,
                text: "乌拉圭位于南美洲。"
            )),
            id: "loop-text-complete",
            sequence: nil,
            createdAt: baseDate.addingTimeInterval(3)
        ),
        persisted(
            .runCompleted(AgentRunCompletedEvent(run: completedRun)),
            id: "journal-completed",
            sequence: 1,
            createdAt: baseDate.addingTimeInterval(4)
        )
    ]

    let presentations = AgentEventPresentationRestorer().presentations(from: events)

    #expect(presentations.map(\.title) == [
        "Run started",
        "Tool requested: web_search",
        "Tool finished: web_search",
        "Answer completed",
        "Run completed"
    ])
}

private func persisted(_ event: AgentEvent, id: String, sequence: Int?, createdAt: Date) -> PersistedAgentEvent {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let payloadJSON: String
    switch event {
    case .runStarted(let payload): payloadJSON = encode(payload, using: encoder)
    case .turnStarted(let payload): payloadJSON = encode(payload, using: encoder)
    case .turnCompleted(let payload): payloadJSON = encode(payload, using: encoder)
    case .promptAssembled(let payload): payloadJSON = encode(payload, using: encoder)
    case .textDelta(let payload): payloadJSON = encode(payload, using: encoder)
    case .textComplete(let payload): payloadJSON = encode(payload, using: encoder)
    case .assistantMessageCreated(let payload): payloadJSON = encode(payload, using: encoder)
    case .toolRequested(let payload), .toolApproved(let payload), .toolStarted(let payload): payloadJSON = encode(payload, using: encoder)
    case .toolFinished(let payload): payloadJSON = encode(payload, using: encoder)
    case .toolFailed(let payload): payloadJSON = encode(payload, using: encoder)
    case .permissionRequested(let payload): payloadJSON = encode(payload, using: encoder)
    case .permissionResolved(let payload): payloadJSON = encode(payload, using: encoder)
    case .budgetWarning(let payload): payloadJSON = encode(payload, using: encoder)
    case .sessionStatusChanged(let payload), .sessionLabelsChanged(let payload), .sessionArchived(let payload), .sessionRestored(let payload): payloadJSON = encode(payload, using: encoder)
    case .artifactCreated(let payload): payloadJSON = encode(payload, using: encoder)
    case .sourceRegistryChanged(let payload), .skillRegistryChanged(let payload): payloadJSON = encode(payload, using: encoder)
    case .automationTriggered(let payload): payloadJSON = encode(payload, using: encoder)
    case .graphMemoryProposed(let payload), .graphMemoryCommitted(let payload), .graphMemoryHeld(let payload): payloadJSON = encode(payload, using: encoder)
    case .runFailed(let payload): payloadJSON = encode(payload, using: encoder)
    case .runCompleted(let payload): payloadJSON = encode(payload, using: encoder)
    }
    return PersistedAgentEvent(
        id: id,
        runID: event.runID ?? "run-activity-restore",
        sessionID: event.sessionID ?? "session-activity-restore",
        kind: event.kind,
        payloadJSON: payloadJSON,
        sequence: sequence,
        createdAt: createdAt
    )
}

private func encode<T: Encodable>(_ value: T, using encoder: JSONEncoder) -> String {
    guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else { return "{}" }
    return json
}
