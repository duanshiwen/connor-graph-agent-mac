import Foundation
import ConnorGraphCore

public enum AgentEventReplayError: Error, Sendable, Equatable, LocalizedError {
    case unsupportedKind(AgentEventKind)

    public var errorDescription: String? {
        switch self {
        case .unsupportedKind(let kind): "Unsupported persisted agent event kind: \(kind.rawValue)"
        }
    }
}

public struct AgentEventReplayer: Sendable {
    private let decoder: JSONDecoder

    public init() {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func replay(_ event: PersistedAgentEvent) throws -> AgentEvent {
        let data = Data(event.payloadJSON.utf8)
        switch event.kind {
        case .runStarted:
            return .runStarted(try decoder.decode(AgentRunStartedEvent.self, from: data))
        case .turnStarted:
            return .turnStarted(try decoder.decode(AgentTurnStartedEvent.self, from: data))
        case .turnCompleted:
            return .turnCompleted(try decoder.decode(AgentTurnCompletedEvent.self, from: data))
        case .textDelta:
            return .textDelta(try decoder.decode(AgentTextDeltaEvent.self, from: data))
        case .textComplete:
            return .textComplete(try decoder.decode(AgentTextCompleteEvent.self, from: data))
        case .assistantMessageCreated:
            return .assistantMessageCreated(try decoder.decode(AgentMessage.self, from: data))
        case .toolRequested:
            return .toolRequested(try decoder.decode(AgentToolCall.self, from: data))
        case .toolApproved:
            return .toolApproved(try decoder.decode(AgentToolCall.self, from: data))
        case .toolStarted:
            return .toolStarted(try decoder.decode(AgentToolCall.self, from: data))
        case .toolFinished:
            return .toolFinished(try decoder.decode(AgentToolResult.self, from: data))
        case .toolFailed:
            return .toolFailed(try decoder.decode(AgentToolFailure.self, from: data))
        case .permissionRequested:
            return .permissionRequested(try decoder.decode(AgentPermissionRequest.self, from: data))
        case .permissionResolved:
            return .permissionResolved(try decoder.decode(AgentPermissionDecision.self, from: data))
        case .budgetWarning:
            return .budgetWarning(try decoder.decode(AgentBudgetWarning.self, from: data))
        case .sessionStatusChanged:
            return .sessionStatusChanged(try decoder.decode(AgentSessionGovernanceEvent.self, from: data))
        case .sessionLabelsChanged:
            return .sessionLabelsChanged(try decoder.decode(AgentSessionGovernanceEvent.self, from: data))
        case .sessionArchived:
            return .sessionArchived(try decoder.decode(AgentSessionGovernanceEvent.self, from: data))
        case .sessionRestored:
            return .sessionRestored(try decoder.decode(AgentSessionGovernanceEvent.self, from: data))
        case .artifactCreated:
            return .artifactCreated(try decoder.decode(AgentSessionArtifactEvent.self, from: data))
        case .sourceRegistryChanged:
            return .sourceRegistryChanged(try decoder.decode(AgentProductOSRegistryEvent.self, from: data))
        case .skillRegistryChanged:
            return .skillRegistryChanged(try decoder.decode(AgentProductOSRegistryEvent.self, from: data))
        case .automationTriggered:
            return .automationTriggered(try decoder.decode(AgentAutomationPlaceholderEvent.self, from: data))
        case .graphMemoryProposed:
            return .graphMemoryProposed(try decoder.decode(AgentGraphMemoryLifecycleEvent.self, from: data))
        case .graphMemoryCommitted:
            return .graphMemoryCommitted(try decoder.decode(AgentGraphMemoryLifecycleEvent.self, from: data))
        case .graphMemoryHeld:
            return .graphMemoryHeld(try decoder.decode(AgentGraphMemoryLifecycleEvent.self, from: data))
        case .runFailed:
            return .runFailed(try decoder.decode(AgentRunFailure.self, from: data))
        case .runCompleted:
            return .runCompleted(try decoder.decode(AgentRunCompletedEvent.self, from: data))
        }
    }

    public func replay(_ events: [PersistedAgentEvent]) throws -> [AgentEvent] {
        try events.map(replay)
    }
}
