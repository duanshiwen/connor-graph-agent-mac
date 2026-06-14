import Foundation
import ConnorGraphCore

public enum AgentEvent: Sendable, Equatable {
    case runStarted(AgentRunStartedEvent)
    case turnStarted(AgentTurnStartedEvent)
    case turnCompleted(AgentTurnCompletedEvent)
    case textDelta(AgentTextDeltaEvent)
    case textComplete(AgentTextCompleteEvent)
    case assistantMessageCreated(AgentMessage)
    case toolRequested(AgentToolCall)
    case toolApproved(AgentToolCall)
    case toolStarted(AgentToolCall)
    case toolFinished(AgentToolResult)
    case toolFailed(AgentToolFailure)
    case permissionRequested(AgentPermissionRequest)
    case permissionResolved(AgentPermissionDecision)
    case budgetWarning(AgentBudgetWarning)
    case sessionStatusChanged(AgentSessionGovernanceEvent)
    case sessionLabelsChanged(AgentSessionGovernanceEvent)
    case sessionArchived(AgentSessionGovernanceEvent)
    case sessionRestored(AgentSessionGovernanceEvent)
    case artifactCreated(AgentSessionArtifactEvent)
    case sourceRegistryChanged(AgentProductOSRegistryEvent)
    case skillRegistryChanged(AgentProductOSRegistryEvent)
    case automationTriggered(AgentAutomationPlaceholderEvent)
    case graphMemoryProposed(AgentGraphMemoryLifecycleEvent)
    case graphMemoryCommitted(AgentGraphMemoryLifecycleEvent)
    case graphMemoryHeld(AgentGraphMemoryLifecycleEvent)
    case runFailed(AgentRunFailure)
    case runCompleted(AgentRunCompletedEvent)

    public var kind: AgentEventKind {
        switch self {
        case .runStarted: return .runStarted
        case .turnStarted: return .turnStarted
        case .turnCompleted: return .turnCompleted
        case .textDelta: return .textDelta
        case .textComplete: return .textComplete
        case .assistantMessageCreated: return .assistantMessageCreated
        case .toolRequested: return .toolRequested
        case .toolApproved: return .toolApproved
        case .toolStarted: return .toolStarted
        case .toolFinished: return .toolFinished
        case .toolFailed: return .toolFailed
        case .permissionRequested: return .permissionRequested
        case .permissionResolved: return .permissionResolved
        case .budgetWarning: return .budgetWarning
        case .sessionStatusChanged: return .sessionStatusChanged
        case .sessionLabelsChanged: return .sessionLabelsChanged
        case .sessionArchived: return .sessionArchived
        case .sessionRestored: return .sessionRestored
        case .artifactCreated: return .artifactCreated
        case .sourceRegistryChanged: return .sourceRegistryChanged
        case .skillRegistryChanged: return .skillRegistryChanged
        case .automationTriggered: return .automationTriggered
        case .graphMemoryProposed: return .graphMemoryProposed
        case .graphMemoryCommitted: return .graphMemoryCommitted
        case .graphMemoryHeld: return .graphMemoryHeld
        case .runFailed: return .runFailed
        case .runCompleted: return .runCompleted
        }
    }

    public var runID: String? {
        switch self {
        case .runStarted(let event): return event.run.id
        case .turnStarted(let event): return event.runID
        case .turnCompleted(let event): return event.runID
        case .textDelta(let event): return event.runID
        case .textComplete(let event): return event.runID
        case .assistantMessageCreated: return nil
        case .toolRequested(let call), .toolApproved(let call), .toolStarted(let call): return call.runID
        case .toolFinished(let result): return result.runID
        case .toolFailed(let failure): return failure.runID
        case .permissionRequested(let request): return request.runID
        case .permissionResolved(let decision): return decision.runID
        case .budgetWarning(let warning): return warning.runID
        case .sessionStatusChanged(let event), .sessionLabelsChanged(let event), .sessionArchived(let event), .sessionRestored(let event): return event.runID
        case .artifactCreated(let event): return event.runID
        case .sourceRegistryChanged(let event), .skillRegistryChanged(let event): return event.runID
        case .automationTriggered(let event): return event.runID
        case .graphMemoryProposed(let event), .graphMemoryCommitted(let event), .graphMemoryHeld(let event): return event.runID
        case .runFailed(let failure): return failure.runID
        case .runCompleted(let event): return event.run.id
        }
    }

    public var sessionID: String? {
        switch self {
        case .runStarted(let event): return event.run.sessionID
        case .turnStarted(let event): return event.sessionID
        case .turnCompleted(let event): return event.sessionID
        case .textDelta(let event): return event.sessionID
        case .textComplete(let event): return event.sessionID
        case .assistantMessageCreated: return nil
        case .toolRequested(let call), .toolApproved(let call), .toolStarted(let call): return call.sessionID
        case .toolFinished(let result): return result.sessionID
        case .toolFailed(let failure): return failure.sessionID
        case .permissionRequested(let request): return request.sessionID
        case .permissionResolved(let decision): return decision.sessionID
        case .budgetWarning(let warning): return warning.sessionID
        case .sessionStatusChanged(let event), .sessionLabelsChanged(let event), .sessionArchived(let event), .sessionRestored(let event): return event.sessionID
        case .artifactCreated(let event): return event.sessionID
        case .sourceRegistryChanged(let event), .skillRegistryChanged(let event): return event.sessionID
        case .automationTriggered(let event): return event.sessionID
        case .graphMemoryProposed(let event), .graphMemoryCommitted(let event), .graphMemoryHeld(let event): return event.sessionID
        case .runFailed(let failure): return failure.sessionID
        case .runCompleted(let event): return event.run.sessionID
        }
    }
}
