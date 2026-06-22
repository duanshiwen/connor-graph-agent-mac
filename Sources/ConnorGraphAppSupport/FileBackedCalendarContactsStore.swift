import Foundation
import ConnorGraphCore

public protocol CalendarSourceRepository: Sendable {
    func listAccounts() async throws -> [CalendarAccount]
}

public struct CalendarAccountSnapshotRepository: CalendarSourceRepository {
    public var accounts: [CalendarAccount]

    public init(accounts: [CalendarAccount]) {
        self.accounts = accounts
    }

    public func listAccounts() async throws -> [CalendarAccount] {
        accounts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

public actor FileBackedCalendarSourceStore: CalendarSourceRepository {
    public struct Snapshot: Codable, Sendable, Equatable {
        public var accounts: [CalendarAccount]
        public var collections: [CalendarCollection]
        public var events: [CalendarEvent]

        public init(accounts: [CalendarAccount] = [], collections: [CalendarCollection] = [], events: [CalendarEvent] = []) {
            self.accounts = accounts
            self.collections = collections
            self.events = events
        }

        public static let empty = Snapshot()
    }

    private let storeURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storeURL = storagePaths.applicationSupportDirectory
            .appendingPathComponent("calendar", isDirectory: true)
            .appendingPathComponent("calendar-store.json")
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
        try loadSnapshot().accounts
    }

    public func loadSnapshot() throws -> Snapshot {
        let snapshot = try load()
        return Snapshot(
            accounts: snapshot.accounts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            collections: snapshot.collections.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            events: snapshot.events.sorted { $0.start.date < $1.start.date }
        )
    }

    public func saveSnapshot(_ snapshot: Snapshot) throws {
        try save(snapshot)
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

public actor FileBackedContactSourceStore {
    public struct Snapshot: Codable, Sendable, Equatable {
        public var records: [ContactRecord]

        public init(records: [ContactRecord] = []) {
            self.records = records
        }

        public static let empty = Snapshot()
    }

    private let storeURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storeURL = storagePaths.applicationSupportDirectory
            .appendingPathComponent("contacts", isDirectory: true)
            .appendingPathComponent("contacts-store.json")
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

    public func loadRecords() throws -> [ContactRecord] {
        try load().records.sorted { lhs, rhs in
            let leftName = [lhs.givenName, lhs.familyName].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let rightName = [rhs.givenName, rhs.familyName].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return leftName.localizedStandardCompare(rightName) == .orderedAscending
        }
    }

    public func saveRecords(_ records: [ContactRecord]) throws {
        try save(Snapshot(records: records))
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
