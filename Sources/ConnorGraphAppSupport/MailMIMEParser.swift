import Foundation
import ConnorGraphCore

public struct MailMIMEParser: Sendable, Equatable {
    public init() {}

    public func parsePlainMessage(raw: String, messageID: MailMessageID, summary: MailMessageSummary, maxBodyCharacters: Int = 16_000) -> MailMessageDetail {
        let parts = raw.components(separatedBy: "\n\n")
        let bodyText = parts.dropFirst().joined(separator: "\n\n")
        let truncated = bodyText.count > maxBodyCharacters
        let clipped = String(bodyText.prefix(maxBodyCharacters))
        let body = MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: clipped, byteCount: bodyText.utf8.count, wasTruncated: truncated), redactedPreview: String(clipped.prefix(500)), omittedReason: truncated ? "body-truncated" : nil, bodyHash: String(abs(bodyText.hashValue)))
        return MailMessageDetail(summary: summary, headers: MailMessageHeaders(messageIDHeader: messageID.rawValue, rawHeaderHash: String(abs(raw.hashValue))), body: body)
    }
}
