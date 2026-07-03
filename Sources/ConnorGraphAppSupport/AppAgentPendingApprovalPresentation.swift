import Foundation
import ConnorGraphCore

public enum AppAgentPendingApprovalSeverity: String, Sendable, Equatable {
    case warning
    case success
    case error
    case cancelled
}

public struct AppAgentPendingApprovalPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var requestID: String
    public var title: String
    public var detail: String
    public var statusLabel: String
    public var severity: AppAgentPendingApprovalSeverity
    public var createdAt: Date
    public var allowsAlwaysAllow: Bool

    public init(_ approval: AgentPendingApproval) {
        self.id = approval.id
        self.requestID = approval.requestID
        self.title = "Permission requested: \(approval.capability.rawValue)"
        let tool = approval.toolName.map { " · Tool: \($0)" } ?? ""
        self.detail = "Request \(approval.requestID)\(tool) · Payload: \(Self.compactJSON(approval.payloadJSON))"
        self.statusLabel = approval.status.rawValue
        self.severity = Self.severity(for: approval.status)
        self.createdAt = approval.createdAt
        self.allowsAlwaysAllow = true
    }

    private static func severity(for status: AgentPendingApprovalStatus) -> AppAgentPendingApprovalSeverity {
        switch status {
        case .pending: .warning
        case .approved: .success
        case .denied: .error
        case .cancelled: .cancelled
        }
    }

    private static func compactJSON(_ json: String) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let compact = try? JSONSerialization.data(withJSONObject: object, options: []),
              let string = String(data: compact, encoding: .utf8)
        else { return trimmed }
        return string
    }
}
