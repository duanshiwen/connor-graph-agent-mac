import Foundation
import ConnorGraphCore

public enum CalendarProviderProfileStatus: String, Codable, Sendable, Equatable, Hashable {
    case supported
    case planned
}

public struct CalendarProviderProfile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: CalendarSourceKind { sourceKind }
    public var sourceKind: CalendarSourceKind
    public var displayName: String
    public var authMode: CalendarSourceAuthMode
    public var status: CalendarProviderProfileStatus
    public var isUserConfigurable: Bool
    public var helpText: String
    public var defaultServerURL: URL?

    public init(sourceKind: CalendarSourceKind, displayName: String, authMode: CalendarSourceAuthMode, status: CalendarProviderProfileStatus, isUserConfigurable: Bool, helpText: String, defaultServerURL: URL? = nil) {
        self.sourceKind = sourceKind
        self.displayName = displayName
        self.authMode = authMode
        self.status = status
        self.isUserConfigurable = isUserConfigurable
        self.helpText = helpText
        self.defaultServerURL = defaultServerURL
    }

    public static let catalog: [CalendarProviderProfile] = [
        CalendarProviderProfile(sourceKind: .macOSEventKit, displayName: "macOS Calendar", authMode: .none, status: .supported, isUserConfigurable: true, helpText: "Read-only access to calendars already authorized in macOS Calendar."),
        CalendarProviderProfile(sourceKind: .icsSubscription, displayName: "ICS/Webcal Subscription", authMode: .none, status: .supported, isUserConfigurable: true, helpText: "Read-only subscription URL using http, https, or webcal."),
        CalendarProviderProfile(sourceKind: .genericCalDAV, displayName: "Generic CalDAV", authMode: .appPassword, status: .supported, isUserConfigurable: true, helpText: "Read-only CalDAV using a server URL, username, and app password."),
        CalendarProviderProfile(sourceKind: .appleICloudCalDAV, displayName: "Apple iCloud Calendar", authMode: .appPassword, status: .supported, isUserConfigurable: true, helpText: "Use an Apple App-specific password for read-only iCloud CalDAV sync.", defaultServerURL: URL(string: "https://caldav.icloud.com")),
        CalendarProviderProfile(sourceKind: .fastmailCalDAV, displayName: "Fastmail Calendar", authMode: .appPassword, status: .supported, isUserConfigurable: true, helpText: "Use Fastmail app password with CalDAV read-only sync.", defaultServerURL: URL(string: "https://caldav.fastmail.com")),
        CalendarProviderProfile(sourceKind: .nextcloudCalDAV, displayName: "Nextcloud Calendar", authMode: .appPassword, status: .supported, isUserConfigurable: true, helpText: "Use your Nextcloud CalDAV endpoint and app password for read-only sync."),
        CalendarProviderProfile(sourceKind: .googleCalendar, displayName: "Google Calendar", authMode: .oauth2, status: .planned, isUserConfigurable: false, helpText: "Google Calendar API OAuth read-only connector is modeled but not enabled until OAuth runtime is implemented."),
        CalendarProviderProfile(sourceKind: .microsoft365Calendar, displayName: "Microsoft 365 Calendar", authMode: .oauth2, status: .planned, isUserConfigurable: false, helpText: "Microsoft Graph Calendar OAuth read-only connector is modeled but not enabled until OAuth runtime is implemented.")
    ]
}
