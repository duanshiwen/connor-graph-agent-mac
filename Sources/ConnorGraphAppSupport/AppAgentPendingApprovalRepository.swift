import Foundation
import ConnorGraphCore
import ConnorGraphStore

public struct AppAgentPendingApprovalRepository: Sendable {
    public let store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func loadPending(limit: Int = 100) throws -> [AgentPendingApproval] {
        try store.pendingApprovals(status: .pending, limit: limit)
    }

    public func load(runID: String, limit: Int = 100) throws -> [AgentPendingApproval] {
        try store.pendingApprovals(runID: runID, limit: limit)
    }

    public func approve(requestID: String, reason: String, actor: String = "human-reviewer") throws -> AgentPendingApproval {
        try store.resolvePendingApproval(requestID: requestID, status: .approved, reason: reason, actor: actor)
    }

    public func deny(requestID: String, reason: String, actor: String = "human-reviewer") throws -> AgentPendingApproval {
        try store.resolvePendingApproval(requestID: requestID, status: .denied, reason: reason, actor: actor)
    }

    public func cancel(requestID: String, reason: String, actor: String = "system") throws -> AgentPendingApproval {
        try store.resolvePendingApproval(requestID: requestID, status: .cancelled, reason: reason, actor: actor)
    }
}
