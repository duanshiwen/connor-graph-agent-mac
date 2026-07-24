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

public struct MailMessagePageRequest: Sendable, Equatable {
    public var query: String
    public var accountID: MailAccountID?
    public var mailboxID: MailMailboxID?
    public var direction: MailMessageDirectionFilter
    public var pageSize: Int
    public var cursor: String?

    public init(
        query: String = "",
        accountID: MailAccountID? = nil,
        mailboxID: MailMailboxID? = nil,
        direction: MailMessageDirectionFilter = .all,
        pageSize: Int = 50,
        cursor: String? = nil
    ) {
        self.query = query
        self.accountID = accountID
        self.mailboxID = mailboxID
        self.direction = direction
        self.pageSize = min(max(pageSize, 1), 100)
        self.cursor = cursor
    }
}

public struct MailMessagePage: Sendable, Equatable {
    public var messages: [MailMessageSummary]
    public var nextCursor: String?

    public init(messages: [MailMessageSummary], nextCursor: String?) {
        self.messages = messages
        self.nextCursor = nextCursor
    }
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
