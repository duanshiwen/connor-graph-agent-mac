import Foundation

public enum SessionAttentionLevel: Int, Codable, Sendable, Comparable, CaseIterable, Identifiable {
    case none = 0
    case unread = 1
    case emphasized = 2
    case actionable = 3
    case interruptive = 4

    public static func < (lhs: SessionAttentionLevel, rhs: SessionAttentionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var id: Int { rawValue }
    public var isUnread: Bool { self > .none }
    public var shouldCountInDockBadge: Bool { self >= .actionable }
    public var shouldRequestSystemNotification: Bool { self >= .actionable }

    public var displayName: String {
        switch self {
        case .none: "不提醒"
        case .unread: "仅未读"
        case .emphasized: "列表突出"
        case .actionable: "系统通知"
        case .interruptive: "强提醒"
        }
    }

    public var detail: String {
        switch self {
        case .none: "不产生未读状态,不显示提醒。"
        case .unread: "只记录未读,不改变卡片强调样式。"
        case .emphasized: "显示未读,并突出聊天列表卡片。"
        case .actionable: "发送 macOS 通知,突出聊天列表,并计入 Dock badge。"
        case .interruptive: "用于失败、阻塞、需要立即处理的高优先级提醒。"
        }
    }
}

public struct SessionNotificationSettings: Codable, Equatable, Sendable {
    public var newMessageLevel: SessionAttentionLevel

    public init(newMessageLevel: SessionAttentionLevel = .actionable) {
        self.newMessageLevel = newMessageLevel
    }

    public static let `default` = SessionNotificationSettings()
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
