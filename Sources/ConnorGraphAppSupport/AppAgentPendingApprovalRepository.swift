import Foundation
import ConnorGraphCore
import ConnorGraphStore

public struct AppAgentPendingApprovalPage: Sendable, Equatable {
    public var approvals: [AgentPendingApproval]
    public var nextCursor: String?

    public init(approvals: [AgentPendingApproval], nextCursor: String?) {
        self.approvals = approvals
        self.nextCursor = nextCursor
    }
}

private struct AppAgentPendingApprovalCursor: Codable {
    var createdAt: Date
    var id: String
}

public struct AppAgentPendingApprovalRepository: Sendable {
    public let store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func loadPending(limit: Int = 100) throws -> [AgentPendingApproval] {
        try store.pendingApprovals(status: .pending, limit: limit)
    }

    public func loadPendingPage(limit: Int = 50, cursor: String? = nil) throws -> AppAgentPendingApprovalPage {
        let pageSize = min(max(limit, 1), 100)
        let decodedCursor = try cursor.map(Self.decodeCursor)
        let rows = try store.pendingApprovalPage(
            status: .pending,
            afterCreatedAt: decodedCursor?.createdAt,
            afterID: decodedCursor?.id,
            limit: pageSize + 1
        )
        let approvals = Array(rows.prefix(pageSize))
        let nextCursor = rows.count > pageSize ? try approvals.last.map(Self.encodeCursor) : nil
        return AppAgentPendingApprovalPage(approvals: approvals, nextCursor: nextCursor)
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

    private static func encodeCursor(_ approval: AgentPendingApproval) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(AppAgentPendingApprovalCursor(createdAt: approval.createdAt, id: approval.id)).base64EncodedString()
    }

    private static func decodeCursor(_ raw: String) throws -> AppAgentPendingApprovalCursor {
        guard let data = Data(base64Encoded: raw) else { throw CocoaError(.coderReadCorrupt) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppAgentPendingApprovalCursor.self, from: data)
    }
}
