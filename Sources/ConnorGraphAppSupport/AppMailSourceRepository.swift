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
