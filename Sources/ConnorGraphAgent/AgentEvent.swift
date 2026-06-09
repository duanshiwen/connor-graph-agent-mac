import Foundation
import ConnorGraphCore

public enum AgentEvent: Sendable, Equatable {
    case runStarted(AgentRunStartedEvent)
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
    case runFailed(AgentRunFailure)
    case runCompleted(AgentRunCompletedEvent)

    public var kind: AgentEventKind {
        switch self {
        case .runStarted: return .runStarted
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
        case .runFailed: return .runFailed
        case .runCompleted: return .runCompleted
        }
    }

    public var runID: String? {
        switch self {
        case .runStarted(let event): return event.run.id
        case .textDelta(let event): return event.runID
        case .textComplete(let event): return event.runID
        case .assistantMessageCreated: return nil
        case .toolRequested(let call), .toolApproved(let call), .toolStarted(let call): return call.runID
        case .toolFinished(let result): return result.runID
        case .toolFailed(let failure): return failure.runID
        case .permissionRequested(let request): return request.runID
        case .permissionResolved(let decision): return decision.runID
        case .budgetWarning(let warning): return warning.runID
        case .runFailed(let failure): return failure.runID
        case .runCompleted(let event): return event.run.id
        }
    }

    public var sessionID: String? {
        switch self {
        case .runStarted(let event): return event.run.sessionID
        case .textDelta(let event): return event.sessionID
        case .textComplete(let event): return event.sessionID
        case .assistantMessageCreated: return nil
        case .toolRequested(let call), .toolApproved(let call), .toolStarted(let call): return call.sessionID
        case .toolFinished(let result): return result.sessionID
        case .toolFailed(let failure): return failure.sessionID
        case .permissionRequested(let request): return request.sessionID
        case .permissionResolved(let decision): return decision.sessionID
        case .budgetWarning(let warning): return warning.sessionID
        case .runFailed(let failure): return failure.sessionID
        case .runCompleted(let event): return event.run.sessionID
        }
    }
}
