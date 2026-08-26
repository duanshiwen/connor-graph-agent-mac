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
    private var loadMoreTask: Task<Void, Never>?
    private var generation = 0
    private var reloadGeneration = 0
    private var isShutdown = false
    /// 已对外提示过的 pending 请求，避免同一请求被反复弹窗/通知。
    private var lastReportedPendingRequestIDs: Set<String> = []

    @ObservationIgnored var activeSessionID: () -> String = { "" }
    @ObservationIgnored var permissionMode: () -> AgentPermissionMode = { .askToWrite }
    @ObservationIgnored var backendForApproval: (AgentPendingApproval) -> AnyAgentBackend? = { _ in nil }
    @ObservationIgnored var onAlwaysAllow: () -> Void = {}
    @ObservationIgnored var onNewPendingApprovals: ([AgentPendingApproval]) -> Void = { _ in }
    @ObservationIgnored var onError: (String) -> Void = { _ in }

    init(model: ChatApprovalModel, repository: AppAgentPendingApprovalRepository?) {
        self.model = model
        self.repository = repository
    }

    /// 当前会话需要人工处理的待审批请求。
    /// 不按权限模式过滤：run 侧策略（AgentPolicyEngine）决定哪些请求会进入待审批状态——
    /// 在执行模式（trustedWrite/allowAll）下普通权限直接放行，只有策略仍然硬性要求人工确认的
    /// 请求（如发布互动网页 publishInteractiveWeb）才会到达这里；这类请求必须展示审批卡片，
    /// 否则 run 会一直阻塞且用户无处确认（会话列表只显示“请求审批”文字，详情页却看不到弹窗）。
    func activeApprovals(sessionID: String) -> [AgentPendingApproval] {
        model.pendingApprovals.filter { $0.sessionID == sessionID && $0.status == .pending }
    }

    func install(_ approvals: [AgentPendingApproval]) {
        guard !isShutdown else { return }
        applyLoadedApprovals(approvals, nextCursor: nil)
    }

    func reload() {
        guard !isShutdown else { return }
        guard let repository else {
            model.pendingApprovals = []
            model.nextPageCursor = nil
            return
        }
        reloadGeneration += 1
        let currentGeneration = reloadGeneration
        reloadTask?.cancel()
        loadMoreTask?.cancel()
        loadMoreTask = nil
        model.isLoadingNextPage = false
        reloadTask = Task { [weak self] in
            do {
                let approvals = try await Task.detached(priority: .userInitiated) {
                    try repository.loadPendingPage()
                }.value
                try Task.checkCancellation()
                guard let self, !self.isShutdown, self.reloadGeneration == currentGeneration else { return }
                self.applyLoadedApprovals(approvals.approvals, nextCursor: approvals.nextCursor)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !self.isShutdown, self.reloadGeneration == currentGeneration else { return }
                self.onError(String(describing: error))
            }
        }
    }

    func loadMoreIfNeeded(currentApprovalID: String) {
        guard !isShutdown,
              model.pendingApprovals.last?.id == currentApprovalID,
              let cursor = model.nextPageCursor,
              !model.isLoadingNextPage,
              loadMoreTask == nil,
              let repository else { return }
        model.isLoadingNextPage = true
        let currentGeneration = reloadGeneration
        loadMoreTask = Task { [weak self] in
            defer {
                self?.model.isLoadingNextPage = false
                self?.loadMoreTask = nil
            }
            do {
                let page = try await Task.detached(priority: .userInitiated) {
                    try repository.loadPendingPage(cursor: cursor)
                }.value
                try Task.checkCancellation()
                guard let self, !self.isShutdown, self.reloadGeneration == currentGeneration else { return }
                let existingIDs = Set(self.model.pendingApprovals.map(\.id))
                self.model.pendingApprovals.append(contentsOf: page.approvals.filter { !existingIDs.contains($0.id) })
                self.model.nextPageCursor = page.nextCursor
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

    @discardableResult
    func cancelPendingApprovals(runID: String, reason: String) -> Int {
        guard !isShutdown else { return 0 }
        do {
            let persisted = try repository?.load(runID: runID) ?? []
            let visible = model.pendingApprovals.filter { $0.runID == runID }
            let approvals = Dictionary(
                (persisted + visible).map { ($0.requestID, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values.filter { $0.status == .pending }

            for approval in approvals {
                _ = try repository?.cancel(
                    requestID: approval.requestID,
                    reason: reason,
                    actor: "run-cancellation"
                )
            }

            let requestIDs = Set(approvals.map(\.requestID))
            model.pendingApprovals.removeAll { requestIDs.contains($0.requestID) }
            if !requestIDs.isEmpty {
                model.lastResultSummary = "已随运行终止取消 \(requestIDs.count) 个待审批请求，并写入审计和 timeline。"
            }
            return requestIDs.count
        } catch {
            onError("终止运行时清理待审批请求失败：\(error)")
            return 0
        }
    }

    func alwaysAllow(_ approval: AgentPendingApproval) {
        guard !isShutdown else { return }
        onAlwaysAllow()
        resolve(approval, status: .approved, reason: "Always allowed by reviewer for this trusted session", actor: "human-reviewer")
    }

    /// 用户主动切换权限模式（例如从“询问”切到“执行”）时，把当前仍处于待审批状态的请求
    /// 按新模式自动放行：这是用户明确的“接下来不用再问我”的意图。
    func permissionModeDidChange() {
        guard !isShutdown else { return }
        autoApproveCurrentPolicy()
    }

    /// 仅在用户主动切换权限模式时调用；加载待审批列表本身不自动批准，
    /// 因为能进入待审批状态的请求（含执行模式下的硬性门禁请求）必须交给用户确认。
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

    /// 统一入口：替换待审批列表，并把「新到达」的待审批请求通过 onNewPendingApprovals
    /// 通知外层（用于弹窗/通知/自动切换到对应会话）。
    /// 加载本身不再执行自动批准：任何能进入待审批状态的请求都代表 run 正在等待人工决策，
    /// 必须展示给用户；执行模式下的普通权限在 run 侧策略引擎就已放行，不会走到这里。
    private func applyLoadedApprovals(_ approvals: [AgentPendingApproval], nextCursor: String?) {
        let previouslySeen = lastReportedPendingRequestIDs
        let loadedPendingIDs = Set(approvals.filter { $0.status == .pending }.map(\.requestID))
        let newlyArrived = approvals.filter { $0.status == .pending && !previouslySeen.contains($0.requestID) }
        lastReportedPendingRequestIDs = loadedPendingIDs
        model.pendingApprovals = approvals
        model.nextPageCursor = nextCursor
        if !newlyArrived.isEmpty {
            onNewPendingApprovals(newlyArrived)
        }
    }

    private func shouldAutoApprove(_ approval: AgentPendingApproval) -> Bool {
        guard approval.status == .pending else { return false }
        switch permissionMode() {
        case .trustedWrite, .allowAll:
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
                var resolvedStatus = status
                let resolved: AgentPendingApproval?
                if status == .pending || self.backendForApproval(approval) != nil {
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
                } else {
                    // 审批时找不到仍在线等待的 agent run（例如应用重启、run 已结束）：
                    // 直接把请求标记为取消，避免“已批准但永远无法恢复”的悬空状态。
                    resolvedStatus = .cancelled
                    resolved = try self.repository?.cancel(
                        requestID: approval.requestID,
                        reason: "未找到仍在线的 agent run，无法恢复执行；待审批请求已取消，请重新执行任务",
                        actor: "system"
                    )
                }
                try Task.checkCancellation()
                let sent: Bool
                if let resolved, let backend = self.backendForApproval(resolved) {
                    try await backend.resolveApproval(resolved, status: resolvedStatus, reason: reason, actor: actor)
                    sent = true
                } else {
                    sent = false
                }
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                self.reload()
                self.model.lastResultSummary = Self.resultSummary(approval: approval, status: resolvedStatus, sentToLiveBackend: sent)
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
        loadMoreTask?.cancel()
        loadMoreTask = nil
        model.isLoadingNextPage = false
        for task in resolutionTasksByRequestID.values { task.cancel() }
        resolutionTasksByRequestID.removeAll()
    }
}

extension ChatApprovalCoordinator: ChatApprovalCommanding {
    var activeChatPendingApprovals: [AgentPendingApproval] { activeApprovals(sessionID: activeSessionID()) }
    func reloadPendingApprovals() { reload() }
    func loadMorePendingApprovalsIfNeeded(currentApprovalID: String) { loadMoreIfNeeded(currentApprovalID: currentApprovalID) }
    func approvePendingApproval(_ approval: AgentPendingApproval) { approve(approval) }
    func denyPendingApproval(_ approval: AgentPendingApproval) { deny(approval) }
    func cancelPendingApproval(_ approval: AgentPendingApproval) { cancel(approval) }
    func alwaysAllowPendingApproval(_ approval: AgentPendingApproval) { alwaysAllow(approval) }
}
