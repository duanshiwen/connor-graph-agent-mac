import Foundation
import ConnorGraphCore

public actor FileBackedMailSourceStore: MailSourceRepository, TimeAwareMailSourceCache {
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
    private let searchService: (any NativeSourceSearchBackend)?
    private var hasPrimedSearchIndex: Bool

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default, searchService: (any NativeSourceSearchBackend)? = nil) {
        self.storeURL = storagePaths.applicationSupportDirectory
            .appendingPathComponent("mail", isDirectory: true)
            .appendingPathComponent("mail-store.json")
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.searchService = searchService
        self.hasPrimedSearchIndex = false
    }

    public init(storeURL: URL, fileManager: FileManager = .default, searchService: (any NativeSourceSearchBackend)? = nil) {
        self.storeURL = storeURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.searchService = searchService
        self.hasPrimedSearchIndex = false
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
        try await searchService?.upsert([NativeSourceSearchAdapters.mailDocument(from: message)])
    }

    /// Batch save messages — single load+save cycle for the entire batch (much faster than per-message)
    public func saveMessagesBatch(_ messages: [MailMessageDetail]) async throws {
        guard !messages.isEmpty else { return }
        var snapshot = try load()
        let newIDs = Set(messages.map(\.id))
        snapshot.messages.removeAll { newIDs.contains($0.id) }
        snapshot.messages.append(contentsOf: messages)
        try save(snapshot)
        if let searchService {
            try await searchService.upsert(messages.map { NativeSourceSearchAdapters.mailDocument(from: $0) })
        }
    }

    public func searchMessages(query: String, accountID: MailAccountID?) async throws -> [MailMessageSummary] {
        try await searchMessages(query: query, accountID: accountID, temporalFilter: nil, temporalSort: .relevanceThenTimeDesc, limit: Int.max)
    }

    public func searchMessages(query: String, accountID: MailAccountID?, temporalFilter: NativeSearchTemporalFilter?, temporalSort: NativeSearchTemporalSort, limit: Int) async throws -> [MailMessageSummary] {
        let limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        let snapshot = try load()
        if let searchService {
            try await primeSearchIndexIfNeeded(snapshot: snapshot)
            let results = try await searchService.search(NativeSearchQuery(text: query, sourceKinds: [.mail], sourceInstanceIDs: accountID.map { Set([$0.rawValue]) }, temporalFilter: temporalFilter, temporalSort: temporalSort, limit: limit, rankingProfile: .recentFirst))
            let byID = Dictionary(uniqueKeysWithValues: snapshot.messages.map { ($0.id.rawValue, $0.summary) })
            return results.compactMap { byID[$0.externalID] }
        }
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = snapshot.messages.map(\.summary).filter { summary in
            if let accountID, summary.accountID != accountID { return false }
            if let temporalFilter, !temporalFilter.contains(NativeSearchTemporalMetadata(primaryTime: summary.date, primaryTimeKind: .sentAt, sentAt: summary.date), sourceKind: .mail) { return false }
            guard !normalized.isEmpty else { return true }
            return summary.subject.lowercased().contains(normalized)
                || summary.snippet.lowercased().contains(normalized)
                || summary.from.email.lowercased().contains(normalized)
                || (summary.from.name?.lowercased().contains(normalized) ?? false)
        }
        let sorted = filtered.sorted { lhs, rhs in temporalSort == .timeAscThenRelevance || temporalSort == .relevanceThenTimeAsc ? lhs.date < rhs.date : lhs.date > rhs.date }
        return Array(sorted.prefix(limit))
    }

    public func message(id: MailMessageID) async throws -> MailMessageDetail? {
        try load().messages.first { $0.id == id }
    }

    public func allMessageIDs() async throws -> [MailMessageID] {
        try load().messages.map(\.id)
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
        let changed = snapshot.messages.filter { ids.contains($0.id) }.map(NativeSourceSearchAdapters.mailDocument(from:))
        try await searchService?.upsert(changed)
    }

    public func presentation() async throws -> NativeMailBrowserPresentation {
        let snapshot = try load()
        return NativeMailBrowserPresentation(
            accounts: snapshot.accounts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            mailboxes: snapshot.mailboxes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            messages: snapshot.messages.map(\.summary).sorted { $0.date > $1.date }
        )
    }

    private func primeSearchIndexIfNeeded(snapshot: Snapshot) async throws {
        guard let searchService, !hasPrimedSearchIndex else { return }
        try await searchService.rebuildSource(kind: .mail, sourceInstanceID: nil, documents: snapshot.messages.map(NativeSourceSearchAdapters.mailDocument(from:)))
        hasPrimedSearchIndex = true
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
