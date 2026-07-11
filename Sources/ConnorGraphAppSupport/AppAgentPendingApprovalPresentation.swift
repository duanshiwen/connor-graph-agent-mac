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
        let mail = AppMailSendApprovalPresentation(approval)
        if mail.isMailSendRequest {
            self.title = mail.title
            self.detail = [mail.recipientSummary, mail.subjectSummary, mail.securitySummary].joined(separator: " · ")
            self.allowsAlwaysAllow = false
        } else if approval.toolName == "calendar_write", let calendar = Self.calendarPayload(approval.payloadJSON) {
            self.title = calendar.title
            self.detail = calendar.detail
            self.allowsAlwaysAllow = false
        } else {
            self.title = "Permission requested: \(approval.capability.rawValue)"
            let tool = approval.toolName.map { " · Tool: \($0)" } ?? ""
            self.detail = "Request \(approval.requestID)\(tool) · Payload: \(Self.compactJSON(approval.payloadJSON))"
            self.allowsAlwaysAllow = true
        }
        self.statusLabel = approval.status.rawValue
        self.severity = Self.severity(for: approval.status)
        self.createdAt = approval.createdAt
    }

    private static func calendarPayload(_ json: String) -> (title: String, detail: String)? {
        guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let operation = object["operation"] as? String else { return nil }
        let title: String
        switch operation {
        case "create_event": title = "Calendar: Create Event"
        case "update_event": title = "Calendar: Update Event"
        case "delete_event": title = "Calendar: Delete Event"
        default: title = "Calendar: Write"
        }
        let eventTitle = object["verifiedEventTitle"] as? String ?? object["title"] as? String ?? "Untitled event"
        let eventID = object["eventID"] as? String
        let calendarID = object["verifiedCalendarID"] as? String ?? object["calendarID"] as? String
        let fields = [eventTitle, eventID.map { "eventID: \($0)" }, calendarID.map { "calendarID: \($0)" }].compactMap { $0 }
        return (title, fields.joined(separator: " · "))
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
