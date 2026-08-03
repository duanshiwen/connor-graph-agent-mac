import Foundation

/// Domain models for the peer-to-peer IM feature (real-human chat), mirroring the
/// Android client's Room schema so both platforms share one behavioral contract.
/// Conversation IDs are stable composite keys: `"peer:{peerUserId}"` / `"group:{groupId}"`.

public enum ImConversationKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case peer
    case group
}

public enum ImMessageType: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case text
    case image
    case video
    case audio
    case system

    public var isMedia: Bool {
        self == .image || self == .video || self == .audio
    }

    public var conversationPreview: String {
        switch self {
        case .text: return ""
        case .image: return "[图片]"
        case .video: return "[视频]"
        case .audio: return "[语音]"
        case .system: return "[系统消息]"
        }
    }
}

public struct ImMediaMetadata: Codable, Sendable, Equatable, Hashable {
    public var width: Int?
    public var height: Int?
    public var duration: Int?
    public var fileSize: Int64?
    public var fileName: String?
    public var mimeType: String?
    public var thumbnail: String?
    public var expired: Bool
    public var localPath: String?
    public var localThumbnailPath: String?

    public init(
        width: Int? = nil,
        height: Int? = nil,
        duration: Int? = nil,
        fileSize: Int64? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        thumbnail: String? = nil,
        expired: Bool = false,
        localPath: String? = nil,
        localThumbnailPath: String? = nil
    ) {
        self.width = width
        self.height = height
        self.duration = duration
        self.fileSize = fileSize
        self.fileName = fileName
        self.mimeType = mimeType
        self.thumbnail = thumbnail
        self.expired = expired
        self.localPath = localPath
        self.localThumbnailPath = localThumbnailPath
    }

    private enum CodingKeys: String, CodingKey {
        case width, height, duration, fileSize, size, fileName, mimeType, format
        case thumbnail, expired, localPath, localThumbnailPath
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
        duration = try values.decodeIfPresent(Int.self, forKey: .duration)
        fileSize = try values.decodeIfPresent(Int64.self, forKey: .fileSize)
            ?? values.decodeIfPresent(Int64.self, forKey: .size)
        fileName = try values.decodeIfPresent(String.self, forKey: .fileName)
        mimeType = try values.decodeIfPresent(String.self, forKey: .mimeType)
            ?? values.decodeIfPresent(String.self, forKey: .format)
        thumbnail = try values.decodeIfPresent(String.self, forKey: .thumbnail)
        expired = try values.decodeIfPresent(Bool.self, forKey: .expired) ?? false
        localPath = try values.decodeIfPresent(String.self, forKey: .localPath)
        localThumbnailPath = try values.decodeIfPresent(String.self, forKey: .localThumbnailPath)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(width, forKey: .width)
        try values.encodeIfPresent(height, forKey: .height)
        try values.encodeIfPresent(duration, forKey: .duration)
        try values.encodeIfPresent(fileSize, forKey: .fileSize)
        try values.encodeIfPresent(fileName, forKey: .fileName)
        try values.encodeIfPresent(mimeType, forKey: .mimeType)
        try values.encodeIfPresent(thumbnail, forKey: .thumbnail)
        if expired { try values.encode(true, forKey: .expired) }
        try values.encodeIfPresent(localPath, forKey: .localPath)
        try values.encodeIfPresent(localThumbnailPath, forKey: .localThumbnailPath)
    }
}

/// Message delivery state machine: SENDING → SENT → DELIVERED → READ, one-way only.
/// FAILED is terminal but retryable (retry resets the same message back to SENDING).
public enum ImMessageStatus: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case sending = "SENDING"
    case sent = "SENT"
    case delivered = "DELIVERED"
    case read = "READ"
    case failed = "FAILED"

    /// Forward-only rank; `nil` for FAILED which sits outside the progression.
    public var progressRank: Int? {
        switch self {
        case .sending: return 0
        case .sent: return 1
        case .delivered: return 2
        case .read: return 3
        case .failed: return nil
        }
    }

    /// Whether transitioning to `next` is allowed (never regress a delivered state).
    public func canAdvance(to next: ImMessageStatus) -> Bool {
        if next == .failed { return self == .sending }
        guard let currentRank = progressRank, let nextRank = next.progressRank else {
            // FAILED → SENDING is the retry path.
            return self == .failed && next == .sending
        }
        return nextRank > currentRank
    }
}

public struct ImConversation: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var kind: ImConversationKind
    public var peerUserId: Int64?
    public var groupId: String?
    public var title: String
    /// Server-backed peer/group name shown beneath the locally managed title.
    public var participantName: String
    public var avatar: String
    public var lastMessagePreview: String
    /// Unix milliseconds of the newest message; 0 when empty.
    public var lastMessageAt: Int64
    public var unreadCount: Int
    /// Local-only preferences, preserved across server-side conversation merges.
    public var pinned: Bool
    public var muted: Bool
    public var status: AgentSessionStatus
    public var labelIds: [String]
    /// Prevents server refreshes from replacing a manual or AI-generated title.
    public var titleCustomized: Bool
    public var updatedAt: Int64

    public init(
        id: String,
        kind: ImConversationKind,
        peerUserId: Int64? = nil,
        groupId: String? = nil,
        title: String,
        participantName: String = "",
        avatar: String = "",
        lastMessagePreview: String = "",
        lastMessageAt: Int64 = 0,
        unreadCount: Int = 0,
        pinned: Bool = false,
        muted: Bool = false,
        status: AgentSessionStatus = .todo,
        labelIds: [String] = [],
        titleCustomized: Bool = false,
        updatedAt: Int64 = 0
    ) {
        self.id = id
        self.kind = kind
        self.peerUserId = peerUserId
        self.groupId = groupId
        self.title = title
        self.participantName = participantName.isEmpty ? title : participantName
        self.avatar = avatar
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
        self.pinned = pinned
        self.muted = muted
        self.status = status
        self.labelIds = labelIds
        self.titleCustomized = titleCustomized
        self.updatedAt = updatedAt
    }

    public static func peerConversationID(peerUserId: Int64) -> String { "peer:\(peerUserId)" }
    public static func groupConversationID(groupId: String) -> String { "group:\(groupId)" }
}

public struct ImMessage: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// Store-assigned monotonic sequence deciding in-conversation order; 0 = unassigned.
    public var seq: Int64
    /// Server message UUID, or an optimistic `temp_` + UUID replaced in place after ack.
    public var id: String
    public var conversationId: String
    public var senderId: Int64
    public var senderName: String
    public var senderAvatar: String
    public var messageType: String
    public var content: String
    public var status: ImMessageStatus
    /// Unix milliseconds.
    public var createdAt: Int64
    public var extraJson: String

    public init(
        seq: Int64 = 0,
        id: String,
        conversationId: String,
        senderId: Int64,
        senderName: String = "",
        senderAvatar: String = "",
        messageType: String = "text",
        content: String,
        status: ImMessageStatus,
        createdAt: Int64,
        extraJson: String = ""
    ) {
        self.seq = seq
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderName = senderName
        self.senderAvatar = senderAvatar
        self.messageType = messageType
        self.content = content
        self.status = status
        self.createdAt = createdAt
        self.extraJson = extraJson
    }

    public static let temporaryIDPrefix = "temp_"

    public static func makeTemporaryID() -> String { temporaryIDPrefix + UUID().uuidString }

    public var hasTemporaryID: Bool { id.hasPrefix(Self.temporaryIDPrefix) }

    public var type: ImMessageType? { ImMessageType(rawValue: messageType.lowercased()) }

    public var mediaMetadata: ImMediaMetadata? {
        guard type?.isMedia == true, let data = extraJson.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ImMediaMetadata.self, from: data)
    }
}

/// Cached friend row (projection of the server-side friendship).
/// `personProfileID` bridges the friend to a local person profile / L4 entity.
public struct ImFriend: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var userId: Int64
    public var username: String
    public var nickname: String
    public var email: String
    public var avatar: String
    public var personProfileID: String?
    public var updatedAt: Int64

    public var id: Int64 { userId }

    /// Display fallback chain: nickname → username → "用户 {id}".
    public var displayName: String {
        if !nickname.isEmpty { return nickname }
        if !username.isEmpty { return username }
        return "用户 \(userId)"
    }

    public init(
        userId: Int64,
        username: String,
        nickname: String = "",
        email: String = "",
        avatar: String = "",
        personProfileID: String? = nil,
        updatedAt: Int64 = 0
    ) {
        self.userId = userId
        self.username = username
        self.nickname = nickname
        self.email = email
        self.avatar = avatar
        self.personProfileID = personProfileID
        self.updatedAt = updatedAt
    }
}

/// Friend request cache; incoming and outgoing share the table, the direction is
/// derived by comparing `senderId`/`receiverId` with the signed-in user's id.
public struct ImFriendRequest: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Int64
    public var senderId: Int64
    public var receiverId: Int64
    public var message: String
    public var status: String
    public var senderUsername: String
    public var senderNickname: String
    public var senderAvatar: String
    public var receiverUsername: String
    public var receiverNickname: String
    public var createdAt: Int64

    public init(
        id: Int64,
        senderId: Int64,
        receiverId: Int64,
        message: String = "",
        status: String = "pending",
        senderUsername: String = "",
        senderNickname: String = "",
        senderAvatar: String = "",
        receiverUsername: String = "",
        receiverNickname: String = "",
        createdAt: Int64 = 0
    ) {
        self.id = id
        self.senderId = senderId
        self.receiverId = receiverId
        self.message = message
        self.status = status
        self.senderUsername = senderUsername
        self.senderNickname = senderNickname
        self.senderAvatar = senderAvatar
        self.receiverUsername = receiverUsername
        self.receiverNickname = receiverNickname
        self.createdAt = createdAt
    }
}

/// Persistent mapping from an IM participant to an opaque forwarding alias token
/// (`@CX` + 6 uppercase hex). The same sender reuses one token across forwards so the
/// AI accumulates knowledge consistently. `displayName` is local-only and never sent to AI.
public struct ImForwardAlias: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var aliasToken: String
    public var senderId: Int64
    public var imConversationId: String
    public var personProfileID: String
    public var displayName: String
    public var createdAt: Int64

    public var id: String { aliasToken }

    public init(
        aliasToken: String,
        senderId: Int64,
        imConversationId: String,
        personProfileID: String,
        displayName: String,
        createdAt: Int64
    ) {
        self.aliasToken = aliasToken
        self.senderId = senderId
        self.imConversationId = imConversationId
        self.personProfileID = personProfileID
        self.displayName = displayName
        self.createdAt = createdAt
    }
}
