import Foundation
import Observation
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Observable
final class ChatApprovalCoordinator {
    let model: ChatApprovalModel
    private let repository: AppAgentPendingApprovalRepository?
    private var resolutionTasksByRequestID: [String: Task<Void, Never>] = [:]
    private var reloadTask: Task<Void, Never>?
    private var generation = 0
    private var reloadGeneration = 0
    private var isShutdown = false

    @ObservationIgnored var activeSessionID: () -> String = { "" }
    @ObservationIgnored var permissionMode: () -> AgentPermissionMode = { .askToWrite }
    @ObservationIgnored var backendForApproval: (AgentPendingApproval) -> AnyAgentBackend? = { _ in nil }
    @ObservationIgnored var onAlwaysAllow: () -> Void = {}
    @ObservationIgnored var onError: (String) -> Void = { _ in }

    init(model: ChatApprovalModel, repository: AppAgentPendingApprovalRepository?) {
        self.model = model
        self.repository = repository
    }

    func activeApprovals(sessionID: String) -> [AgentPendingApproval] {
        model.pendingApprovals.filter { $0.sessionID == sessionID && !shouldAutoApprove($0) }
    }

    func install(_ approvals: [AgentPendingApproval]) {
        guard !isShutdown else { return }
        model.pendingApprovals = approvals
        autoApproveCurrentPolicy()
    }

    func reload() {
        guard !isShutdown else { return }
        guard let repository else {
            model.pendingApprovals = []
            return
        }
        reloadGeneration += 1
        let currentGeneration = reloadGeneration
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            do {
                let approvals = try await Task.detached(priority: .userInitiated) {
                    try repository.loadPending()
                }.value
                try Task.checkCancellation()
                guard let self, !self.isShutdown, self.reloadGeneration == currentGeneration else { return }
                self.model.pendingApprovals = approvals
                self.autoApproveCurrentPolicy()
            } catch is CancellationError {
                return
            } catch {
                guard let self, !self.isShutdown, self.reloadGeneration == currentGeneration else { return }
                self.onError(String(describing: error))
            }
        }
    }

    func approve(_ approval: AgentPendingApproval) {
        resolve(approval, status: .approved, reason: "Approved by reviewer", actor: "human-reviewer")
    }

    func deny(_ approval: AgentPendingApproval) {
        resolve(approval, status: .denied, reason: "Denied by reviewer", actor: "human-reviewer")
    }

    func cancel(_ approval: AgentPendingApproval) {
        resolve(approval, status: .cancelled, reason: "Cancelled by system", actor: "system")
    }

    func alwaysAllow(_ approval: AgentPendingApproval) {
        guard !isShutdown else { return }
        onAlwaysAllow()
        resolve(approval, status: .approved, reason: "Always allowed by reviewer for this trusted session", actor: "human-reviewer")
    }

    func permissionModeDidChange() {
        guard !isShutdown else { return }
        autoApproveCurrentPolicy()
    }

    private func autoApproveCurrentPolicy() {
        for approval in model.pendingApprovals where shouldAutoApprove(approval) {
            resolve(
                approval,
                status: .approved,
                reason: "Automatically approved by current \(permissionMode().displayName) policy",
                actor: "policy-auto-approver"
            )
        }
    }

    private func shouldAutoApprove(_ approval: AgentPendingApproval) -> Bool {
        guard approval.status == .pending else { return false }
        switch permissionMode() {
        case .trustedWrite:
            switch approval.capability {
            case .readGraph, .readSession, .mutateSessionStatus, .modelCall, .proposeGraphWrite, .commitGraphWrite, .externalNetwork, .readWorkspaceFile, .listWorkspaceFiles, .searchWorkspaceFiles, .writeWorkspaceFile, .editWorkspaceFile, .computeScientific, .runReadOnlyShellCommand, .runWorkspaceShellCommand, .readContacts, .readCalendar, .readRSS, .readRSSContent, .mutateRSSState, .syncRSSSources, .exportRSSOPML, .readMail, .readMailBody, .createMailDraft:
                return true
            case .invalidateGraphStatement, .deleteGraphObject, .costlyModelCall, .deleteWorkspaceFile, .runNetworkShellCommand, .runDestructiveShellCommand, .mutateContacts, .mutateCalendar, .manageRSSSources, .importRSSOPML, .mutateMailState, .manageMailboxes, .sendMail, .importMailAttachment:
                return false
            }
        case .allowAll:
            return true
        case .readOnly, .askToWrite:
            return false
        }
    }

    private func resolve(_ approval: AgentPendingApproval, status: AgentPendingApprovalStatus, reason: String, actor: String) {
        guard !isShutdown, resolutionTasksByRequestID[approval.requestID] == nil else { return }
        let currentGeneration = generation
        resolutionTasksByRequestID[approval.requestID] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == currentGeneration {
                    self.resolutionTasksByRequestID.removeValue(forKey: approval.requestID)
                }
            }
            do {
                let resolved: AgentPendingApproval?
                switch status {
                case .approved:
                    resolved = try self.repository?.approve(requestID: approval.requestID, reason: reason, actor: actor)
                case .denied:
                    resolved = try self.repository?.deny(requestID: approval.requestID, reason: reason, actor: actor)
                case .cancelled:
                    resolved = try self.repository?.cancel(requestID: approval.requestID, reason: reason, actor: actor)
                case .pending:
                    resolved = approval
                }
                try Task.checkCancellation()
                let sent: Bool
                if let resolved, let backend = self.backendForApproval(resolved) {
                    try await backend.resolveApproval(resolved, status: status, reason: reason, actor: actor)
                    sent = true
                } else {
                    sent = false
                }
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                self.reload()
                self.model.lastResultSummary = Self.resultSummary(approval: approval, status: status, sentToLiveBackend: sent)
            } catch is CancellationError {
                return
            } catch {
                guard self.generation == currentGeneration else { return }
                self.onError(String(describing: error))
            }
        }
    }

    private static func resultSummary(approval: AgentPendingApproval, status: AgentPendingApprovalStatus, sentToLiveBackend: Bool) -> String {
        switch status {
        case .approved:
            sentToLiveBackend
                ? "已批准权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 agent run 发送 resume。"
                : "已批准权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run，未发送 resume。请重试该会话请求。"
        case .denied:
            sentToLiveBackend
                ? "已拒绝权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 agent run 发送 deny。"
                : "已拒绝权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run。"
        case .cancelled:
            sentToLiveBackend
                ? "已取消权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 agent run 发送 cancel/deny。"
                : "已取消权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run。"
        case .pending:
            "权限请求 \(approval.requestID) 仍为 pending。"
        }
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        generation += 1
        reloadGeneration += 1
        reloadTask?.cancel()
        reloadTask = nil
        for task in resolutionTasksByRequestID.values { task.cancel() }
        resolutionTasksByRequestID.removeAll()
    }
}

extension ChatApprovalCoordinator: ChatApprovalCommanding {
    var activeChatPendingApprovals: [AgentPendingApproval] { activeApprovals(sessionID: activeSessionID()) }
    func reloadPendingApprovals() { reload() }
    func approvePendingApproval(_ approval: AgentPendingApproval) { approve(approval) }
    func denyPendingApproval(_ approval: AgentPendingApproval) { deny(approval) }
    func cancelPendingApproval(_ approval: AgentPendingApproval) { cancel(approval) }
    func alwaysAllowPendingApproval(_ approval: AgentPendingApproval) { alwaysAllow(approval) }
}
