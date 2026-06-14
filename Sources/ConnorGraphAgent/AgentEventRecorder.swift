import Foundation
import ConnorGraphCore

public protocol AgentRunEventRepository: Sendable {
    func upsert(agentRun run: AgentRun) throws
    func append(agentEvent event: PersistedAgentEvent) throws
}

public struct AgentEventRecorder: Sendable {
    private let repository: (any AgentRunEventRepository)?
    private let encoder: JSONEncoder

    public init(repository: (any AgentRunEventRepository)? = nil) {
        self.repository = repository
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func recordRun(_ run: AgentRun) throws {
        try repository?.upsert(agentRun: run)
    }

    public func record(_ event: AgentEvent, sequence: Int? = nil) throws {
        guard let runID = event.runID, let sessionID = event.sessionID else { return }
        let payload = try payloadJSON(for: event)
        try repository?.append(agentEvent: PersistedAgentEvent(
            runID: runID,
            sessionID: sessionID,
            kind: event.kind,
            payloadJSON: payload,
            sequence: sequence
        ))
    }

    private func payloadJSON(for event: AgentEvent) throws -> String {
        let data: Data
        switch event {
        case .runStarted(let payload): data = try encoder.encode(payload)
        case .turnStarted(let payload): data = try encoder.encode(payload)
        case .turnCompleted(let payload): data = try encoder.encode(payload)
        case .promptAssembled(let payload): data = try encoder.encode(payload)
        case .textDelta(let payload): data = try encoder.encode(payload)
        case .textComplete(let payload): data = try encoder.encode(payload)
        case .assistantMessageCreated(let payload): data = try encoder.encode(payload)
        case .toolRequested(let payload), .toolApproved(let payload), .toolStarted(let payload): data = try encoder.encode(payload)
        case .toolFinished(let payload): data = try encoder.encode(payload)
        case .toolFailed(let payload): data = try encoder.encode(payload)
        case .permissionRequested(let payload): data = try encoder.encode(payload)
        case .permissionResolved(let payload): data = try encoder.encode(payload)
        case .budgetWarning(let payload): data = try encoder.encode(payload)
        case .sessionStatusChanged(let payload), .sessionLabelsChanged(let payload), .sessionArchived(let payload), .sessionRestored(let payload): data = try encoder.encode(payload)
        case .artifactCreated(let payload): data = try encoder.encode(payload)
        case .sourceRegistryChanged(let payload), .skillRegistryChanged(let payload): data = try encoder.encode(payload)
        case .automationTriggered(let payload): data = try encoder.encode(payload)
        case .graphMemoryProposed(let payload), .graphMemoryCommitted(let payload), .graphMemoryHeld(let payload): data = try encoder.encode(payload)
        case .runFailed(let payload): data = try encoder.encode(payload)
        case .runCompleted(let payload): data = try encoder.encode(payload)
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
