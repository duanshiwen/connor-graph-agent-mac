import Foundation

/// Domain models for the peer-to-peer IM feature (real-human chat), mirroring the
/// Android client's Room schema so both platforms share one behavioral contract.
/// Conversation IDs are stable composite keys: `"peer:{peerUserId}"` / `"group:{groupId}"`.

public enum ImConversationKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case peer
    case group
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
    public var avatar: String
    public var lastMessagePreview: String
    /// Unix milliseconds of the newest message; 0 when empty.
    public var lastMessageAt: Int64
    public var unreadCount: Int
    /// Local-only preferences, preserved across server-side conversation merges.
    public var pinned: Bool
    public var muted: Bool
    public var updatedAt: Int64

    public init(
        id: String,
        kind: ImConversationKind,
        peerUserId: Int64? = nil,
        groupId: String? = nil,
        title: String,
        avatar: String = "",
        lastMessagePreview: String = "",
        lastMessageAt: Int64 = 0,
        unreadCount: Int = 0,
        pinned: Bool = false,
        muted: Bool = false,
        updatedAt: Int64 = 0
    ) {
        self.id = id
        self.kind = kind
        self.peerUserId = peerUserId
        self.groupId = groupId
        self.title = title
        self.avatar = avatar
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
        self.pinned = pinned
        self.muted = muted
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
