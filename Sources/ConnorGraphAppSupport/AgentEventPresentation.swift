import Foundation
import ConnorGraphAgent

public enum AgentEventPresentationSeverity: String, Codable, Sendable, Equatable {
    case info
    case success
    case warning
    case error
}

public struct AgentEventPresentation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var title: String
    public var detail: String
    public var severity: AgentEventPresentationSeverity
    public var runID: String?
    public var sessionID: String?

    public init(
        id: String = UUID().uuidString,
        kind: String,
        title: String,
        detail: String,
        severity: AgentEventPresentationSeverity,
        runID: String?,
        sessionID: String?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.severity = severity
        self.runID = runID
        self.sessionID = sessionID
    }
}

public struct AgentEventPresenter: Sendable {
    public init() {}

    public func presentation(for event: AgentEvent) -> AgentEventPresentation {
        switch event {
        case .runStarted(let payload):
            return item(event, title: "Run started", detail: "Model: \(payload.run.model ?? "unknown")", severity: .info)
        case .textDelta(let payload):
            return item(event, title: "Assistant is writing", detail: payload.text, severity: .info)
        case .textComplete(let payload):
            return item(event, title: "Answer completed", detail: payload.text, severity: .success)
        case .assistantMessageCreated(let message):
            return item(event, title: "Assistant message saved", detail: message.content, severity: .success)
        case .toolRequested(let call):
            return item(event, title: "Tool requested", detail: call.name, severity: .info)
        case .toolApproved(let call):
            return item(event, title: "Tool approved", detail: call.name, severity: .success)
        case .toolStarted(let call):
            return item(event, title: "Tool started", detail: call.name, severity: .info)
        case .toolFinished(let result):
            return item(event, title: "Tool finished", detail: result.contentText, severity: .success)
        case .toolFailed(let failure):
            return item(event, title: "Tool failed", detail: failure.message, severity: .error)
        case .permissionRequested(let request):
            return item(event, title: "Permission requested", detail: request.capability.rawValue, severity: .warning)
        case .permissionResolved(let decision):
            let severity: AgentEventPresentationSeverity = decision.outcome == .approved ? .success : .warning
            return item(event, title: "Permission \(decision.outcome.rawValue)", detail: decision.reason, severity: severity)
        case .budgetWarning(let warning):
            return item(event, title: "Budget warning", detail: warning.message, severity: .warning)
        case .runFailed(let failure):
            return item(event, title: "Run failed", detail: failure.message, severity: .error)
        case .runCompleted:
            return item(event, title: "Run completed", detail: "The agent run finished successfully.", severity: .success)
        }
    }

    private func item(_ event: AgentEvent, title: String, detail: String, severity: AgentEventPresentationSeverity) -> AgentEventPresentation {
        AgentEventPresentation(
            kind: event.kind.rawValue,
            title: title,
            detail: detail,
            severity: severity,
            runID: event.runID,
            sessionID: event.sessionID
        )
    }
}
