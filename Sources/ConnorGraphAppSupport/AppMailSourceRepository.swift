import Foundation
import ConnorGraphCore

public protocol MailSourceRepository: Sendable {
    func listAccounts() async throws -> [MailAccount]
    func saveAccount(_ account: MailAccount) async throws
    func account(id: MailAccountID) async throws -> MailAccount?
}

/// Combined protocol for mail store operations used by the app runtime
public protocol MailStoreProtocol: MailSourceRepository, TimeAwareMailSourceCache {
    func saveMessagesBatch(_ messages: [MailMessageDetail]) async throws
    func allMessageIDs() async throws -> [MailMessageID]
    func clearCachedMailData() async throws
    func presentation() async throws -> NativeMailBrowserPresentation
}

public enum MailBodyOnDemandFetchPlanner {
    public static func hasDisplayableBody(_ detail: MailMessageDetail) -> Bool {
        if isDisplayable(detail.body?.plainText?.text) { return true }
        if isDisplayable(detail.body?.htmlText?.text) { return true }
        if isDisplayable(detail.body?.redactedPreview) { return true }
        return false
    }

    public static func isLikelyEncodedGarbage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if looksLikeQuotedPrintableResidue(trimmed) { return true }
        if looksLikeBase64EncodedHTML(trimmed) { return true }
        return false
    }

    private static func isDisplayable(_ text: String?) -> Bool {
        guard let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !isLikelyEncodedGarbage(trimmed)
    }

    private static func looksLikeQuotedPrintableResidue(_ text: String) -> Bool {
        if text.contains("=\r\n") || text.contains("=\n") { return true }
        guard let regex = try? NSRegularExpression(pattern: #"=[0-9A-Fa-f]{2}"#) else { return false }
        let count = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        return count >= 3
    }

    private static func looksLikeBase64EncodedHTML(_ text: String) -> Bool {
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=\r\n\t ")
        let scalarCount = text.unicodeScalars.count
        guard scalarCount >= 48 else { return false }
        let allowedCount = text.unicodeScalars.filter { alphabet.contains(Character($0)) }.count
        guard Double(allowedCount) / Double(scalarCount) > 0.95 else { return false }
        var normalized = text.filter { !$0.isWhitespace }
        guard normalized.count >= 48 else { return false }
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data.prefix(256), encoding: .utf8) else { return false }
        let lower = decoded.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("<!doctype") || lower.hasPrefix("<html") || lower.hasPrefix("<body") || lower.contains("<html")
    }

    public static func imapUID(for detail: MailMessageDetail) -> String? {
        let accountID = detail.summary.accountID
        let supportedMailboxes = [
            RemoteIMAPMailbox(name: "INBOX", path: "INBOX", role: .inbox),
            RemoteIMAPMailbox(name: "Sent", path: "Sent", role: .sent)
        ]
        for mailbox in supportedMailboxes {
            guard let uid = mailbox.uid(fromMessageID: detail.id, accountID: accountID) else { continue }
            guard uid.allSatisfy(\.isNumber) else { return nil }
            return uid
        }
        return nil
    }
}
