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
        CalendarProviderProfile(sourceKind: .macOSEventKit, displayName: "macOS Calendar", authMode: .none, status: .supported, isUserConfigurable: true, helpText: "只读访问 macOS 日历中已授权的日历。点击「同步本机日历」后，系统会请求日历权限。"),
        CalendarProviderProfile(sourceKind: .icsSubscription, displayName: "ICS/Webcal Subscription", authMode: .none, status: .supported, isUserConfigurable: true, helpText: "只读订阅日历，支持 http、https 和 webcal 协议的订阅链接。"),
        CalendarProviderProfile(sourceKind: .genericCalDAV, displayName: "Generic CalDAV", authMode: .appPassword, status: .supported, isUserConfigurable: true, helpText: "通过服务器 URL、用户名和应用密码连接标准 CalDAV 服务，只读同步。"),
        CalendarProviderProfile(sourceKind: .appleICloudCalDAV, displayName: "Apple iCloud Calendar", authMode: .appPassword, status: .supported, isUserConfigurable: true, helpText: "使用 Apple App-specific password（应用专用密码）连接 iCloud CalDAV，只读同步。需要在 appleid.apple.com 生成应用专用密码。", defaultServerURL: URL(string: "https://caldav.icloud.com")),
        CalendarProviderProfile(sourceKind: .fastmailCalDAV, displayName: "Fastmail Calendar", authMode: .appPassword, status: .supported, isUserConfigurable: true, helpText: "使用 Fastmail 应用密码通过 CalDAV 只读同步日历。", defaultServerURL: URL(string: "https://caldav.fastmail.com")),
        CalendarProviderProfile(sourceKind: .nextcloudCalDAV, displayName: "Nextcloud Calendar", authMode: .appPassword, status: .supported, isUserConfigurable: true, helpText: "使用 Nextcloud CalDAV 端点和应用密码进行只读同步。"),
        CalendarProviderProfile(sourceKind: .googleCalendar, displayName: "Google Calendar", authMode: .oauth2, status: .planned, isUserConfigurable: false, helpText: "Google 日历 OAuth 只读连接器已建模，待 OAuth 运行时实现后启用。"),
        CalendarProviderProfile(sourceKind: .microsoft365Calendar, displayName: "Microsoft 365 Calendar", authMode: .oauth2, status: .planned, isUserConfigurable: false, helpText: "Microsoft 365 日历 OAuth 只读连接器已建模，待 OAuth 运行时实现后启用。")
    ]
}
