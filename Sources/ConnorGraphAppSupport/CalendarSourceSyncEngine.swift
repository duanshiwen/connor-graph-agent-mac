import Foundation
import ConnorGraphCore

public struct CalendarSourceValidationResult: Sendable, Equatable {
    public var sourceKind: CalendarSourceKind
    public var status: CalendarAccountHealthStatus
    public var summary: String
    public var blockingReasons: [String]

    public init(sourceKind: CalendarSourceKind, status: CalendarAccountHealthStatus, summary: String, blockingReasons: [String] = []) {
        self.sourceKind = sourceKind
        self.status = status
        self.summary = summary
        self.blockingReasons = blockingReasons
    }
}

public struct DiscoveredCalendarCollection: Sendable, Equatable, Identifiable {
    public var id: CalendarID
    public var displayName: String
    public var colorHex: String?
    public var isReadOnly: Bool

    public init(id: CalendarID, displayName: String, colorHex: String? = nil, isReadOnly: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.colorHex = colorHex
        self.isReadOnly = isReadOnly
    }
}

public struct CalendarSourceSyncRequest: Sendable, Equatable {
    public var account: CalendarAccount
    public var credential: String?
    public var runID: String?

    public init(account: CalendarAccount, credential: String? = nil, runID: String? = nil) {
        self.account = account
        self.credential = credential
        self.runID = runID
    }
}

public struct CalendarSourceSyncResult: Sendable, Equatable {
    public var accountID: CalendarAccountID
    public var sourceKind: CalendarSourceKind
    public var insertedEvents: Int
    public var updatedEvents: Int
    public var deletedEvents: Int
    public var unchangedEvents: Int
    public var updatedCollections: Int
    public var diagnostics: [CalendarSourceSyncDiagnostic]

    public init(
        accountID: CalendarAccountID,
        sourceKind: CalendarSourceKind,
        insertedEvents: Int = 0,
        updatedEvents: Int = 0,
        deletedEvents: Int = 0,
        unchangedEvents: Int = 0,
        updatedCollections: Int = 0,
        diagnostics: [CalendarSourceSyncDiagnostic] = []
    ) {
        self.accountID = accountID
        self.sourceKind = sourceKind
        self.insertedEvents = insertedEvents
        self.updatedEvents = updatedEvents
        self.deletedEvents = deletedEvents
        self.unchangedEvents = unchangedEvents
        self.updatedCollections = updatedCollections
        self.diagnostics = diagnostics
    }
}

public struct CalendarSourceSyncDiagnostic: Sendable, Codable, Equatable, Hashable {
    public var code: String
    public var summary: String
    public var isRetryable: Bool

    public init(code: String, summary: String, isRetryable: Bool = false) {
        self.code = code
        self.summary = summary
        self.isRetryable = isRetryable
    }
}

public enum CalendarSourceSyncError: Error, Sendable, Equatable {
    case unsupportedSourceKind(CalendarSourceKind)
    case writeNotSupported(CalendarSourceKind)
}

public protocol CalendarSourceConnector: Sendable {
    var kind: CalendarSourceKind { get }

    func validate(configuration: CalendarSourceConfiguration, credential: String?) async throws -> CalendarSourceValidationResult
    func discoverCalendars(configuration: CalendarSourceConfiguration, credential: String?) async throws -> [DiscoveredCalendarCollection]
    func sync(request: CalendarSourceSyncRequest) async throws -> CalendarSourceSyncResult
}

public struct CalendarSourceSyncEngine: Sendable {
    private let connectors: [CalendarSourceKind: any CalendarSourceConnector]

    public init(connectors: [any CalendarSourceConnector]) {
        self.connectors = Dictionary(uniqueKeysWithValues: connectors.map { ($0.kind, $0) })
    }

    public func sync(request: CalendarSourceSyncRequest) async throws -> CalendarSourceSyncResult {
        guard request.account.configuration.syncMode == .readOnly else {
            throw CalendarSourceSyncError.writeNotSupported(request.account.sourceKind)
        }
        guard let connector = connectors[request.account.sourceKind] else {
            throw CalendarSourceSyncError.unsupportedSourceKind(request.account.sourceKind)
        }
        return try await connector.sync(request: request)
    }
}
