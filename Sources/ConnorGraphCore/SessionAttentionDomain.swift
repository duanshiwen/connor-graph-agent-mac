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

public enum SessionAttentionMessageType: String, Codable, Sendable, CaseIterable, Identifiable {
    case assistantReply
    case taskCompleted
    case taskFailed
    case userActionRequired
    case permissionApprovalRequired
    case backgroundTaskCompleted
    case backgroundTaskFailed
    case proactiveBriefing
    case systemNotice
    case governanceChange

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .assistantReply: "普通助理回复"
        case .taskCompleted: "会话任务完成"
        case .taskFailed: "会话任务失败"
        case .userActionRequired: "需要用户操作"
        case .permissionApprovalRequired: "权限审批请求"
        case .backgroundTaskCompleted: "后台任务完成"
        case .backgroundTaskFailed: "后台任务失败"
        case .proactiveBriefing: "主动简报"
        case .systemNotice: "系统提醒"
        case .governanceChange: "状态/治理变化"
        }
    }

    public var detail: String {
        switch self {
        case .assistantReply: "普通 assistant 消息或非阻塞回复。"
        case .taskCompleted: "用户发起的会话运行完成。"
        case .taskFailed: "用户发起的会话运行失败或异常退出。"
        case .userActionRequired: "需要用户输入、确认、补充资料或下一步决策。"
        case .permissionApprovalRequired: "工具调用、文件写入、网络访问等需要审批。"
        case .backgroundTaskCompleted: "标题生成、摘要、索引、同步等后台任务完成。"
        case .backgroundTaskFailed: "后台任务失败,但不一定阻塞当前会话。"
        case .proactiveBriefing: "Connor 主动创建或更新的信息综合简报会话。"
        case .systemNotice: "系统级状态、权限、连接、同步或环境提醒。"
        case .governanceChange: "会话状态、标签、归档、工作流状态等变化。"
        }
    }

    public var defaultAttentionLevel: SessionAttentionLevel {
        switch self {
        case .assistantReply: .unread
        case .taskCompleted: .actionable
        case .taskFailed: .interruptive
        case .userActionRequired: .actionable
        case .permissionApprovalRequired: .interruptive
        case .backgroundTaskCompleted: .emphasized
        case .backgroundTaskFailed: .actionable
        case .proactiveBriefing: .emphasized
        case .systemNotice: .emphasized
        case .governanceChange: .unread
        }
    }
}

public struct SessionNotificationPolicy: Codable, Equatable, Sendable {
    public var minimumLevel: SessionAttentionLevel
    public var levelsByMessageType: [SessionAttentionMessageType: SessionAttentionLevel]

    public init(
        minimumLevel: SessionAttentionLevel = .unread,
        levelsByMessageType: [SessionAttentionMessageType: SessionAttentionLevel] = [:]
    ) {
        self.minimumLevel = minimumLevel
        self.levelsByMessageType = levelsByMessageType
    }

    public static let `default` = SessionNotificationPolicy()

    public func configuredLevel(for messageType: SessionAttentionMessageType) -> SessionAttentionLevel {
        levelsByMessageType[messageType] ?? messageType.defaultAttentionLevel
    }

    public func effectiveLevel(for messageType: SessionAttentionMessageType) -> SessionAttentionLevel {
        max(configuredLevel(for: messageType), minimumLevel)
    }
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
