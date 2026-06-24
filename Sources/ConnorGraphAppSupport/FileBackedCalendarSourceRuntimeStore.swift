import Foundation
import ConnorGraphCore

public struct CalendarSourceRuntimeSnapshot: Codable, Sendable, Equatable {
    public var accounts: [CalendarAccount]
    public var collections: [CalendarCollection]
    public var events: [CalendarEvent]
    public var syncStates: [CalendarAccountSyncState]
    public var diagnostics: [CalendarSourceSyncDiagnostic]

    public init(
        accounts: [CalendarAccount] = [],
        collections: [CalendarCollection] = [],
        events: [CalendarEvent] = [],
        syncStates: [CalendarAccountSyncState] = [],
        diagnostics: [CalendarSourceSyncDiagnostic] = []
    ) {
        self.accounts = accounts
        self.collections = collections
        self.events = events
        self.syncStates = syncStates
        self.diagnostics = diagnostics
    }

    public static let empty = CalendarSourceRuntimeSnapshot()
}

public actor FileBackedCalendarSourceRuntimeStore: CalendarSourceRepository {
    private let storeURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storeURL = storagePaths.applicationSupportDirectory
            .appendingPathComponent("calendar", isDirectory: true)
            .appendingPathComponent("calendar-runtime-store.json")
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

    public func listAccounts() async throws -> [CalendarAccount] {
        try await loadSnapshot().accounts
    }

    public func loadSnapshot() async throws -> CalendarSourceRuntimeSnapshot {
        let snapshot = try load()
        return CalendarSourceRuntimeSnapshot(
            accounts: snapshot.accounts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            collections: snapshot.collections.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            events: snapshot.events.sorted { lhs, rhs in
                if lhs.start.date == rhs.start.date { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
                return lhs.start.date < rhs.start.date
            },
            syncStates: snapshot.syncStates.sorted { $0.accountID.rawValue.localizedStandardCompare($1.accountID.rawValue) == .orderedAscending },
            diagnostics: snapshot.diagnostics.sorted { lhs, rhs in
                let left = lhs.occurredAt ?? .distantPast
                let right = rhs.occurredAt ?? .distantPast
                if left == right { return lhs.code.localizedStandardCompare(rhs.code) == .orderedAscending }
                return left < right
            }
        )
    }

    public func saveSnapshot(_ snapshot: CalendarSourceRuntimeSnapshot) async throws {
        try save(snapshot)
    }

    public func upsertAccounts(_ accounts: [CalendarAccount]) async throws {
        var snapshot = try load()
        var byID = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.id, $0) })
        for account in accounts { byID[account.id] = account }
        snapshot.accounts = Array(byID.values)
        try save(snapshot)
    }

    public func applySyncResult(_ result: CalendarSourceSyncResult, account: CalendarAccount, attemptedAt: Date = Date(), backoffPolicy: CalendarSyncBackoffPolicy = CalendarSyncBackoffPolicy()) async throws {
        var snapshot = try load()
        snapshot.accounts = upserting(account, into: snapshot.accounts, by: \CalendarAccount.id)
        snapshot.collections.removeAll { $0.accountID == account.id }
        snapshot.collections.append(contentsOf: result.collections)
        let syncedCollectionIDs = Set(result.collections.map(\.id))
        if !syncedCollectionIDs.isEmpty {
            snapshot.events.removeAll { syncedCollectionIDs.contains($0.calendarID) }
        }
        snapshot.events.append(contentsOf: result.events)
        snapshot.diagnostics.removeAll { $0.accountID == account.id }
        snapshot.diagnostics.append(contentsOf: result.diagnostics.map { diagnostic in
            var copy = diagnostic
            if copy.accountID == nil { copy.accountID = account.id }
            if copy.occurredAt == nil { copy.occurredAt = attemptedAt }
            return copy
        })
        let collectionStates = result.collections.map { collection in
            CalendarCollectionSyncState(
                collectionID: collection.id,
                lastSuccessfulSyncAt: attemptedAt,
                eventCount: result.events.filter { $0.calendarID == collection.id }.count
            )
        }
        let state = CalendarAccountSyncState(
            accountID: account.id,
            sourceKind: account.sourceKind,
            lastAttemptedSyncAt: attemptedAt,
            lastSuccessfulSyncAt: attemptedAt,
            failureCount: 0,
            nextRetryAt: nil,
            lastFailure: nil,
            collectionStates: collectionStates
        )
        snapshot.syncStates = upserting(state, into: snapshot.syncStates, by: \CalendarAccountSyncState.accountID)
        _ = backoffPolicy
        try save(snapshot)
    }

    public func recordSyncFailure(account: CalendarAccount, failure: CalendarSyncFailureRecord, diagnostics: [CalendarSourceSyncDiagnostic] = [], attemptedAt: Date = Date(), backoffPolicy: CalendarSyncBackoffPolicy = CalendarSyncBackoffPolicy()) async throws {
        var snapshot = try load()
        snapshot.accounts = upserting(account, into: snapshot.accounts, by: \CalendarAccount.id)
        let existing = snapshot.syncStates.first { $0.accountID == account.id }
        let failureCount = (existing?.failureCount ?? 0) + 1
        let nextRetry = attemptedAt.addingTimeInterval(backoffPolicy.delaySeconds(failureCount: failureCount))
        let state = CalendarAccountSyncState(
            accountID: account.id,
            sourceKind: account.sourceKind,
            lastAttemptedSyncAt: attemptedAt,
            lastSuccessfulSyncAt: existing?.lastSuccessfulSyncAt,
            failureCount: failureCount,
            nextRetryAt: nextRetry,
            lastFailure: failure,
            collectionStates: existing?.collectionStates ?? []
        )
        snapshot.syncStates = upserting(state, into: snapshot.syncStates, by: \CalendarAccountSyncState.accountID)
        snapshot.diagnostics.removeAll { $0.accountID == account.id }
        snapshot.diagnostics.append(contentsOf: diagnostics.map { diagnostic in
            var copy = diagnostic
            if copy.accountID == nil { copy.accountID = account.id }
            if copy.occurredAt == nil { copy.occurredAt = attemptedAt }
            return copy
        })
        try save(snapshot)
    }

    public func deleteAccountScopedData(accountID: CalendarAccountID) async throws {
        var snapshot = try load()
        let removedCollectionIDs = Set(snapshot.collections.filter { $0.accountID == accountID }.map(\.id))
        snapshot.accounts.removeAll { $0.id == accountID }
        snapshot.collections.removeAll { $0.accountID == accountID }
        snapshot.events.removeAll { removedCollectionIDs.contains($0.calendarID) }
        snapshot.syncStates.removeAll { $0.accountID == accountID }
        snapshot.diagnostics.removeAll { $0.accountID == accountID }
        try save(snapshot)
    }

    private func load() throws -> CalendarSourceRuntimeSnapshot {
        guard fileManager.fileExists(atPath: storeURL.path) else { return .empty }
        let data = try Data(contentsOf: storeURL)
        guard !data.isEmpty else { return .empty }
        return try decoder.decode(CalendarSourceRuntimeSnapshot.self, from: data)
    }

    private func save(_ snapshot: CalendarSourceRuntimeSnapshot) throws {
        try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: storeURL, options: [.atomic])
    }

    private func upserting<Element, ID: Hashable>(_ element: Element, into elements: [Element], by keyPath: KeyPath<Element, ID>) -> [Element] {
        var byID = Dictionary(uniqueKeysWithValues: elements.map { ($0[keyPath: keyPath], $0) })
        byID[element[keyPath: keyPath]] = element
        return Array(byID.values)
    }
}
