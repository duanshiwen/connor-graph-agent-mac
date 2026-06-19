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

public enum CalendarAccountHealthStatus: String, Codable, Sendable, Equatable, Hashable {
    case ready
    case degraded
    case blocked
    case unauthenticated
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
    public var displayName: String
    public var credentialBinding: ConnectedAccountCredentialBinding?
    public var health: CalendarAccountHealth
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: CalendarAccountID,
        connectedAccountID: ConnectedAccountID? = nil,
        provider: ConnectedAccountProviderKind,
        displayName: String,
        credentialBinding: ConnectedAccountCredentialBinding? = nil,
        health: CalendarAccountHealth = CalendarAccountHealth(status: .unknown, summary: "Not checked"),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.connectedAccountID = connectedAccountID
        self.provider = provider
        self.displayName = displayName
        self.credentialBinding = credentialBinding
        self.health = health
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
