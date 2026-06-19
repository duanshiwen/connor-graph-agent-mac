import Foundation
import ConnorGraphCore

public actor FileBackedMailSourceStore: MailSourceRepository, MailSourceCache {
    private struct Snapshot: Codable, Sendable, Equatable {
        var accounts: [MailAccount]
        var mailboxes: [MailMailbox]
        var messages: [MailMessageDetail]

        static let empty = Snapshot(accounts: [], mailboxes: [], messages: [])
    }

    private let storeURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storeURL = storagePaths.applicationSupportDirectory
            .appendingPathComponent("mail", isDirectory: true)
            .appendingPathComponent("mail-store.json")
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public init(storeURL: URL, fileManager: FileManager = .default) {
        self.storeURL = storeURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func listAccounts() async throws -> [MailAccount] {
        try load().accounts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func saveAccount(_ account: MailAccount) async throws {
        var snapshot = try load()
        snapshot.accounts.removeAll { $0.id == account.id }
        snapshot.accounts.append(account)
        try save(snapshot)
    }

    public func account(id: MailAccountID) async throws -> MailAccount? {
        try load().accounts.first { $0.id == id }
    }

    public func listMailboxes(accountID: MailAccountID) async throws -> [MailMailbox] {
        try load().mailboxes
            .filter { $0.accountID == accountID }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public func saveMailbox(_ mailbox: MailMailbox) async throws {
        var snapshot = try load()
        snapshot.mailboxes.removeAll { $0.id == mailbox.id }
        snapshot.mailboxes.append(mailbox)
        try save(snapshot)
    }

    public func saveMessage(_ message: MailMessageDetail) async throws {
        var snapshot = try load()
        snapshot.messages.removeAll { $0.id == message.id }
        snapshot.messages.append(message)
        try save(snapshot)
    }

    public func searchMessages(query: String, accountID: MailAccountID?) async throws -> [MailMessageSummary] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try load().messages.map(\.summary).filter { summary in
            if let accountID, summary.accountID != accountID { return false }
            guard !normalized.isEmpty else { return true }
            return summary.subject.lowercased().contains(normalized)
                || summary.snippet.lowercased().contains(normalized)
                || summary.from.email.lowercased().contains(normalized)
                || (summary.from.name?.lowercased().contains(normalized) ?? false)
        }.sorted { $0.date > $1.date }
    }

    public func message(id: MailMessageID) async throws -> MailMessageDetail? {
        try load().messages.first { $0.id == id }
    }

    public func updateFlags(messageIDs: [MailMessageID], transform: @Sendable (MailMessageFlags) -> MailMessageFlags) async throws {
        var snapshot = try load()
        let ids = Set(messageIDs)
        snapshot.messages = snapshot.messages.map { detail in
            guard ids.contains(detail.id) else { return detail }
            var copy = detail
            copy.summary.flags = transform(copy.summary.flags)
            return copy
        }
        try save(snapshot)
    }

    public func presentation() async throws -> NativeMailBrowserPresentation {
        let snapshot = try load()
        return NativeMailBrowserPresentation(
            accounts: snapshot.accounts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            mailboxes: snapshot.mailboxes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            messages: snapshot.messages.map(\.summary).sorted { $0.date > $1.date }
        )
    }

    private func load() throws -> Snapshot {
        guard fileManager.fileExists(atPath: storeURL.path) else { return .empty }
        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else { return .empty }
        return try decoder.decode(Snapshot.self, from: data)
    }

    private func save(_ snapshot: Snapshot) throws {
        try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: storeURL, options: [.atomic])
    }
}
