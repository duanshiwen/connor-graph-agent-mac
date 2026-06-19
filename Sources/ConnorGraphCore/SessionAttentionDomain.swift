import Foundation

public enum SessionAttentionLevel: Int, Codable, Sendable, Comparable {
    case none = 0
    case unread = 1
    case emphasized = 2
    case actionable = 3
    case interruptive = 4

    public static func < (lhs: SessionAttentionLevel, rhs: SessionAttentionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var isUnread: Bool { self > .none }
    public var shouldCountInDockBadge: Bool { self >= .actionable }
    public var shouldRequestSystemNotification: Bool { self >= .actionable }
}

public struct SessionReadState: Codable, Equatable, Sendable {
    public var lastReadMessageID: String?
    public var lastReadAt: Date?
    public var unreadCount: Int
    public var highestLevel: SessionAttentionLevel
    public var lastUnreadMessageID: String?
    public var lastUnreadPreview: String?
    public var updatedAt: Date

    public init(
        lastReadMessageID: String? = nil,
        lastReadAt: Date? = nil,
        unreadCount: Int = 0,
        highestLevel: SessionAttentionLevel = .none,
        lastUnreadMessageID: String? = nil,
        lastUnreadPreview: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.lastReadMessageID = lastReadMessageID
        self.lastReadAt = lastReadAt
        self.unreadCount = unreadCount
        self.highestLevel = highestLevel
        self.lastUnreadMessageID = lastUnreadMessageID
        self.lastUnreadPreview = lastUnreadPreview
        self.updatedAt = updatedAt
    }

    public static func initial(updatedAt: Date = Date()) -> SessionReadState {
        SessionReadState(updatedAt: updatedAt)
    }

    public mutating func markUnread(
        messageID: String,
        preview: String?,
        level: SessionAttentionLevel = .unread,
        at date: Date = Date()
    ) {
        guard level > .none else { return }
        if lastUnreadMessageID != messageID {
            unreadCount += 1
        }
        highestLevel = max(highestLevel, level)
        lastUnreadMessageID = messageID
        lastUnreadPreview = preview
        updatedAt = date
    }

    public mutating func markRead(
        messageID: String?,
        at date: Date = Date()
    ) {
        lastReadMessageID = messageID ?? lastUnreadMessageID ?? lastReadMessageID
        lastReadAt = date
        unreadCount = 0
        highestLevel = .none
        lastUnreadMessageID = nil
        lastUnreadPreview = nil
        updatedAt = date
    }
}
