import Foundation

public struct AgentToolInvocationAssembler: Sendable {
    public init() {}

    public func invocations(from events: [AgentEventPresentation]) -> [AgentToolInvocationPresentation] {
        var orderedCallIDs: [String] = []
        var builders: [String: InvocationBuilder] = [:]

        for event in events {
            guard let activity = event.toolActivity else { continue }
            if builders[activity.callID] == nil {
                orderedCallIDs.append(activity.callID)
                builders[activity.callID] = InvocationBuilder(callID: activity.callID)
            }
            builders[activity.callID]?.merge(event: event, activity: activity)
        }

        return orderedCallIDs.compactMap { builders[$0]?.build() }
    }
}

private struct InvocationBuilder {
    var callID: String
    var runID: String?
    var sessionID: String?
    var toolName: String?
    var semanticKind: AgentToolSemanticKind?
    var phase: AgentToolActivityPhase = .requested
    var severity: AgentEventPresentationSeverity = .info

    var title: String?
    var subtitle: String?
    var target: String?
    var icon: String?

    var argumentsJSON: String?
    var resultJSON: String?
    var outputText: String?
    var errorText: String?

    var requestedEventID: String?
    var approvedEventID: String?
    var startedEventID: String?
    var finishedEventID: String?
    var failedEventID: String?
    var rawEventIDs: [String] = []

    mutating func merge(event: AgentEventPresentation, activity: AgentToolActivityPresentation) {
        rawEventIDs.append(event.id)
        runID = runID ?? event.runID
        sessionID = sessionID ?? event.sessionID
        toolName = preferredToolName(existing: toolName, candidate: activity.rawToolName)
        semanticKind = preferredSemanticKind(existing: semanticKind, candidate: activity.semanticKind)

        if shouldReplaceSummary(with: activity) {
            phase = activity.phase
            severity = activity.severity
            title = activity.title
            subtitle = activity.subtitle
            target = activity.target
            icon = activity.icon
        } else {
            title = title ?? activity.title
            subtitle = subtitle ?? activity.subtitle
            target = target ?? activity.target
            icon = icon ?? activity.icon
        }

        if let value = nonEmpty(activity.argumentsJSON) {
            argumentsJSON = argumentsJSON ?? value
        }
        if let value = nonEmpty(activity.resultJSON) {
            resultJSON = value
        }

        switch activity.phase {
        case .requested:
            requestedEventID = requestedEventID ?? event.id
            if let detail = nonEmpty(activity.detail) {
                outputText = outputText ?? nil
                if argumentsJSON == nil, looksLikeJSON(detail) {
                    argumentsJSON = detail
                }
            }
        case .approved:
            approvedEventID = approvedEventID ?? event.id
        case .running:
            startedEventID = startedEventID ?? event.id
        case .finished:
            finishedEventID = event.id
            outputText = nonEmpty(activity.detail) ?? nonEmpty(event.detail)
        case .failed:
            failedEventID = event.id
            errorText = nonEmpty(activity.detail) ?? nonEmpty(event.detail)
            outputText = outputText ?? errorText
        }
    }

    func build() -> AgentToolInvocationPresentation? {
        guard let toolName, let semanticKind else { return nil }
        return AgentToolInvocationPresentation(
            id: callID,
            callID: callID,
            runID: runID,
            sessionID: sessionID,
            toolName: toolName,
            semanticKind: semanticKind,
            phase: phase,
            severity: severity,
            title: AgentToolDisplayNameResolver.displayName(
                rawToolName: toolName,
                semanticKind: semanticKind,
                fallbackTitle: title
            ),
            subtitle: subtitle,
            target: target,
            icon: icon ?? "wrench.and.screwdriver",
            argumentsJSON: argumentsJSON,
            resultJSON: resultJSON,
            outputText: outputText,
            errorText: errorText,
            requestedEventID: requestedEventID,
            approvedEventID: approvedEventID,
            startedEventID: startedEventID,
            finishedEventID: finishedEventID,
            failedEventID: failedEventID,
            rawEventIDs: rawEventIDs
        )
    }

    private func shouldReplaceSummary(with activity: AgentToolActivityPresentation) -> Bool {
        phaseRank(activity.phase) >= phaseRank(phase)
    }

    private func phaseRank(_ phase: AgentToolActivityPhase) -> Int {
        switch phase {
        case .requested: 0
        case .approved: 1
        case .running: 2
        case .finished: 3
        case .failed: 4
        }
    }

    private func preferredToolName(existing: String?, candidate: String) -> String? {
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return existing }
        if existing == nil || existing == "unknown" { return candidate }
        return existing
    }

    private func preferredSemanticKind(existing: AgentToolSemanticKind?, candidate: AgentToolSemanticKind) -> AgentToolSemanticKind? {
        if existing == nil || existing == .unknown { return candidate }
        return existing
    }

    private func nonEmpty(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil
    }

    private func looksLikeJSON(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
}
