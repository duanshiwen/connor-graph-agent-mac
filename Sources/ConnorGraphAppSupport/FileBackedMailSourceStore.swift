import Foundation
import ConnorGraphCore

/// Backward-compatible facade kept for existing tests and call sites.
///
/// The commercial mail data source now persists through `SQLiteMailSourceStore` so that
/// message bodies, temporal metadata, and native-source search indexing share one path.
/// Older code/tests still instantiate `FileBackedMailSourceStore`; this wrapper maps the
/// legacy JSON-style URL to a SQLite database URL and delegates every operation.
public final class FileBackedMailSourceStore: MailStoreProtocol, @unchecked Sendable {
    private let store: SQLiteMailSourceStore

    public init(storeURL: URL, searchService: (any NativeSourceSearchBackend)? = nil) {
        let databaseURL = Self.databaseURL(fromLegacyStoreURL: storeURL)
        do {
            self.store = try SQLiteMailSourceStore(databaseURL: databaseURL, searchService: searchService)
        } catch {
            preconditionFailure("Unable to open mail source store at \(databaseURL.path): \(error)")
        }
    }

    public init(storagePaths: AppStoragePaths, searchService: (any NativeSourceSearchBackend)? = nil) {
        let databaseURL = storagePaths.applicationSupportDirectory
            .appendingPathComponent("mail", isDirectory: true)
            .appendingPathComponent("mail-source.sqlite")
        do {
            self.store = try SQLiteMailSourceStore(databaseURL: databaseURL, searchService: searchService)
        } catch {
            preconditionFailure("Unable to open mail source store at \(databaseURL.path): \(error)")
        }
    }

    private static func databaseURL(fromLegacyStoreURL url: URL) -> URL {
        let ext = url.pathExtension.lowercased()
        if ext == "sqlite" || ext == "sqlite3" || ext == "db" { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let filename = base.isEmpty ? "mail-source.sqlite" : "\(base).sqlite"
        return url.deletingLastPathComponent().appendingPathComponent(filename)
    }

    public func listAccounts() async throws -> [MailAccount] { try await store.listAccounts() }
    public func saveAccount(_ account: MailAccount) async throws { try await store.saveAccount(account) }
    public func account(id: MailAccountID) async throws -> MailAccount? { try await store.account(id: id) }
    public func listMailboxes(accountID: MailAccountID) async throws -> [MailMailbox] { try await store.listMailboxes(accountID: accountID) }
    public func saveMailbox(_ mailbox: MailMailbox) async throws { try await store.saveMailbox(mailbox) }
    public func saveMessage(_ message: MailMessageDetail) async throws { try await store.saveMessage(message) }
    public func saveMessagesBatch(_ messages: [MailMessageDetail]) async throws { try await store.saveMessagesBatch(messages) }
    public func searchMessages(query: String, accountID: MailAccountID?) async throws -> [MailMessageSummary] { try await store.searchMessages(query: query, accountID: accountID) }
    public func recentMessages(accountID: MailAccountID?, direction: MailMessageDirectionFilter, limit: Int) async throws -> [MailMessageSummary] {
        try await store.recentMessages(accountID: accountID, direction: direction, limit: limit)
    }
    public func searchMessages(query: String, accountID: MailAccountID?, temporalFilter: NativeSearchTemporalFilter?, temporalSort: NativeSearchTemporalSort, limit: Int) async throws -> [MailMessageSummary] {
        try await store.searchMessages(query: query, accountID: accountID, temporalFilter: temporalFilter, temporalSort: temporalSort, limit: limit)
    }
    public func message(id: MailMessageID) async throws -> MailMessageDetail? { try await store.message(id: id) }
    public func allMessageIDs() async throws -> [MailMessageID] { try await store.allMessageIDs() }
    public func clearCachedMailData() async throws { try await store.clearCachedMailData() }
    public func updateFlags(messageIDs: [MailMessageID], transform: @Sendable (MailMessageFlags) -> MailMessageFlags) async throws { try await store.updateFlags(messageIDs: messageIDs, transform: transform) }
    public func presentation() async throws -> NativeMailBrowserPresentation { try await store.presentation() }
}
