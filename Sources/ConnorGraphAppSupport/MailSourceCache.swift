import Foundation
import ConnorGraphCore

public protocol MailSourceCache: Sendable {
    func listMailboxes(accountID: MailAccountID) async throws -> [MailMailbox]
    func saveMailbox(_ mailbox: MailMailbox) async throws
    func saveMessage(_ message: MailMessageDetail) async throws
    func searchMessages(query: String, accountID: MailAccountID?) async throws -> [MailMessageSummary]
    func message(id: MailMessageID) async throws -> MailMessageDetail?
    func updateFlags(messageIDs: [MailMessageID], transform: @Sendable (MailMessageFlags) -> MailMessageFlags) async throws
}

public protocol RecentMailSourceCache: MailSourceCache {
    func recentMessages(
        accountID: MailAccountID?,
        direction: MailMessageDirectionFilter,
        limit: Int
    ) async throws -> [MailMessageSummary]
}

public protocol TimeAwareMailSourceCache: MailSourceCache {
    func searchMessages(
        query: String,
        accountID: MailAccountID?,
        temporalFilter: NativeSearchTemporalFilter?,
        temporalSort: NativeSearchTemporalSort,
        limit: Int
    ) async throws -> [MailMessageSummary]
}
