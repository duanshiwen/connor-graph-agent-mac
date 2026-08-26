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
    public private(set) var permissionMode: AgentPermissionMode
    private let auditLog: any AgentAuditLog

    public init(permissionMode: AgentPermissionMode, auditLog: any AgentAuditLog = InMemoryAgentAuditLog()) {
        self.permissionMode = permissionMode
        self.auditLog = auditLog
    }

    /// 让正在运行的 run 也能切换权限模式：后续工具调用按新模式判定。
    public func updatePermissionMode(_ mode: AgentPermissionMode) {
        permissionMode = mode
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

    public func discoveryOutcome(for capability: AgentPermissionCapability) -> AgentPermissionOutcome {
        outcome(for: capability)
    }

    private func outcome(for capability: AgentPermissionCapability) -> AgentPermissionOutcome {
        // 硬性门禁：即使在执行模式（trustedWrite/allowAll）下也要求人工审批，
        // 规则与 requiresHumanApprovalInExecutionMode 保持一致（唯一事实来源）。
        if capability.requiresHumanApprovalInExecutionMode {
            return permissionMode == .readOnly ? .denied : .needsApproval
        }
        if permissionMode == .trustedWrite || permissionMode == .allowAll {
            return .approved
        }
        if capability == .mutateContacts
            || capability == .mutateCalendar
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
            case .mutateSessionStatus, .deleteSession, .mutatePersonality, .proposeGraphWrite, .commitGraphWrite, .invalidateGraphStatement, .deleteGraphObject, .externalNetwork, .navigateBrowser, .interactBrowser, .commitBrowserAction, .transferBrowserFile, .costlyModelCall, .writeWorkspaceFile, .editWorkspaceFile, .deleteWorkspaceFile, .runWorkspaceShellCommand, .runNetworkShellCommand, .runDestructiveShellCommand, .mutateMailState, .manageMailboxes, .createMailDraft, .sendMail, .importMailAttachment, .mutateContacts, .mutateCalendar, .mutateRSSState, .manageRSSSources, .syncRSSSources, .importRSSOPML, .createInteractiveWebDraft, .publishInteractiveWeb, .largeWorkspaceWrite:
                return .denied
            }
        case .askToWrite:
            switch capability {
            case .readGraph, .readSession, .mutatePersonality, .modelCall, .proposeGraphWrite, .externalNetwork, .readBrowserPage, .navigateBrowser, .readWorkspaceFile, .listWorkspaceFiles, .searchWorkspaceFiles, .computeScientific, .runReadOnlyShellCommand, .readMail, .readMailBody, .createMailDraft, .readContacts, .readCalendar, .readRSS, .readRSSContent, .syncRSSSources, .exportRSSOPML, .createInteractiveWebDraft:
                return .approved
            case .mutateSessionStatus, .deleteSession, .commitGraphWrite, .invalidateGraphStatement, .deleteGraphObject, .interactBrowser, .commitBrowserAction, .transferBrowserFile, .costlyModelCall, .writeWorkspaceFile, .editWorkspaceFile, .deleteWorkspaceFile, .runWorkspaceShellCommand, .runNetworkShellCommand, .runDestructiveShellCommand, .mutateMailState, .manageMailboxes, .sendMail, .importMailAttachment, .mutateContacts, .mutateCalendar, .mutateRSSState, .manageRSSSources, .importRSSOPML, .publishInteractiveWeb, .largeWorkspaceWrite:
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
