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

    public var supportsWrite: Bool {
        switch self {
        case .macOSEventKit, .genericCalDAV, .appleICloudCalDAV, .fastmailCalDAV, .nextcloudCalDAV:
            return true
        case .googleCalendar, .microsoft365Calendar, .icsSubscription:
            return false
        }
    }

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
    case bidirectional
}

public struct CalendarCredentialBinding: Codable, Sendable, Equatable, Hashable {
    public var credentialNamespace: String
    public var accountName: String
    public var authMode: CalendarSourceAuthMode

    public init(credentialNamespace: String, accountName: String, authMode: CalendarSourceAuthMode) {
        self.credentialNamespace = credentialNamespace
        self.accountName = accountName
        self.authMode = authMode
    }

    private enum CodingKeys: String, CodingKey {
        case credentialNamespace
        case accountName
        case authMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credentialNamespace = try container.decode(String.self, forKey: .credentialNamespace)
        accountName = try container.decode(String.self, forKey: .accountName)
        authMode = try container.decode(CalendarSourceAuthMode.self, forKey: .authMode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentialNamespace, forKey: .credentialNamespace)
        try container.encode(accountName, forKey: .accountName)
        try container.encode(authMode, forKey: .authMode)
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

    private enum CodingKeys: String, CodingKey {
        case sourceKind, authMode, syncMode, serverURL, username, principalURL, calendarHomeSetURL, subscriptionURL, syncWindowPastDays, syncWindowFutureDays, enabledCollectionIDs, providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceKind = try container.decode(CalendarSourceKind.self, forKey: .sourceKind)
        authMode = try container.decodeIfPresent(CalendarSourceAuthMode.self, forKey: .authMode) ?? .none
        syncMode = try container.decodeIfPresent(CalendarSourceSyncMode.self, forKey: .syncMode) ?? .readOnly
        serverURL = try container.decodeIfPresent(URL.self, forKey: .serverURL)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        principalURL = try container.decodeIfPresent(URL.self, forKey: .principalURL)
        calendarHomeSetURL = try container.decodeIfPresent(URL.self, forKey: .calendarHomeSetURL)
        subscriptionURL = try container.decodeIfPresent(URL.self, forKey: .subscriptionURL)
        syncWindowPastDays = max(0, try container.decodeIfPresent(Int.self, forKey: .syncWindowPastDays) ?? 30)
        syncWindowFutureDays = max(1, try container.decodeIfPresent(Int.self, forKey: .syncWindowFutureDays) ?? 365)
        enabledCollectionIDs = try container.decodeIfPresent([CalendarID].self, forKey: .enabledCollectionIDs) ?? []
        providerMetadata = try container.decodeIfPresent([String: String].self, forKey: .providerMetadata) ?? [:]
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

public struct CalendarCollectionCapabilities: Codable, Sendable, Equatable, Hashable {
    public var canCreateEvents: Bool
    public var canUpdateEvents: Bool
    public var canDeleteEvents: Bool
    public var supportsScheduling: Bool
    public var readOnlyReason: String?

    public init(canCreateEvents: Bool = false, canUpdateEvents: Bool = false, canDeleteEvents: Bool = false, supportsScheduling: Bool = false, readOnlyReason: String? = nil) {
        self.canCreateEvents = canCreateEvents
        self.canUpdateEvents = canUpdateEvents
        self.canDeleteEvents = canDeleteEvents
        self.supportsScheduling = supportsScheduling
        self.readOnlyReason = readOnlyReason
    }

    public static let readOnly = CalendarCollectionCapabilities(readOnlyReason: "Calendar collection is read-only")
    public static let eventCRUD = CalendarCollectionCapabilities(canCreateEvents: true, canUpdateEvents: true, canDeleteEvents: true)
}

public struct CalendarCollection: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: CalendarID
    public var accountID: CalendarAccountID
    public var displayName: String
    public var colorHex: String?
    public var isReadOnly: Bool
    public var source: String
    public var capabilities: CalendarCollectionCapabilities

    public init(id: CalendarID, accountID: CalendarAccountID, displayName: String, colorHex: String? = nil, isReadOnly: Bool = false, source: String = "connor-cache", capabilities: CalendarCollectionCapabilities? = nil) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self.colorHex = colorHex
        self.isReadOnly = isReadOnly
        self.source = source
        self.capabilities = capabilities ?? (isReadOnly ? .readOnly : .eventCRUD)
    }

    private enum CodingKeys: String, CodingKey { case id, accountID, displayName, colorHex, isReadOnly, source, capabilities }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CalendarID.self, forKey: .id)
        accountID = try container.decode(CalendarAccountID.self, forKey: .accountID)
        displayName = try container.decode(String.self, forKey: .displayName)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "connor-cache"
        capabilities = try container.decodeIfPresent(CalendarCollectionCapabilities.self, forKey: .capabilities) ?? (isReadOnly ? .readOnly : .eventCRUD)
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

public struct CalendarEventSourceMetadata: Codable, Sendable, Equatable, Hashable {
    public var sourceKind: CalendarSourceKind
    public var remoteIdentifier: String?
    public var resourceURL: URL?
    public var etag: String?
    public var scheduleTag: String?
    public var recurrenceIdentifier: String?
    public var isRecurring: Bool
    public var organizerEmail: String?
    public var hasAttendees: Bool

    public init(sourceKind: CalendarSourceKind, remoteIdentifier: String? = nil, resourceURL: URL? = nil, etag: String? = nil, scheduleTag: String? = nil, recurrenceIdentifier: String? = nil, isRecurring: Bool = false, organizerEmail: String? = nil, hasAttendees: Bool = false) {
        self.sourceKind = sourceKind
        self.remoteIdentifier = remoteIdentifier
        self.resourceURL = resourceURL
        self.etag = etag
        self.scheduleTag = scheduleTag
        self.recurrenceIdentifier = recurrenceIdentifier
        self.isRecurring = isRecurring
        self.organizerEmail = organizerEmail
        self.hasAttendees = hasAttendees
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
    public var sourceMetadata: CalendarEventSourceMetadata?
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
        sourceMetadata: CalendarEventSourceMetadata? = nil,
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
        self.sourceMetadata = sourceMetadata
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

public enum CalendarPatchValue<Value: Codable & Sendable & Equatable & Hashable>: Codable, Sendable, Equatable, Hashable {
    case unchanged
    case clear
    case set(Value)
}

public enum CalendarMutationOperation: String, Codable, Sendable, Equatable, Hashable {
    case create
    case update
    case delete
}

public enum CalendarRecurrenceFrequency: String, Codable, Sendable, Equatable, Hashable {
    case daily
    case weekly
    case monthly
    case yearly
}

public struct CalendarRecurrence: Codable, Sendable, Equatable, Hashable {
    public var frequency: CalendarRecurrenceFrequency
    public var interval: Int
    public var until: Date?
    public var count: Int?

    public init(frequency: CalendarRecurrenceFrequency, interval: Int = 1, until: Date? = nil, count: Int? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.until = until
        self.count = count.map { max(1, $0) }
    }

    /// RFC 5545 RRULE 文本，例如 "FREQ=WEEKLY;INTERVAL=2;UNTIL=20261231T235959Z"。
    public var rruleString: String? {
        guard interval >= 1, until == nil || count == nil, count == nil || count! >= 1 else { return nil }
        var parts = ["FREQ=\(frequency.rawValue.uppercased())"]
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if let until {
            parts.append("UNTIL=\(Self.utcFormatted(until))")
        } else if let count {
            parts.append("COUNT=\(count)")
        }
        return parts.joined(separator: ";")
    }

    /// 从 RRULE 文本解析；不支持 BY* 等高级规则时返回 nil。
    public init?(rrule: String) {
        var frequency: CalendarRecurrenceFrequency?
        var interval = 1
        var until: Date?
        var count: Int?
        for part in rrule.components(separatedBy: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0].uppercased() {
            case "FREQ":
                switch pair[1].uppercased() {
                case "DAILY": frequency = .daily
                case "WEEKLY": frequency = .weekly
                case "MONTHLY": frequency = .monthly
                case "YEARLY": frequency = .yearly
                default: break
                }
            case "INTERVAL":
                interval = Int(pair[1]) ?? 1
            case "UNTIL":
                until = Self.dateFromUTC(pair[1].uppercased())
            case "COUNT":
                count = Int(pair[1])
            default:
                break
            }
        }
        guard let frequency else { return nil }
        guard until == nil || count == nil, count == nil || count! >= 1 else { return nil }
        self.init(frequency: frequency, interval: max(1, interval), until: until, count: count)
    }

    private static func utcFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dateFromUTC(_ value: String) -> Date? {
        let trimmed = value.replacingOccurrences(of: "'", with: "")
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.date(from: trimmed)
    }
}

public enum CalendarMutationScope: String, Codable, Sendable, Equatable, Hashable {
    /// 只修改/删除单个实例（周期事件的某一次）。
    case thisEvent
    /// 修改/删除当前实例及之后的所有实例。
    case futureEvents
    /// 修改/删除整个周期系列（默认）。
    case entireSeries
}

public struct CalendarEventDraft: Codable, Sendable, Equatable, Hashable {
    public var calendarID: CalendarID
    public var title: String
    public var start: CalendarEventDateTime
    public var end: CalendarEventDateTime
    public var isAllDay: Bool
    public var location: String?
    public var url: URL?
    public var notes: String?
    public var recurrence: CalendarRecurrence?

    public init(calendarID: CalendarID, title: String, start: CalendarEventDateTime, end: CalendarEventDateTime, isAllDay: Bool = false, location: String? = nil, url: URL? = nil, notes: String? = nil, recurrence: CalendarRecurrence? = nil) {
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.url = url
        self.notes = notes
        self.recurrence = recurrence
    }
}

public struct CalendarEventPatch: Codable, Sendable, Equatable, Hashable {
    public var title: CalendarPatchValue<String>
    public var start: CalendarPatchValue<CalendarEventDateTime>
    public var end: CalendarPatchValue<CalendarEventDateTime>
    public var isAllDay: CalendarPatchValue<Bool>
    public var location: CalendarPatchValue<String>
    public var url: CalendarPatchValue<URL>
    public var notes: CalendarPatchValue<String>
    public var recurrence: CalendarPatchValue<CalendarRecurrence>

    public init(title: CalendarPatchValue<String> = .unchanged, start: CalendarPatchValue<CalendarEventDateTime> = .unchanged, end: CalendarPatchValue<CalendarEventDateTime> = .unchanged, isAllDay: CalendarPatchValue<Bool> = .unchanged, location: CalendarPatchValue<String> = .unchanged, url: CalendarPatchValue<URL> = .unchanged, notes: CalendarPatchValue<String> = .unchanged, recurrence: CalendarPatchValue<CalendarRecurrence> = .unchanged) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.url = url
        self.notes = notes
        self.recurrence = recurrence
    }

    public var isEmpty: Bool {
        title == .unchanged && start == .unchanged && end == .unchanged && isAllDay == .unchanged && location == .unchanged && url == .unchanged && notes == .unchanged && recurrence == .unchanged
    }
}

public struct CalendarMutationVersion: Codable, Sendable, Equatable, Hashable {
    public var value: String
    public init(value: String) { self.value = value }
}

public enum CalendarMutationError: Error, Codable, Sendable, Equatable, Hashable {
    case invalidInput(String)
    case readOnlySource
    case readOnlyCollection(String?)
    case calendarNotFound(CalendarID)
    case accountNotFound(CalendarAccountID)
    case eventNotFound
    case recurrenceUnsupported
    case schedulingUnsupported
    case conflict(expected: String?, actual: String?)
    case authenticationRequired
    case permissionDenied
    case remoteFailure(String)
    case verificationFailed
}

public struct CalendarMutationRequest: Codable, Sendable, Equatable, Hashable {
    public var operation: CalendarMutationOperation
    public var eventID: CalendarEventID?
    public var expectedVersion: CalendarMutationVersion?
    public var draft: CalendarEventDraft?
    public var patch: CalendarEventPatch?
    public var scope: CalendarMutationScope
    public var occurrenceDate: Date?
    public var approvalID: String?
    public var runID: String?
    public var sessionID: String?

    public init(operation: CalendarMutationOperation, eventID: CalendarEventID? = nil, expectedVersion: CalendarMutationVersion? = nil, draft: CalendarEventDraft? = nil, patch: CalendarEventPatch? = nil, scope: CalendarMutationScope = .entireSeries, occurrenceDate: Date? = nil, approvalID: String? = nil, runID: String? = nil, sessionID: String? = nil) {
        self.operation = operation
        self.eventID = eventID
        self.expectedVersion = expectedVersion
        self.draft = draft
        self.patch = patch
        self.scope = scope
        self.occurrenceDate = occurrenceDate
        self.approvalID = approvalID
        self.runID = runID
        self.sessionID = sessionID
    }

    public func validated() throws -> CalendarMutationRequest {
        switch operation {
        case .create:
            guard let draft else { throw CalendarMutationError.invalidInput("draft is required") }
            guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CalendarMutationError.invalidInput("title is required") }
            guard draft.end.date > draft.start.date else { throw CalendarMutationError.invalidInput("end must be after start") }
            if let recurrence = draft.recurrence { try Self.validate(recurrence) }
        case .update:
            guard eventID != nil, expectedVersion != nil, let patch, !patch.isEmpty else { throw CalendarMutationError.invalidInput("eventID, expectedVersion, and a non-empty patch are required") }
            if case .set(let recurrence) = patch.recurrence { try Self.validate(recurrence) }
        case .delete:
            guard eventID != nil, expectedVersion != nil else { throw CalendarMutationError.invalidInput("eventID and expectedVersion are required") }
        }
        return self
    }

    private static func validate(_ recurrence: CalendarRecurrence) throws {
        guard recurrence.interval >= 1 else { throw CalendarMutationError.invalidInput("recurrence interval must be at least 1") }
        guard recurrence.count == nil || recurrence.count! >= 1 else { throw CalendarMutationError.invalidInput("recurrence count must be at least 1") }
        guard recurrence.until == nil || recurrence.count == nil else { throw CalendarMutationError.invalidInput("recurrence until and count are mutually exclusive") }
    }
}

public enum CalendarMutationSyncStatus: String, Codable, Sendable, Equatable, Hashable {
    case confirmed
    case remoteSucceededLocalVerificationPending
    case remoteAlreadyMissing
}

public struct CalendarMutationConflict: Codable, Sendable, Equatable, Hashable {
    public var expectedVersion: CalendarMutationVersion?
    public var actualVersion: CalendarMutationVersion?
    public var currentEvent: CalendarEvent?
    public var retryGuidance: String

    public init(expectedVersion: CalendarMutationVersion?, actualVersion: CalendarMutationVersion?, currentEvent: CalendarEvent? = nil, retryGuidance: String) {
        self.expectedVersion = expectedVersion
        self.actualVersion = actualVersion
        self.currentEvent = currentEvent
        self.retryGuidance = retryGuidance
    }
}

public struct CalendarMutationResult: Codable, Sendable, Equatable, Hashable {
    public var receipt: CalendarWriteReceipt
    public var confirmedEvent: CalendarEvent?
    public var remoteVersion: CalendarMutationVersion?
    public var syncStatus: CalendarMutationSyncStatus

    public init(receipt: CalendarWriteReceipt, confirmedEvent: CalendarEvent? = nil, remoteVersion: CalendarMutationVersion? = nil, syncStatus: CalendarMutationSyncStatus = .confirmed) {
        self.receipt = receipt
        self.confirmedEvent = confirmedEvent
        self.remoteVersion = remoteVersion
        self.syncStatus = syncStatus
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
