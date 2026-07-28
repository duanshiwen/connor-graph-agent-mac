import Foundation

public enum MailCacheChangeReason: String, Sendable, Equatable {
    case sentMessageSaved
    case readStateUpdated
}

public enum MailCacheChangeNotificationUserInfoKey {
    public static let accountID = "accountID"
    public static let messageID = "messageID"
    public static let messageIDs = "messageIDs"
    public static let reason = "reason"
}

public extension Notification.Name {
    static let connorMailCacheDidChange = Notification.Name("Connor.MailCache.didChange")
}
