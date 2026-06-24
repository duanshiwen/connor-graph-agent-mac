import Foundation

public struct CalendarAccountID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct CalendarID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct CalendarEventID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct CalendarAttendeeID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum CalendarSourceKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case macOSEventKit
    case genericCalDAV
    case appleICloudCalDAV
    case fastmailCalDAV
    case nextcloudCalDAV
    case googleCalendar
    case microsoft365Calendar
    case icsSubscription

    public var displayName: String {
        switch self {
        case .macOSEventKit: "macOS Calendar / EventKit"
        case .genericCalDAV: "标准 CalDAV"
        case .appleICloudCalDAV: "Apple iCloud CalDAV"
        case .fastmailCalDAV: "Fastmail CalDAV"
        case .nextcloudCalDAV: "Nextcloud CalDAV"
        case .googleCalendar: "Google Calendar"
        case .microsoft365Calendar: "Microsoft 365 Calendar"
        case .icsSubscription: "ICS / Webcal 订阅"
        }
    }

    public var supportsWrite: Bool { false }

    public static func legacyProviderMapping(_ provider: ConnectedAccountProviderKind) -> CalendarSourceKind {
        switch provider {
        case .localFixture:
            return .macOSEventKit
        case .appleICloud:
            return .appleICloudCalDAV
        case .google:
            return .googleCalendar
        case .microsoft365:
            return .microsoft365Calendar
        case .genericCalDAVCardDAV:
            return .genericCalDAV
        case .qq, .netEase, .genericIMAPSMTP:
            return .genericCalDAV
        }
    }

    public var legacyProvider: ConnectedAccountProviderKind {
        switch self {
        case .macOSEventKit:
            return .localFixture
        case .appleICloudCalDAV:
            return .appleICloud
        case .googleCalendar:
            return .google
        case .microsoft365Calendar:
            return .microsoft365
        case .genericCalDAV, .fastmailCalDAV, .nextcloudCalDAV:
            return .genericCalDAVCardDAV
        case .icsSubscription:
            return .genericCalDAVCardDAV
        }
    }
}

public enum CalendarSourceAuthMode: String, Codable, Sendable, Equatable, Hashable {
    case none
    case basic
    case appPassword
    case oauth2
    case bearerToken
}

public enum CalendarSourceSyncMode: String, Codable, Sendable, Equatable, Hashable {
    case readOnly
}

public struct CalendarCredentialBinding: Codable, Sendable, Equatable, Hashable {
    public var keychainService: String
    public var accountName: String
    public var authMode: CalendarSourceAuthMode

    public init(keychainService: String, accountName: String, authMode: CalendarSourceAuthMode) {
        self.keychainService = keychainService
        self.accountName = accountName
        self.authMode = authMode
    }
}

public struct CalendarSourceConfiguration: Codable, Sendable, Equatable, Hashable {
    public var sourceKind: CalendarSourceKind
    public var authMode: CalendarSourceAuthMode
    public var syncMode: CalendarSourceSyncMode
    public var serverURL: URL?
    public var username: String?
    public var principalURL: URL?
    public var calendarHomeSetURL: URL?
    public var subscriptionURL: URL?
    public var syncWindowPastDays: Int
    public var syncWindowFutureDays: Int
    public var enabledCollectionIDs: [CalendarID]
    public var providerMetadata: [String: String]

    public init(
        sourceKind: CalendarSourceKind,
        authMode: CalendarSourceAuthMode = .none,
        syncMode: CalendarSourceSyncMode = .readOnly,
        serverURL: URL? = nil,
        username: String? = nil,
        principalURL: URL? = nil,
        calendarHomeSetURL: URL? = nil,
        subscriptionURL: URL? = nil,
        syncWindowPastDays: Int = 30,
        syncWindowFutureDays: Int = 365,
        enabledCollectionIDs: [CalendarID] = [],
        providerMetadata: [String: String] = [:]
    ) {
        self.sourceKind = sourceKind
        self.authMode = authMode
        self.syncMode = syncMode
        self.serverURL = serverURL
        self.username = username
        self.principalURL = principalURL
        self.calendarHomeSetURL = calendarHomeSetURL
        self.subscriptionURL = subscriptionURL
        self.syncWindowPastDays = max(0, syncWindowPastDays)
        self.syncWindowFutureDays = max(1, syncWindowFutureDays)
        self.enabledCollectionIDs = enabledCollectionIDs
        self.providerMetadata = providerMetadata
    }

    public static func migrated(from provider: ConnectedAccountProviderKind) -> CalendarSourceConfiguration {
        let sourceKind = CalendarSourceKind.legacyProviderMapping(provider)
        let authMode: CalendarSourceAuthMode
        switch sourceKind {
        case .macOSEventKit, .icsSubscription:
            authMode = .none
        case .googleCalendar, .microsoft365Calendar:
            authMode = .oauth2
        case .genericCalDAV, .appleICloudCalDAV, .fastmailCalDAV, .nextcloudCalDAV:
            authMode = .appPassword
        }
        return CalendarSourceConfiguration(sourceKind: sourceKind, authMode: authMode)
    }
}

public enum CalendarAccountHealthStatus: String, Codable, Sendable, Equatable, Hashable {
    case ready
    case syncing
    case degraded
    case blocked
    case unauthenticated
    case rateLimited
    case needsConfiguration
    case unknown
}

public struct CalendarAccountHealth: Codable, Sendable, Equatable, Hashable {
    public var status: CalendarAccountHealthStatus
    public var checkedAt: Date
    public var summary: String
    public var blockingReasons: [String]

    public init(status: CalendarAccountHealthStatus, checkedAt: Date = Date(), summary: String, blockingReasons: [String] = []) {
        self.status = status
        self.checkedAt = checkedAt
        self.summary = summary
        self.blockingReasons = blockingReasons
    }
}

public struct CalendarAccount: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: CalendarAccountID
    public var connectedAccountID: ConnectedAccountID?
    public var provider: ConnectedAccountProviderKind
    public var sourceKind: CalendarSourceKind
    public var displayName: String
    public var credentialBinding: ConnectedAccountCredentialBinding?
    public var configuration: CalendarSourceConfiguration
    public var health: CalendarAccountHealth
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: CalendarAccountID,
        connectedAccountID: ConnectedAccountID? = nil,
        provider: ConnectedAccountProviderKind,
        sourceKind: CalendarSourceKind? = nil,
        displayName: String,
        credentialBinding: ConnectedAccountCredentialBinding? = nil,
        configuration: CalendarSourceConfiguration? = nil,
        health: CalendarAccountHealth = CalendarAccountHealth(status: .unknown, summary: "Not checked"),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let resolvedSourceKind = sourceKind ?? CalendarSourceKind.legacyProviderMapping(provider)
        self.id = id
        self.connectedAccountID = connectedAccountID
        self.provider = provider
        self.sourceKind = resolvedSourceKind
        self.displayName = displayName
        self.credentialBinding = credentialBinding
        self.configuration = configuration ?? CalendarSourceConfiguration.migrated(from: provider)
        self.health = health
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case connectedAccountID
        case provider
        case sourceKind
        case displayName
        case credentialBinding
        case configuration
        case health
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CalendarAccountID.self, forKey: .id)
        connectedAccountID = try container.decodeIfPresent(ConnectedAccountID.self, forKey: .connectedAccountID)
        provider = try container.decodeIfPresent(ConnectedAccountProviderKind.self, forKey: .provider) ?? .genericCalDAVCardDAV
        sourceKind = try container.decodeIfPresent(CalendarSourceKind.self, forKey: .sourceKind) ?? CalendarSourceKind.legacyProviderMapping(provider)
        displayName = try container.decode(String.self, forKey: .displayName)
        credentialBinding = try container.decodeIfPresent(ConnectedAccountCredentialBinding.self, forKey: .credentialBinding)
        configuration = try container.decodeIfPresent(CalendarSourceConfiguration.self, forKey: .configuration) ?? CalendarSourceConfiguration.migrated(from: provider)
        if configuration.sourceKind != sourceKind {
            configuration.sourceKind = sourceKind
        }
        health = try container.decodeIfPresent(CalendarAccountHealth.self, forKey: .health) ?? CalendarAccountHealth(status: .unknown, summary: "Not checked")
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

public struct CalendarCollection: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: CalendarID
    public var accountID: CalendarAccountID
    public var displayName: String
    public var colorHex: String?
    public var isReadOnly: Bool
    public var source: String

    public init(id: CalendarID, accountID: CalendarAccountID, displayName: String, colorHex: String? = nil, isReadOnly: Bool = false, source: String = "connor-cache") {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self.colorHex = colorHex
        self.isReadOnly = isReadOnly
        self.source = source
    }
}

public struct CalendarEventDateTime: Codable, Sendable, Equatable, Hashable {
    public var date: Date
    public var timeZoneIdentifier: String?

    public init(date: Date, timeZoneIdentifier: String? = nil) {
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public enum CalendarAttendeeRole: String, Codable, Sendable, Equatable, Hashable {
    case required
    case optional
    case resource
    case unknown
}

public enum CalendarAttendeeResponseStatus: String, Codable, Sendable, Equatable, Hashable {
    case needsAction
    case accepted
    case declined
    case tentative
    case delegated
    case unknown
}

public struct CalendarAttendee: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: CalendarAttendeeID
    public var name: String?
    public var email: String?
    public var role: CalendarAttendeeRole
    public var responseStatus: CalendarAttendeeResponseStatus

    public init(id: CalendarAttendeeID, name: String? = nil, email: String? = nil, role: CalendarAttendeeRole = .unknown, responseStatus: CalendarAttendeeResponseStatus = .unknown) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.responseStatus = responseStatus
    }
}

public struct CalendarRecurrenceSummary: Codable, Sendable, Equatable, Hashable {
    public var ruleDescription: String

    public init(ruleDescription: String) {
        self.ruleDescription = ruleDescription
    }
}

public struct CalendarEvent: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: CalendarEventID
    public var calendarID: CalendarID
    public var title: String
    public var start: CalendarEventDateTime
    public var end: CalendarEventDateTime
    public var isAllDay: Bool
    public var location: String?
    public var url: URL?
    public var notes: String?
    public var attendees: [CalendarAttendee]
    public var recurrenceSummary: CalendarRecurrenceSummary?
    public var updatedAt: Date

    public init(
        id: CalendarEventID,
        calendarID: CalendarID,
        title: String,
        start: CalendarEventDateTime,
        end: CalendarEventDateTime,
        isAllDay: Bool = false,
        location: String? = nil,
        url: URL? = nil,
        notes: String? = nil,
        attendees: [CalendarAttendee] = [],
        recurrenceSummary: CalendarRecurrenceSummary? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.url = url
        self.notes = notes
        self.attendees = attendees
        self.recurrenceSummary = recurrenceSummary
        self.updatedAt = updatedAt
    }

    public var durationSeconds: TimeInterval {
        end.date.timeIntervalSince(start.date)
    }
}

public struct CalendarFreeBusyBlock: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var calendarID: CalendarID
    public var start: Date
    public var end: Date

    public init(id: String = UUID().uuidString, calendarID: CalendarID, start: Date, end: Date) {
        self.id = id
        self.calendarID = calendarID
        self.start = start
        self.end = end
    }
}

public struct CalendarSourceSyncCursor: Codable, Sendable, Equatable, Hashable {
    public var syncToken: String?
    public var etag: String?
    public var lastSeenEventIDs: [CalendarEventID]

    public init(syncToken: String? = nil, etag: String? = nil, lastSeenEventIDs: [CalendarEventID] = []) {
        self.syncToken = syncToken
        self.etag = etag
        self.lastSeenEventIDs = lastSeenEventIDs
    }
}

public struct CalendarSyncFailureRecord: Codable, Sendable, Equatable, Hashable {
    public var occurredAt: Date
    public var code: String
    public var message: String
    public var isCredentialRelated: Bool

    public init(occurredAt: Date = Date(), code: String, message: String, isCredentialRelated: Bool = false) {
        self.occurredAt = occurredAt
        self.code = code
        self.message = message
        self.isCredentialRelated = isCredentialRelated
    }
}

public struct CalendarCollectionSyncState: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: CalendarID { collectionID }
    public var collectionID: CalendarID
    public var cursor: CalendarSourceSyncCursor
    public var lastSuccessfulSyncAt: Date?
    public var eventCount: Int

    public init(collectionID: CalendarID, cursor: CalendarSourceSyncCursor = CalendarSourceSyncCursor(), lastSuccessfulSyncAt: Date? = nil, eventCount: Int = 0) {
        self.collectionID = collectionID
        self.cursor = cursor
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.eventCount = max(0, eventCount)
    }
}

public struct CalendarAccountSyncState: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: CalendarAccountID { accountID }
    public var accountID: CalendarAccountID
    public var sourceKind: CalendarSourceKind
    public var lastAttemptedSyncAt: Date?
    public var lastSuccessfulSyncAt: Date?
    public var failureCount: Int
    public var nextRetryAt: Date?
    public var lastFailure: CalendarSyncFailureRecord?
    public var collectionStates: [CalendarCollectionSyncState]

    public init(
        accountID: CalendarAccountID,
        sourceKind: CalendarSourceKind,
        lastAttemptedSyncAt: Date? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        failureCount: Int = 0,
        nextRetryAt: Date? = nil,
        lastFailure: CalendarSyncFailureRecord? = nil,
        collectionStates: [CalendarCollectionSyncState] = []
    ) {
        self.accountID = accountID
        self.sourceKind = sourceKind
        self.lastAttemptedSyncAt = lastAttemptedSyncAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.failureCount = max(0, failureCount)
        self.nextRetryAt = nextRetryAt
        self.lastFailure = lastFailure
        self.collectionStates = collectionStates
    }
}

public struct CalendarSyncBackoffPolicy: Codable, Sendable, Equatable, Hashable {
    public var initialDelaySeconds: TimeInterval
    public var multiplier: Double
    public var maxDelaySeconds: TimeInterval

    public init(initialDelaySeconds: TimeInterval = 60, multiplier: Double = 2, maxDelaySeconds: TimeInterval = 3_600) {
        self.initialDelaySeconds = max(0, initialDelaySeconds)
        self.multiplier = max(1, multiplier)
        self.maxDelaySeconds = max(self.initialDelaySeconds, maxDelaySeconds)
    }

    public func delaySeconds(failureCount: Int) -> TimeInterval {
        guard failureCount > 0, initialDelaySeconds > 0 else { return 0 }
        let exponent = max(0, failureCount - 1)
        let delay = initialDelaySeconds * pow(multiplier, Double(exponent))
        return min(delay, maxDelaySeconds)
    }
}

public enum CalendarMutationKind: String, Codable, Sendable, Equatable, Hashable {
    case createEvent
    case updateEvent
    case deleteEvent
    case respondToInvite
}

public struct CalendarWriteReceipt: Codable, Sendable, Equatable, Hashable {
    public var mutationKind: CalendarMutationKind
    public var eventID: CalendarEventID?
    public var approved: Bool
    public var summary: String

    public init(mutationKind: CalendarMutationKind, eventID: CalendarEventID? = nil, approved: Bool, summary: String) {
        self.mutationKind = mutationKind
        self.eventID = eventID
        self.approved = approved
        self.summary = summary
    }
}
