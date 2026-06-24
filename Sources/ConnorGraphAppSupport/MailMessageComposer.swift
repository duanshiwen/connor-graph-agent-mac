import Foundation
import ConnorGraphCore

public enum MailMessageComposerError: Error, Equatable, Sendable, CustomStringConvertible {
    case headerInjection(String)
    case missingRecipient

    public var description: String {
        switch self {
        case .headerInjection(let field): "Header injection detected in \(field)"
        case .missingRecipient: "At least one recipient is required"
        }
    }
}

public struct MailSMTPEnvelope: Sendable, Equatable {
    public var from: MailAddress
    public var recipients: [MailAddress]

    public init(from: MailAddress, recipients: [MailAddress]) {
        self.from = from
        self.recipients = recipients
    }
}

public struct ComposedMailMessage: Sendable, Equatable {
    public var rawMessage: String
    public var envelopeRecipients: [MailAddress]
    public var envelopeHash: String
    public var messageID: String
    public var from: MailAddress

    public var rfc5322: String { rawMessage }
    public var envelope: MailSMTPEnvelope { MailSMTPEnvelope(from: from, recipients: envelopeRecipients) }

    public init(rawMessage: String, envelopeRecipients: [MailAddress], envelopeHash: String, messageID: String, from: MailAddress) {
        self.rawMessage = rawMessage
        self.envelopeRecipients = envelopeRecipients
        self.envelopeHash = envelopeHash
        self.messageID = messageID
        self.from = from
    }
}

public struct MailMessageComposer: Sendable {
    public init() {}

    public func compose(
        draft: MailDraft,
        from: MailAddress,
        date: Date = Date(),
        messageID: String? = nil
    ) throws -> ComposedMailMessage {
        let recipients = draft.to + draft.cc + draft.bcc
        guard !recipients.isEmpty else { throw MailMessageComposerError.missingRecipient }
        try validateAddress(from, field: "From")
        try draft.to.forEach { try validateAddress($0, field: "To") }
        try draft.cc.forEach { try validateAddress($0, field: "Cc") }
        try draft.bcc.forEach { try validateAddress($0, field: "Bcc") }
        try draft.replyTo.forEach { try validateAddress($0, field: "Reply-To") }
        try validateHeaderValue(draft.subject, field: "Subject")
        try draft.referencesHeaders.forEach { try validateHeaderValue($0, field: "References") }
        if let value = draft.inReplyToHeader { try validateHeaderValue(value, field: "In-Reply-To") }
        if let value = draft.messageIDHeader { try validateHeaderValue(value, field: "Message-ID") }

        let resolvedMessageID = messageID ?? draft.messageIDHeader ?? "<\(UUID().uuidString)@connor.local>"
        let dateHeader = Self.rfc5322DateFormatter.string(from: date)
        var headers: [String] = []
        headers.append("From: \(formatAddress(from))")
        headers.append("To: \(draft.to.map(formatAddress).joined(separator: ", "))")
        if !draft.cc.isEmpty { headers.append("Cc: \(draft.cc.map(formatAddress).joined(separator: ", "))") }
        if !draft.replyTo.isEmpty { headers.append("Reply-To: \(draft.replyTo.map(formatAddress).joined(separator: ", "))") }
        headers.append("Subject: \(encodeHeaderIfNeeded(draft.subject))")
        headers.append("Date: \(dateHeader)")
        headers.append("Message-ID: \(resolvedMessageID)")
        if let inReplyTo = draft.inReplyToHeader { headers.append("In-Reply-To: \(inReplyTo)") }
        if !draft.referencesHeaders.isEmpty { headers.append("References: \(draft.referencesHeaders.joined(separator: " "))") }
        headers.append("MIME-Version: 1.0")

        let body: String
        if let htmlBody = draft.htmlBody, !htmlBody.isEmpty {
            let boundary = "connor-alt-\(UUID().uuidString)"
            headers.append("Content-Type: multipart/alternative; boundary=\"\(boundary)\"")
            body = [
                "--\(boundary)",
                "Content-Type: text/plain; charset=utf-8",
                "Content-Transfer-Encoding: 8bit",
                "",
                normalizeBody(draft.body),
                "--\(boundary)",
                "Content-Type: text/html; charset=utf-8",
                "Content-Transfer-Encoding: 8bit",
                "",
                normalizeBody(htmlBody),
                "--\(boundary)--",
                ""
            ].joined(separator: "\r\n")
        } else {
            headers.append("Content-Type: text/plain; charset=utf-8")
            headers.append("Content-Transfer-Encoding: 8bit")
            body = normalizeBody(draft.body)
        }

        let raw = headers.joined(separator: "\r\n") + "\r\n\r\n" + body
        return ComposedMailMessage(
            rawMessage: raw,
            envelopeRecipients: recipients,
            envelopeHash: draft.envelopeHash(),
            messageID: resolvedMessageID,
            from: from
        )
    }

    public func compose(
        draft: MailDraft,
        identity: MailIdentity,
        date: Date = Date(),
        messageID: String? = nil
    ) throws -> ComposedMailMessage {
        try compose(draft: draft, from: identity.address, date: date, messageID: messageID)
    }

    public static func dotStuff(_ rawMessage: String) -> String {
        rawMessage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in line.hasPrefix(".") ? ".\(line)" : line }
            .joined(separator: "\r\n")
    }

    private func validateAddress(_ address: MailAddress, field: String) throws {
        if let name = address.name { try validateHeaderValue(name, field: field) }
        try validateHeaderValue(address.email, field: field)
    }

    private func validateHeaderValue(_ value: String, field: String) throws {
        if value.unicodeScalars.contains(where: { $0.value == 10 || $0.value == 13 }) {
            throw MailMessageComposerError.headerInjection(field)
        }
    }

    private func formatAddress(_ address: MailAddress) -> String {
        if let name = address.name, !name.isEmpty {
            return "\(encodeHeaderIfNeeded(name)) <\(address.email)>"
        }
        return address.email
    }

    private func encodeHeaderIfNeeded(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0.value > 127 }) else { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

    private func normalizeBody(_ body: String) -> String {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
    }

    private static let rfc5322DateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}
