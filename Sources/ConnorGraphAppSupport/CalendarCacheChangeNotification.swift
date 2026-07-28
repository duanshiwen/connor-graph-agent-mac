import Foundation

public enum CalendarCacheChangeReason: String, Sendable, Equatable {
    case eventMutationCommitted
}

public enum CalendarCacheChangeNotificationUserInfoKey {
    public static let accountID = "accountID"
    public static let calendarID = "calendarID"
    public static let eventID = "eventID"
    public static let operation = "operation"
    public static let reason = "reason"
}

public extension Notification.Name {
    static let connorCalendarCacheDidChange = Notification.Name("Connor.CalendarCache.didChange")
}
