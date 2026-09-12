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

    /// M7 base 小程序能力面：这六个能力覆盖全部 base.* 工具执行（permission 映射见
    /// ConnorGraphAppSupport.BaseAgentTool.permission），任何权限模式下一律静默放行——
    /// 「所有 base 小程序操作免用户审批」，权限面不再是 base 的边界，
    /// 唯一边界是工具面（authoring/runtime 硬门禁在 BaseAgentTool.execute() 内）。
    /// basePublish（发布/公开动作，R7 硬门禁）不在此列：仍需人工确认。
    public static let baseSurfaceCapabilities: Set<AgentPermissionCapability> = [
        .baseRead, .baseWrite, .baseManageSchema, .baseManageMethods, .baseManageApps, .baseExecute
    ]

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
        // 控制电脑会话级授权：controlSystemInput 在非只读模式下，同会话批准过一次即自动放行
        // （授权存续见 ComputerControlConsent；readOnly 下仍一律拒绝）。
        var outcome = self.outcome(for: capability)
        if capability == .controlSystemInput, outcome == .needsApproval, permissionMode != .readOnly,
           await ComputerControlConsent.shared.isGranted(sessionID: sessionID) {
            outcome = .approved
        }
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
        // M7 硬切：base.* 小程序操作免用户审批——六个 base 能力任何权限模式下都静默放行
        // （不进审批队列、不弹人工确认）。边界在工具面（surface 硬门禁），不在权限面。
        // basePublish 是硬门禁例外：发布/公开动作任何执行模式下都需人工确认（R7）。
        if Self.baseSurfaceCapabilities.contains(capability) {
            return .approved
        }
        // 执行模式（trustedWrite/allowAll）下自动批准（含发送邮件与发布互动网页），
        // 不显示人工审批；但 basePublish 是硬门禁：发布/公开动作任何执行模式下都需人工确认（R7）。
        // 询问/只读模式按下方细分规则逐项判定。
        if permissionMode == .trustedWrite || permissionMode == .allowAll {
            if capability == .basePublish {
                return .needsApproval
            }
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
            return capability == .basePublish ? .needsApproval : .approved
        case .readOnly:
            // 下方 .baseRead 之外的 base.* 列举仅为穷举：六个 base 能力已在上方 M7 硬切提前放行。
            switch capability {
            case .readGraph, .readSession, .modelCall, .readWorkspaceFile, .listWorkspaceFiles, .searchWorkspaceFiles, .computeScientific, .runReadOnlyShellCommand, .readMail, .readMailBody, .readContacts, .readCalendar, .readRSS, .readRSSContent, .exportRSSOPML, .readBrowserPage, .readSystemScreen, .readSystemAccessibility, .baseRead:
                return .approved
            case .mutateSessionStatus, .deleteSession, .mutatePersonality, .proposeGraphWrite, .commitGraphWrite, .invalidateGraphStatement, .deleteGraphObject, .externalNetwork, .navigateBrowser, .interactBrowser, .commitBrowserAction, .transferBrowserFile, .costlyModelCall, .writeWorkspaceFile, .editWorkspaceFile, .deleteWorkspaceFile, .runWorkspaceShellCommand, .runNetworkShellCommand, .runDestructiveShellCommand, .mutateMailState, .manageMailboxes, .createMailDraft, .sendMail, .importMailAttachment, .mutateContacts, .mutateCalendar, .mutateRSSState, .manageRSSSources, .syncRSSSources, .importRSSOPML, .createInteractiveWebDraft, .publishInteractiveWeb, .largeWorkspaceWrite,
             .controlSystemInput, .baseWrite, .baseManageSchema, .baseManageMethods, .baseManageApps, .baseExecute, .basePublish:
                return .denied
            }
        case .askToWrite:
            // 下方 .baseRead 之外的 base.* 列举仅为穷举：六个 base 能力已在上方 M7 硬切提前放行。
            switch capability {
            case .readGraph, .readSession, .mutatePersonality, .modelCall, .proposeGraphWrite, .externalNetwork, .readBrowserPage, .navigateBrowser, .readWorkspaceFile, .listWorkspaceFiles, .searchWorkspaceFiles, .computeScientific, .runReadOnlyShellCommand, .readMail, .readMailBody, .createMailDraft, .readContacts, .readCalendar, .readRSS, .readRSSContent, .syncRSSSources, .exportRSSOPML, .createInteractiveWebDraft, .readSystemScreen, .readSystemAccessibility, .baseRead:
                return .approved
            case .mutateSessionStatus, .deleteSession, .commitGraphWrite, .invalidateGraphStatement, .deleteGraphObject, .interactBrowser, .commitBrowserAction, .transferBrowserFile, .costlyModelCall, .writeWorkspaceFile, .editWorkspaceFile, .deleteWorkspaceFile, .runWorkspaceShellCommand, .runNetworkShellCommand, .runDestructiveShellCommand, .mutateMailState, .manageMailboxes, .sendMail, .importMailAttachment, .mutateContacts, .mutateCalendar, .mutateRSSState, .manageRSSSources, .importRSSOPML, .publishInteractiveWeb, .largeWorkspaceWrite,
             .controlSystemInput, .baseWrite, .baseManageSchema, .baseManageMethods, .baseManageApps, .baseExecute, .basePublish:
                return .needsApproval
            }
        case .trustedWrite:
            return capability == .basePublish ? .needsApproval : .approved
        }
    }

    private func reason(for capability: AgentPermissionCapability, outcome: AgentPermissionOutcome) -> String {
        "\(permissionMode.rawValue) policy \(outcome.rawValue) capability \(capability.rawValue)"
    }
}
