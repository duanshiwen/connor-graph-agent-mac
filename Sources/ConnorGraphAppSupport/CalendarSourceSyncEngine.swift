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
    public var collections: [CalendarCollection]
    public var events: [CalendarEvent]

    public init(
        accountID: CalendarAccountID,
        sourceKind: CalendarSourceKind,
        insertedEvents: Int = 0,
        updatedEvents: Int = 0,
        deletedEvents: Int = 0,
        unchangedEvents: Int = 0,
        updatedCollections: Int = 0,
        diagnostics: [CalendarSourceSyncDiagnostic] = [],
        collections: [CalendarCollection] = [],
        events: [CalendarEvent] = []
    ) {
        self.accountID = accountID
        self.sourceKind = sourceKind
        self.insertedEvents = insertedEvents
        self.updatedEvents = updatedEvents
        self.deletedEvents = deletedEvents
        self.unchangedEvents = unchangedEvents
        self.updatedCollections = updatedCollections
        self.diagnostics = diagnostics
        self.collections = collections
        self.events = events
    }
}

public enum CalendarSourceSyncDiagnosticSeverity: String, Sendable, Codable, Equatable, Hashable {
    case info
    case warning
    case error
}

public struct CalendarSourceSyncDiagnostic: Sendable, Codable, Equatable, Hashable {
    public var accountID: CalendarAccountID?
    public var collectionID: CalendarID?
    public var severity: CalendarSourceSyncDiagnosticSeverity
    public var code: String
    public var summary: String
    public var message: String
    public var isRetryable: Bool
    public var occurredAt: Date?

    public init(code: String, summary: String, isRetryable: Bool = false) {
        self.accountID = nil
        self.collectionID = nil
        self.severity = .info
        self.code = code
        self.summary = summary
        self.message = summary
        self.isRetryable = isRetryable
        self.occurredAt = nil
    }

    public init(
        accountID: CalendarAccountID? = nil,
        collectionID: CalendarID? = nil,
        severity: CalendarSourceSyncDiagnosticSeverity,
        code: String,
        message: String,
        isRetryable: Bool = false,
        occurredAt: Date? = nil
    ) {
        self.accountID = accountID
        self.collectionID = collectionID
        self.severity = severity
        self.code = code
        self.summary = message
        self.message = message
        self.isRetryable = isRetryable
        self.occurredAt = occurredAt
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
    private let runtimeStore: FileBackedCalendarSourceRuntimeStore?
    private let backoffPolicy: CalendarSyncBackoffPolicy

    public init(connectors: [any CalendarSourceConnector], runtimeStore: FileBackedCalendarSourceRuntimeStore? = nil, backoffPolicy: CalendarSyncBackoffPolicy = CalendarSyncBackoffPolicy()) {
        self.connectors = Dictionary(uniqueKeysWithValues: connectors.map { ($0.kind, $0) })
        self.runtimeStore = runtimeStore
        self.backoffPolicy = backoffPolicy
    }

    public func sync(request: CalendarSourceSyncRequest) async throws -> CalendarSourceSyncResult {
        let attemptedAt = Date()
        guard request.account.configuration.syncMode == .readOnly else {
            let error = CalendarSourceSyncError.writeNotSupported(request.account.sourceKind)
            try await recordFailureIfNeeded(account: request.account, code: "writeNotSupported", message: "Calendar source \(request.account.sourceKind.rawValue) is not configured for read-only sync", error: error, attemptedAt: attemptedAt)
            throw error
        }
        guard let connector = connectors[request.account.sourceKind] else {
            let error = CalendarSourceSyncError.unsupportedSourceKind(request.account.sourceKind)
            try await recordFailureIfNeeded(account: request.account, code: "unsupportedSourceKind", message: "No calendar connector is registered for \(request.account.sourceKind.rawValue)", error: error, attemptedAt: attemptedAt)
            throw error
        }
        do {
            let result = try await connector.sync(request: request)
            try await runtimeStore?.applySyncResult(result, account: request.account, attemptedAt: attemptedAt, backoffPolicy: backoffPolicy)
            return result
        } catch {
            try await recordFailureIfNeeded(account: request.account, code: "syncFailed", message: String(describing: error), error: error, attemptedAt: attemptedAt)
            throw error
        }
    }

    private func recordFailureIfNeeded(account: CalendarAccount, code: String, message: String, error: Error, attemptedAt: Date) async throws {
        let failure = CalendarSyncFailureRecord(
            occurredAt: attemptedAt,
            code: code,
            message: message,
            isCredentialRelated: message.localizedCaseInsensitiveContains("credential") || message.localizedCaseInsensitiveContains("unauthorized") || message.contains("401")
        )
        let diagnostic = CalendarSourceSyncDiagnostic(accountID: account.id, severity: .error, code: code, message: message, isRetryable: code != "writeNotSupported", occurredAt: attemptedAt)
        try await runtimeStore?.recordSyncFailure(account: account, failure: failure, diagnostics: [diagnostic], attemptedAt: attemptedAt, backoffPolicy: backoffPolicy)
        _ = error
    }
}
