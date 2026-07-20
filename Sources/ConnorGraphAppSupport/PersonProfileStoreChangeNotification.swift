import Foundation

public enum PersonProfileStoreChangeReason: String, Sendable, Equatable {
    case upserted
    case deleted
    case merged
}

public enum PersonProfileStoreChangeNotificationUserInfoKey {
    public static let personIDs = "personIDs"
    public static let reason = "reason"
}

public extension Notification.Name {
    static let connorPersonProfileStoreDidChange = Notification.Name("Connor.PersonProfileStore.didChange")
}
