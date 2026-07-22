import Foundation
import ConnorGraphCore

public protocol AgentAuditLog: Sendable {
    func record(_ event: AgentAuditEvent) async
}

public actor InMemoryAgentAuditLog: AgentAuditLog {
    public private(set) var events: [AgentAuditEvent] = []

    public init() {}

    public func record(_ event: AgentAuditEvent) async {
        events.append(event)
    }
}

public actor AgentPolicyEngine: Sendable {
    public let permissionMode: AgentPermissionMode
    private let auditLog: any AgentAuditLog

    public init(permissionMode: AgentPermissionMode, auditLog: any AgentAuditLog = InMemoryAgentAuditLog()) {
        self.permissionMode = permissionMode
        self.auditLog = auditLog
    }

    public func evaluate(
        capability: AgentPermissionCapability,
        runID: String,
        sessionID: String,
        toolName: String? = nil,
        payloadJSON: String = "{}"
    ) async -> AgentPermissionDecision {
        let request = AgentPermissionRequest(
            runID: runID,
            sessionID: sessionID,
            capability: capability,
            toolName: toolName,
            payloadJSON: payloadJSON
        )
        let outcome = outcome(for: capability)
        let decision = AgentPermissionDecision(
            requestID: request.id,
            runID: runID,
            sessionID: sessionID,
            capability: capability,
            outcome: outcome,
            reason: reason(for: capability, outcome: outcome)
        )
        await auditLog.record(AgentAuditEvent(
            runID: runID,
            sessionID: sessionID,
            eventType: .permissionDecision,
            capability: capability,
            toolName: toolName,
            decision: decision,
            payloadJSON: payloadJSON
        ))
        return decision
    }

    private func outcome(for capability: AgentPermissionCapability) -> AgentPermissionOutcome {
        if permissionMode == .trustedWrite || permissionMode == .allowAll {
            return .approved
        }
        if capability == .mutateContacts
            || capability == .mutateCalendar
            || capability == .mutatePersonality
            || capability == .sendMail
            || capability == .commitBrowserAction
            || capability == .transferBrowserFile
        {
            return .needsApproval
        }
        switch permissionMode {
        case .allowAll:
            return .approved
        case .readOnly:
            switch capability {
            case .readGraph, .readSession, .modelCall, .readWorkspaceFile, .listWorkspaceFiles, .searchWorkspaceFiles, .computeScientific, .runReadOnlyShellCommand, .readMail, .readMailBody, .readContacts, .readCalendar, .readRSS, .readRSSContent, .exportRSSOPML, .readBrowserPage:
                return .approved
            case .mutateSessionStatus, .mutatePersonality, .proposeGraphWrite, .commitGraphWrite, .invalidateGraphStatement, .deleteGraphObject, .externalNetwork, .navigateBrowser, .interactBrowser, .commitBrowserAction, .transferBrowserFile, .costlyModelCall, .writeWorkspaceFile, .editWorkspaceFile, .deleteWorkspaceFile, .runWorkspaceShellCommand, .runNetworkShellCommand, .runDestructiveShellCommand, .mutateMailState, .manageMailboxes, .createMailDraft, .sendMail, .importMailAttachment, .mutateContacts, .mutateCalendar, .mutateRSSState, .manageRSSSources, .syncRSSSources, .importRSSOPML:
                return .denied
            }
        case .askToWrite:
            switch capability {
            case .readGraph, .readSession, .modelCall, .proposeGraphWrite, .externalNetwork, .readBrowserPage, .navigateBrowser, .readWorkspaceFile, .listWorkspaceFiles, .searchWorkspaceFiles, .computeScientific, .runReadOnlyShellCommand, .readMail, .readMailBody, .createMailDraft, .readContacts, .readCalendar, .readRSS, .readRSSContent, .syncRSSSources, .exportRSSOPML:
                return .approved
            case .mutateSessionStatus, .mutatePersonality, .commitGraphWrite, .invalidateGraphStatement, .deleteGraphObject, .interactBrowser, .commitBrowserAction, .transferBrowserFile, .costlyModelCall, .writeWorkspaceFile, .editWorkspaceFile, .deleteWorkspaceFile, .runWorkspaceShellCommand, .runNetworkShellCommand, .runDestructiveShellCommand, .mutateMailState, .manageMailboxes, .sendMail, .importMailAttachment, .mutateContacts, .mutateCalendar, .mutateRSSState, .manageRSSSources, .importRSSOPML:
                return .needsApproval
            }
        case .trustedWrite:
            return .approved
        }
    }

    private func reason(for capability: AgentPermissionCapability, outcome: AgentPermissionOutcome) -> String {
        "\(permissionMode.rawValue) policy \(outcome.rawValue) capability \(capability.rawValue)"
    }
}
