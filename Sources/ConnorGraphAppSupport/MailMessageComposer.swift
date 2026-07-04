import Foundation
import ConnorGraphCore

public enum MailMessageComposerError: Error, Equatable, Sendable, CustomStringConvertible {
    case headerInjection(String)
    case missingRecipient
    case unsafeAttachmentFilename(String)

    public var description: String {
        switch self {
        case .headerInjection(let field): "Header injection detected in \(field)"
        case .missingRecipient: "At least one recipient is required"
        case .unsafeAttachmentFilename(let filename): "Unsafe attachment filename: \(filename)"
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

public struct OutboundMailAttachment: Sendable, Equatable {
    public var id: MailAttachmentID
    public var filename: String
    public var mimeType: String
    public var data: Data
    public var contentID: String?
    public var isInline: Bool
    public var contentHash: String?

    public init(id: MailAttachmentID, filename: String, mimeType: String, data: Data, contentID: String? = nil, isInline: Bool = false, contentHash: String? = nil) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.contentID = contentID
        self.isInline = isInline
        self.contentHash = contentHash
    }

    public func descriptor(messageID: MailMessageID) -> MailAttachmentDescriptor {
        MailAttachmentDescriptor(id: id, messageID: messageID, filename: filename, mimeType: mimeType, byteCount: data.count, contentID: contentID, isInline: isInline, contentHash: contentHash)
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
        messageID: String? = nil,
        attachments: [OutboundMailAttachment] = []
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
        try attachments.forEach(validateAttachment)

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

        let bodyPart = buildBodyPart(draft: draft)
        let rawBody: String
        if attachments.isEmpty {
            headers.append(contentsOf: bodyPart.headers)
            rawBody = bodyPart.body
        } else {
            let mixedBoundary = "connor-mixed-\(UUID().uuidString)"
            headers.append("Content-Type: multipart/mixed; boundary=\"\(mixedBoundary)\"")
            rawBody = buildMixedBody(boundary: mixedBoundary, bodyPart: bodyPart, attachments: attachments)
        }

        let raw = headers.joined(separator: "\r\n") + "\r\n\r\n" + rawBody
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
        messageID: String? = nil,
        attachments: [OutboundMailAttachment] = []
    ) throws -> ComposedMailMessage {
        try compose(draft: draft, from: identity.address, date: date, messageID: messageID, attachments: attachments)
    }

    public static func dotStuff(_ rawMessage: String) -> String {
        rawMessage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in line.hasPrefix(".") ? ".\(line)" : line }
            .joined(separator: "\r\n")
    }

    private struct BodyPart {
        var headers: [String]
        var body: String
    }

    private func buildBodyPart(draft: MailDraft) -> BodyPart {
        if let htmlBody = draft.htmlBody, !htmlBody.isEmpty {
            let boundary = "connor-alt-\(UUID().uuidString)"
            let body = [
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
            return BodyPart(headers: ["Content-Type: multipart/alternative; boundary=\"\(boundary)\""], body: body)
        }
        return BodyPart(headers: ["Content-Type: text/plain; charset=utf-8", "Content-Transfer-Encoding: 8bit"], body: normalizeBody(draft.body))
    }

    private func buildMixedBody(boundary: String, bodyPart: BodyPart, attachments: [OutboundMailAttachment]) -> String {
        var parts: [String] = []
        parts.append("--\(boundary)")
        parts.append(contentsOf: bodyPart.headers)
        parts.append("")
        parts.append(bodyPart.body)
        for attachment in attachments {
            parts.append("--\(boundary)")
            parts.append("Content-Type: \(attachment.mimeType); name=\"\(attachment.filename)\"")
            parts.append("Content-Transfer-Encoding: base64")
            parts.append("Content-Disposition: \(attachment.isInline ? "inline" : "attachment"); filename=\"\(attachment.filename)\"")
            if let contentID = attachment.contentID { parts.append("Content-ID: <\(contentID)>") }
            parts.append("")
            parts.append(attachment.data.base64EncodedString())
        }
        parts.append("--\(boundary)--")
        parts.append("")
        return parts.joined(separator: "\r\n")
    }

    private func validateAddress(_ address: MailAddress, field: String) throws {
        if let name = address.name { try validateHeaderValue(name, field: field) }
        try validateHeaderValue(address.email, field: field)
    }

    private func validateAttachment(_ attachment: OutboundMailAttachment) throws {
        try validateHeaderValue(attachment.filename, field: "Attachment filename")
        try validateHeaderValue(attachment.mimeType, field: "Attachment MIME type")
        if attachment.filename.contains("/") || attachment.filename.contains("\\") || attachment.filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MailMessageComposerError.unsafeAttachmentFilename(attachment.filename)
        }
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
