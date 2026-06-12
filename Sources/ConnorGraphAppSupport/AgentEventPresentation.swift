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
            return item(
                event,
                title: "Tool requested: \(call.name)",
                detail: "Call \(call.id) · Arguments: \(compactJSON(call.argumentsJSON))",
                severity: .info
            )
        case .toolApproved(let call):
            return item(event, title: "Tool approved: \(call.name)", detail: "Call \(call.id) approved for execution.", severity: .success)
        case .toolStarted(let call):
            return item(event, title: "Tool running: \(call.name)", detail: "Call \(call.id) is executing.", severity: .info)
        case .toolFinished(let result):
            return item(
                event,
                title: "Tool finished: \(result.toolName)",
                detail: "Call \(result.toolCallID) · \(trimmedDetail(result.contentText))",
                severity: .success
            )
        case .toolFailed(let failure):
            return item(
                event,
                title: "Tool failed: \(failure.toolName)",
                detail: "Call \(failure.toolCallID) · \(trimmedDetail(failure.message))",
                severity: .error
            )
        case .permissionRequested(let request):
            let toolDetail = request.toolName.map { " · Tool: \($0)" } ?? ""
            return item(
                event,
                title: "Permission requested: \(request.capability.rawValue)",
                detail: "Request \(request.id)\(toolDetail) · Payload: \(compactJSON(request.payloadJSON))",
                severity: .warning
            )
        case .permissionResolved(let decision):
            return item(
                event,
                title: "Permission \(permissionResolutionLabel(decision.outcome)): \(decision.capability.rawValue)",
                detail: "Request \(decision.requestID) · \(trimmedDetail(decision.reason))",
                severity: permissionResolutionSeverity(decision.outcome)
            )
        case .budgetWarning(let warning):
            return item(event, title: "Budget warning", detail: warning.message, severity: .warning)
        case .sessionStatusChanged(let payload):
            return item(event, title: "Session status changed", detail: payload.message, severity: .info)
        case .sessionLabelsChanged(let payload):
            return item(event, title: "Session labels changed", detail: payload.message, severity: .info)
        case .sessionArchived(let payload):
            return item(event, title: "Session archived", detail: payload.message, severity: .warning)
        case .sessionRestored(let payload):
            return item(event, title: "Session restored", detail: payload.message, severity: .success)
        case .artifactCreated(let payload):
            return item(event, title: "Artifact created: \(payload.artifactKind)", detail: payload.message, severity: .success)
        case .sourceRegistryChanged(let payload):
            return item(event, title: "Source registry changed: \(payload.entryID)", detail: payload.message, severity: .info)
        case .skillRegistryChanged(let payload):
            return item(event, title: "Skill registry changed: \(payload.entryID)", detail: payload.message, severity: .info)
        case .automationTriggered(let payload):
            return item(event, title: "Automation triggered: \(payload.trigger)", detail: payload.message, severity: .info)
        case .graphMemoryProposed(let payload):
            return item(event, title: "Graph memory proposed", detail: payload.message, severity: .info)
        case .graphMemoryCommitted(let payload):
            return item(event, title: "Graph memory committed", detail: payload.message, severity: .success)
        case .graphMemoryHeld(let payload):
            return item(event, title: "Graph memory held", detail: payload.message, severity: .warning)
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

    private func permissionResolutionLabel(_ outcome: AgentPermissionOutcome) -> String {
        switch outcome {
        case .approved: "approved"
        case .denied: "denied"
        case .needsApproval: "needs approval"
        }
    }

    private func permissionResolutionSeverity(_ outcome: AgentPermissionOutcome) -> AgentEventPresentationSeverity {
        switch outcome {
        case .approved: .success
        case .denied: .error
        case .needsApproval: .warning
        }
    }

    private func compactJSON(_ json: String) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let compact = try? JSONSerialization.data(withJSONObject: object, options: []),
              let string = String(data: compact, encoding: .utf8)
        else { return trimmedDetail(trimmed) }
        return trimmedDetail(string)
    }

    private func trimmedDetail(_ value: String, maxLength _: Int = 220) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
