import Foundation
import ConnorGraphCore

public protocol MailAuditLogProtocol: Sendable {
    func record(_ record: MailAuditRecord) async throws
    func listRecords() async throws -> [MailAuditRecord]
}

public actor InMemoryMailSourceRepository: MailSourceRepository {
    private var accounts: [MailAccountID: MailAccount]

    public init(accounts: [MailAccount] = []) {
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    public func listAccounts() async throws -> [MailAccount] {
        accounts.values.sorted { $0.displayName < $1.displayName }
    }

    public func saveAccount(_ account: MailAccount) async throws {
        accounts[account.id] = account
    }

    public func account(id: MailAccountID) async throws -> MailAccount? {
        accounts[id]
    }
}

public actor InMemoryMailSourceCache: MailSourceCache, RecentMailSourceCache {
    private var mailboxes: [MailMailboxID: MailMailbox]
    private var messages: [MailMessageID: MailMessageDetail]

    public init(mailboxes: [MailMailbox] = [], messages: [MailMessageDetail] = []) {
        self.mailboxes = Dictionary(uniqueKeysWithValues: mailboxes.map { ($0.id, $0) })
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    }

    public func listMailboxes(accountID: MailAccountID) async throws -> [MailMailbox] {
        mailboxes.values.filter { $0.accountID == accountID }.sorted { $0.path < $1.path }
    }

    public func saveMailbox(_ mailbox: MailMailbox) async throws {
        mailboxes[mailbox.id] = mailbox
    }

    public func saveMessage(_ message: MailMessageDetail) async throws {
        messages[message.id] = message
    }

    public func searchMessages(query: String, accountID: MailAccountID?) async throws -> [MailMessageSummary] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return messages.values.map(\.summary).filter { summary in
            if let accountID, summary.accountID != accountID { return false }
            if normalized.isEmpty { return true }
            return summary.subject.lowercased().contains(normalized)
                || summary.snippet.lowercased().contains(normalized)
                || summary.from.email.lowercased().contains(normalized)
        }.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.rawValue < rhs.id.rawValue
        }
    }

    public func recentMessages(accountID: MailAccountID?, direction: MailMessageDirectionFilter, limit: Int) async throws -> [MailMessageSummary] {
        let limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        let filtered = messages.values.map(\.summary).filter { summary in
            if let accountID, summary.accountID != accountID { return false }
            switch direction {
            case .all:
                return true
            case .received:
                return mailboxes[summary.mailboxID]?.role != .sent
            case .sent:
                return mailboxes[summary.mailboxID]?.role == .sent
            }
        }.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.rawValue < rhs.id.rawValue
        }
        return Array(filtered.prefix(limit))
    }

    public func message(id: MailMessageID) async throws -> MailMessageDetail? {
        messages[id]
    }

    public func updateFlags(messageIDs: [MailMessageID], transform: @Sendable (MailMessageFlags) -> MailMessageFlags) async throws {
        for id in messageIDs {
            guard var detail = messages[id] else { continue }
            detail.summary.flags = transform(detail.summary.flags)
            messages[id] = detail
        }
    }
}

public actor InMemoryMailAuditLog: MailAuditLogProtocol {
    private var records: [MailAuditRecord] = []

    public init() {}

    public func record(_ record: MailAuditRecord) async throws {
        records.append(record)
    }

    public func listRecords() async throws -> [MailAuditRecord] {
        records
    }
}
