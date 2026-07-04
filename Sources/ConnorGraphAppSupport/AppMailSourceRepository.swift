import Foundation
import ConnorGraphCore

public protocol MailSourceRepository: Sendable {
    func listAccounts() async throws -> [MailAccount]
    func saveAccount(_ account: MailAccount) async throws
    func account(id: MailAccountID) async throws -> MailAccount?
}

/// Combined protocol for all mail store operations used by AppViewModel
public protocol MailStoreProtocol: MailSourceRepository, TimeAwareMailSourceCache {
    func saveMessagesBatch(_ messages: [MailMessageDetail]) async throws
    func allMessageIDs() async throws -> [MailMessageID]
    func presentation() async throws -> NativeMailBrowserPresentation
}

public enum MailBodyOnDemandFetchPlanner {
    public static func hasDisplayableBody(_ detail: MailMessageDetail) -> Bool {
        if detail.body?.plainText?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if detail.body?.htmlText?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if detail.body?.redactedPreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        return false
    }

    public static func imapUID(for detail: MailMessageDetail) -> String? {
        let prefix = "\(detail.summary.accountID.rawValue)-INBOX-"
        let rawValue = detail.id.rawValue
        guard rawValue.hasPrefix(prefix) else { return nil }
        let uid = String(rawValue.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty, uid.allSatisfy(\.isNumber) else { return nil }
        return uid
    }
}
