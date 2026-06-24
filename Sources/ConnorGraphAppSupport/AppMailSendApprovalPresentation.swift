import Foundation
import ConnorGraphCore

public struct AppMailSendApprovalPresentation: Sendable, Equatable {
    public var isMailSendRequest: Bool
    public var draftID: String
    public var from: String?
    public var to: [String]
    public var cc: [String]
    public var bccCount: Int
    public var subject: String?
    public var bodyPreview: String?
    public var envelopeHash: String?
    public var warning: String

    public init(_ approval: AgentPendingApproval) {
        self.isMailSendRequest = approval.capability == .sendMail || approval.toolName == "mail_send_draft"
        let payload = Self.payloadObject(from: approval.payloadJSON)
        self.draftID = Self.stringValue(payload["draftID"]) ?? Self.stringValue(payload["draft_id"]) ?? "unknown"
        self.from = Self.stringValue(payload["from"])
        self.to = Self.stringArray(payload["to"])
        self.cc = Self.stringArray(payload["cc"])
        self.bccCount = Self.stringArray(payload["bcc"]).count
        self.subject = Self.stringValue(payload["subject"])
        self.bodyPreview = Self.stringValue(payload["bodyPreview"]) ?? Self.stringValue(payload["body_preview"])
        self.envelopeHash = Self.stringValue(payload["envelopeHash"]) ?? Self.stringValue(payload["envelope_hash"])
        self.warning = "点击 Allow 后，Connor 会继续执行这一次 mail_send_draft，并通过已配置 SMTP 账号发送真实邮件。请确认草稿收件人、主题和正文。"
    }

    public var title: String { "确认发送邮件" }

    public var recipientSummary: String {
        if to.isEmpty { return "收件人：草稿中配置" }
        return "收件人：\(to.joined(separator: ", "))"
    }

    public var subjectSummary: String {
        let value = subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "主题：草稿中配置" : "主题：\(value)"
    }

    public var securitySummary: String {
        var parts = ["Draft: \(draftID)"]
        if let envelopeHash, !envelopeHash.isEmpty { parts.append("Envelope: \(envelopeHash)") }
        if bccCount > 0 { parts.append("Bcc: \(bccCount) hidden") }
        return parts.joined(separator: " · ")
    }

    private static func payloadObject(from json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return [:] }
        return dictionary
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let values = value as? [Any] { return values.compactMap(stringValue) }
        if let string = value as? String, !string.isEmpty { return [string] }
        return []
    }
}
