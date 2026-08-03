import Foundation
import ConnorGraphCore

private enum ImJSONValue: Codable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case object([String: ImJSONValue])
    case array([ImJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: ImJSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([ImJSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeJSONStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        if let string = try? decode(String.self, forKey: key) { return string }
        let value = try decode(ImJSONValue.self, forKey: key)
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)
    }

    func decodeStringOrNumberIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        if let string = try? decode(String.self, forKey: key) { return string }
        if let integer = try? decode(Int64.self, forKey: key) { return String(integer) }
        if let double = try? decode(Double.self, forKey: key) { return String(double) }
        return nil
    }
}

/// REST contract for the IM feature (peer chat / group chat / friends), aligned
/// byte-for-byte with the backend's JSON tags and the Android client's DTOs.
/// Responses use the `{code, msg, data}` envelope (code 0 = success); fields are
/// camelCase and timestamps are RFC3339 strings. Known contract quirks:
/// history paging's `has_more` is snake_case, and friend/friend-request IDs are
/// serialized under the uppercase key `"ID"`.

public struct ImChatMessageDTO: Decodable, Sendable, Equatable {
    public var messageId: String
    public var senderId: Int64
    public var receiverId: Int64
    public var messageType: String
    public var content: String
    public var extra: String
    public var isAgent: Bool
    public var status: String
    public var sentAt: String

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try values.decode(String.self, forKey: .messageId)
        senderId = try values.decode(Int64.self, forKey: .senderId)
        receiverId = try values.decodeIfPresent(Int64.self, forKey: .receiverId) ?? 0
        messageType = try values.decodeIfPresent(String.self, forKey: .messageType) ?? "text"
        content = try values.decodeIfPresent(String.self, forKey: .content) ?? ""
        extra = try values.decodeJSONStringIfPresent(forKey: .extra) ?? "{}"
        isAgent = try values.decodeIfPresent(Bool.self, forKey: .isAgent) ?? false
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "sent"
        sentAt = try values.decodeStringOrNumberIfPresent(forKey: .sentAt) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case messageId, senderId, receiverId, messageType, content, extra, isAgent, status, sentAt
    }
}

public struct ImConversationDTO: Decodable, Sendable, Equatable {
    public var peerId: Int64
    public var lastMessageId: String
    public var lastMessageContent: String
    public var lastMessageType: String
    public var lastMessageTime: String
    public var unreadCount: Int

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        peerId = try values.decode(Int64.self, forKey: .peerId)
        lastMessageId = try values.decodeIfPresent(String.self, forKey: .lastMessageId) ?? ""
        lastMessageContent = try values.decodeIfPresent(String.self, forKey: .lastMessageContent) ?? ""
        lastMessageType = try values.decodeIfPresent(String.self, forKey: .lastMessageType) ?? ""
        lastMessageTime = try values.decodeIfPresent(String.self, forKey: .lastMessageTime) ?? ""
        unreadCount = try values.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case peerId, lastMessageId, lastMessageContent, lastMessageType, lastMessageTime, unreadCount
    }
}

public struct ImChatHistoryDTO: Decodable, Sendable, Equatable {
    public var messages: [ImChatMessageDTO]
    public var hasMore: Bool

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        messages = try values.decodeIfPresent([ImChatMessageDTO].self, forKey: .messages) ?? []
        hasMore = try values.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
    }
}

public struct ImUnreadConversationDTO: Decodable, Sendable, Equatable {
    public var peerId: Int64
    public var unreadCount: Int
    public var lastMessageId: String
    public var lastMessageContent: String
    public var lastMessageType: String
    public var lastMessageTime: String

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        peerId = try values.decode(Int64.self, forKey: .peerId)
        unreadCount = try values.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        lastMessageId = try values.decodeIfPresent(String.self, forKey: .lastMessageId) ?? ""
        lastMessageContent = try values.decodeIfPresent(String.self, forKey: .lastMessageContent) ?? ""
        lastMessageType = try values.decodeIfPresent(String.self, forKey: .lastMessageType) ?? ""
        lastMessageTime = try values.decodeIfPresent(String.self, forKey: .lastMessageTime) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case peerId, unreadCount, lastMessageId, lastMessageContent, lastMessageType, lastMessageTime
    }
}

public struct ImUnreadSummaryDTO: Decodable, Sendable, Equatable {
    public var totalUnread: Int64
    public var conversations: [ImUnreadConversationDTO]

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        totalUnread = try values.decodeIfPresent(Int64.self, forKey: .totalUnread) ?? 0
        conversations = try values.decodeIfPresent([ImUnreadConversationDTO].self, forKey: .conversations) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case totalUnread, conversations
    }
}

public struct ImMarkReadResultDTO: Decodable, Sendable, Equatable {
    public var updatedCount: Int64
    public var unreadCount: Int

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        updatedCount = try values.decodeIfPresent(Int64.self, forKey: .updatedCount) ?? 0
        unreadCount = try values.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case updatedCount, unreadCount
    }
}

public struct ImGroupDTO: Decodable, Sendable, Equatable {
    public var groupId: String
    public var name: String
    public var description: String
    public var avatar: String
    public var creatorId: Int64
    public var memberCount: Int
    public var lastMessageId: String
    public var lastMessageContent: String
    public var lastMessageType: String
    public var lastMessageTime: String
    public var agentEnabled: Bool
    public var creatorUsername: String

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try values.decode(String.self, forKey: .groupId)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        avatar = try values.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        creatorId = try values.decodeIfPresent(Int64.self, forKey: .creatorId) ?? 0
        memberCount = try values.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        lastMessageId = try values.decodeIfPresent(String.self, forKey: .lastMessageId) ?? ""
        lastMessageContent = try values.decodeIfPresent(String.self, forKey: .lastMessageContent) ?? ""
        lastMessageType = try values.decodeIfPresent(String.self, forKey: .lastMessageType) ?? ""
        lastMessageTime = try values.decodeIfPresent(String.self, forKey: .lastMessageTime) ?? ""
        agentEnabled = try values.decodeIfPresent(Bool.self, forKey: .agentEnabled) ?? false
        creatorUsername = try values.decodeIfPresent(String.self, forKey: .creatorUsername) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case groupId, name, description, avatar, creatorId, memberCount
        case lastMessageId, lastMessageContent, lastMessageType, lastMessageTime, agentEnabled, creatorUsername
    }
}

public struct ImGroupListDTO: Decodable, Sendable, Equatable {
    public var groups: [ImGroupDTO]
    public var total: Int

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        groups = try values.decodeIfPresent([ImGroupDTO].self, forKey: .groups) ?? []
        total = try values.decodeIfPresent(Int.self, forKey: .total) ?? groups.count
    }

    private enum CodingKeys: String, CodingKey { case groups, total }
}

public struct ImGroupCreateDTO: Decodable, Sendable, Equatable {
    public var groupId: String
    public var createdAt: Int64

    private enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case createdAt = "created_at"
    }
}

public struct ImGroupMemberDTO: Decodable, Sendable, Equatable, Identifiable {
    public var groupId: String
    public var userId: Int64
    public var role: String
    public var username: String
    public var email: String
    public var avatar: String
    public var joinedAt: String

    public var id: Int64 { userId }
    public var displayName: String { username.isEmpty ? "用户 \(userId)" : username }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try values.decodeIfPresent(String.self, forKey: .groupId) ?? ""
        userId = try values.decode(Int64.self, forKey: .userId)
        role = try values.decodeIfPresent(String.self, forKey: .role) ?? "member"
        username = try values.decodeIfPresent(String.self, forKey: .username) ?? ""
        email = try values.decodeIfPresent(String.self, forKey: .email) ?? ""
        avatar = try values.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        joinedAt = try values.decodeStringOrNumberIfPresent(forKey: .joinedAt) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case groupId, userId, role, username, email, avatar, joinedAt
    }
}

public struct ImGroupMembersDTO: Decodable, Sendable, Equatable {
    public var members: [ImGroupMemberDTO]

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        members = try values.decodeIfPresent([ImGroupMemberDTO].self, forKey: .members) ?? []
    }

    private enum CodingKeys: String, CodingKey { case members }
}

public struct ImGroupMessageDTO: Decodable, Sendable, Equatable {
    public var messageId: String
    public var groupId: String
    public var senderId: Int64
    public var messageType: String
    public var content: String
    public var extra: String
    public var isAgent: Bool
    public var sentAt: String

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try values.decode(String.self, forKey: .messageId)
        groupId = try values.decodeIfPresent(String.self, forKey: .groupId) ?? ""
        senderId = try values.decode(Int64.self, forKey: .senderId)
        messageType = try values.decodeIfPresent(String.self, forKey: .messageType) ?? "text"
        content = try values.decodeIfPresent(String.self, forKey: .content) ?? ""
        extra = try values.decodeJSONStringIfPresent(forKey: .extra) ?? "{}"
        isAgent = try values.decodeIfPresent(Bool.self, forKey: .isAgent) ?? false
        sentAt = try values.decodeStringOrNumberIfPresent(forKey: .sentAt) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case messageId, groupId, senderId, messageType, content, extra, isAgent, sentAt
    }
}

public struct ImMediaUploadDTO: Decodable, Sendable, Equatable {
    public var uploadURL: String
    public var objectName: String
    public var downloadURL: String
    public var expiresIn: Int64

    private enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case objectName = "object_name"
        case downloadURL = "download_url"
        case expiresIn = "expires_in"
    }
}

public struct ImGroupHistoryDTO: Decodable, Sendable, Equatable {
    public var messages: [ImGroupMessageDTO]
    public var hasMore: Bool

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        messages = try values.decodeIfPresent([ImGroupMessageDTO].self, forKey: .messages) ?? []
        hasMore = try values.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
    }
}

public struct ImFriendDTO: Decodable, Sendable, Equatable {
    public var id: Int64
    public var userId: Int64
    public var friendId: Int64
    public var status: String
    public var username: String
    public var nickname: String
    public var email: String
    public var avatar: String

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        userId = try values.decode(Int64.self, forKey: .userId)
        friendId = try values.decode(Int64.self, forKey: .friendId)
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "accepted"
        username = try values.decode(String.self, forKey: .username)
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        email = try values.decodeIfPresent(String.self, forKey: .email) ?? ""
        avatar = try values.decodeIfPresent(String.self, forKey: .avatar) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case userId, friendId, status, username, nickname, email, avatar
    }
}

public struct ImFriendRequestDTO: Decodable, Sendable, Equatable {
    public var id: Int64
    public var senderId: Int64
    public var receiverId: Int64
    public var message: String
    public var status: String
    public var senderUsername: String
    public var senderNickname: String
    public var senderEmail: String
    public var senderAvatar: String
    public var receiverUsername: String
    public var receiverNickname: String
    public var receiverEmail: String
    public var receiverAvatar: String
    public var createdAt: String

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        senderId = try values.decode(Int64.self, forKey: .senderId)
        receiverId = try values.decode(Int64.self, forKey: .receiverId)
        message = try values.decodeIfPresent(String.self, forKey: .message) ?? ""
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        senderUsername = try values.decodeIfPresent(String.self, forKey: .senderUsername) ?? ""
        senderNickname = try values.decodeIfPresent(String.self, forKey: .senderNickname) ?? ""
        senderEmail = try values.decodeIfPresent(String.self, forKey: .senderEmail) ?? ""
        senderAvatar = try values.decodeIfPresent(String.self, forKey: .senderAvatar) ?? ""
        receiverUsername = try values.decodeIfPresent(String.self, forKey: .receiverUsername) ?? ""
        receiverNickname = try values.decodeIfPresent(String.self, forKey: .receiverNickname) ?? ""
        receiverEmail = try values.decodeIfPresent(String.self, forKey: .receiverEmail) ?? ""
        receiverAvatar = try values.decodeIfPresent(String.self, forKey: .receiverAvatar) ?? ""
        createdAt = try values.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case senderId, receiverId, message, status
        case senderUsername, senderNickname, senderEmail, senderAvatar
        case receiverUsername, receiverNickname, receiverEmail, receiverAvatar, createdAt
    }
}

public struct ImPublicUserDTO: Decodable, Sendable, Equatable {
    public var id: Int64
    public var username: String
    public var nickname: String
    public var avatarUrl: String

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        username = try values.decode(String.self, forKey: .username)
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        avatarUrl = try values.decodeIfPresent(String.self, forKey: .avatarUrl) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, nickname, avatarUrl
    }
}

// MARK: - Client

/// Token-per-call IM REST client. Unwraps the `{code, msg, data}` envelope; a 401
/// maps to `ConnorBackendAPIError.unauthorized`, a non-zero code to `.server`.
public struct ImAPIClient: Sendable {
    public var baseURL: URL
    private let transport: any ConnorBackendHTTPTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL, transport: any ConnorBackendHTTPTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.transport = transport
    }

    // ---- Peer chat ----

    public func conversations(token: String) async throws -> [ImConversationDTO] {
        try await request("chat/conversations", token: token)
    }

    public func chatHistory(token: String, peerId: Int64, beforeId: String? = nil, limit: Int = 20) async throws -> ImChatHistoryDTO {
        try await request("chat/history/\(peerId)?limit=\(limit)\(beforeIdQuery(beforeId))", token: token)
    }

    public func markRead(token: String, peerId: Int64, messageIds: [String] = []) async throws -> ImMarkReadResultDTO {
        try await request("chat/read", method: "POST", token: token, body: MarkReadBody(peerId: peerId, messageIds: messageIds))
    }

    public func unreadSummary(token: String) async throws -> ImUnreadSummaryDTO {
        try await request("chat/unread-summary", token: token)
    }

    public func mediaUpload(token: String, fileURL: URL, messageType: ImMessageType) async throws -> ImMediaUploadDTO {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? NSNumber else { throw ConnorBackendAPIError.invalidResponse }
        let upload: ImMediaUploadDTO = try await request(
            "chat/upload-url",
            method: "POST",
            token: token,
            body: MediaUploadBody(
                fileName: fileURL.lastPathComponent,
                fileSize: fileSize.int64Value,
                messageType: messageType.rawValue
            )
        )
        guard let uploadURL = URL(string: upload.uploadURL) else { throw ConnorBackendAPIError.invalidResponse }
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.httpBody = try Data(contentsOf: fileURL)
        uploadRequest.setValue(Self.mimeType(for: fileURL, messageType: messageType), forHTTPHeaderField: "Content-Type")
        let (_, response) = try await transport.data(for: uploadRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ConnorBackendAPIError.invalidResponse
        }
        return upload
    }

    public func markPrivateMediaCached(token: String, messageId: String) async throws {
        try await requestVoid(
            "chat/media/cached",
            method: "POST",
            token: token,
            bodyData: try encoder.encode(MediaCachedBody(messageId: messageId))
        )
    }

    // ---- Group chat ----

    public func myGroups(token: String) async throws -> [ImGroupDTO] {
        try await request("group-chats", token: token)
    }

    public func groupDetail(token: String, groupId: String) async throws -> ImGroupDTO {
        try await request("group-chats/\(groupId)", token: token)
    }

    public func createGroup(
        token: String,
        name: String,
        description: String = "",
        memberIds: [Int64] = []
    ) async throws -> ImGroupDTO {
        try await request(
            "group-chats",
            method: "POST",
            token: token,
            body: CreateGroupBody(name: name, description: description, memberIds: memberIds)
        )
    }

    public func groupMessages(token: String, groupId: String, beforeId: String? = nil, limit: Int = 20) async throws -> ImGroupHistoryDTO {
        try await request(
            "group-chats/\(groupId)/messages?limit=\(limit)\(beforeIdQuery(beforeId))",
            token: token
        )
    }

    public func inviteGroupMember(token: String, groupId: String, userId: Int64) async throws {
        try await requestVoid(
            "group-chats/\(groupId)/members",
            method: "POST",
            token: token,
            bodyData: encoder.encode(InviteMemberBody(userId: userId))
        )
    }

    public func removeGroupMember(token: String, groupId: String, userId: Int64) async throws {
        try await requestVoid(
            "group-chats/\(groupId)/members/\(userId)",
            method: "DELETE",
            token: token
        )
    }

    public func groupMembers(token: String, groupId: String) async throws -> [ImGroupMemberDTO] {
        let result: ImGroupMembersDTO = try await request("group-chats/\(groupId)/members", token: token)
        return result.members
    }

    public func leaveGroup(token: String, groupId: String) async throws {
        try await requestVoid(
            "group-chats/\(groupId)/leave",
            method: "POST",
            token: token,
            bodyData: Data("{}".utf8)
        )
    }

    public func markGroupMediaCached(token: String, groupId: String, messageId: String) async throws {
        try await requestVoid(
            "group-chats/\(groupId)/messages/\(messageId)/media-cached",
            method: "POST",
            token: token,
            bodyData: Data("{}".utf8)
        )
    }

    public func markGroupRead(token: String, groupId: String) async throws {
        try await requestVoid(
            "group-chats/\(groupId)/read",
            method: "POST",
            token: token,
            bodyData: Data("{}".utf8)
        )
    }

    // ---- Friends ----

    public func friends(token: String) async throws -> [ImFriendDTO] {
        try await request("friends", token: token)
    }

    public func sendFriendRequest(token: String, username: String, message: String = "") async throws -> ImFriendRequestDTO {
        try await request("friends/requests", method: "POST", token: token, body: SendFriendRequestBody(username: username, message: message))
    }

    public func receivedFriendRequests(token: String) async throws -> [ImFriendRequestDTO] {
        try await request("friends/requests/received", token: token)
    }

    public func sentFriendRequests(token: String) async throws -> [ImFriendRequestDTO] {
        try await request("friends/requests/sent", token: token)
    }

    public func acceptFriendRequest(token: String, requestId: Int64) async throws -> ImFriendRequestDTO {
        try await request("friends/requests/\(requestId)/accept", method: "PUT", token: token, bodyData: Data("{}".utf8))
    }

    public func rejectFriendRequest(token: String, requestId: Int64) async throws -> ImFriendRequestDTO {
        try await request("friends/requests/\(requestId)/reject", method: "PUT", token: token, bodyData: Data("{}".utf8))
    }

    public func deleteFriend(token: String, userId: Int64) async throws {
        try await requestVoid("friends/\(userId)", method: "DELETE", token: token)
    }

    public func searchUsers(token: String, query: String, limit: Int = 10) async throws -> [ImPublicUserDTO] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        return try await request("friends/users/search?q=\(encoded)&limit=\(limit)", token: token)
    }

    // ---- Plumbing ----

    private struct MarkReadBody: Encodable { var peerId: Int64; var messageIds: [String] }
    private struct SendFriendRequestBody: Encodable { var username: String; var message: String }
    private struct CreateGroupBody: Encodable {
        var name: String
        var description: String
        var memberIds: [Int64]
        enum CodingKeys: String, CodingKey {
            case name, description
            case memberIds = "member_ids"
        }
    }
    private struct InviteMemberBody: Encodable {
        var userId: Int64
        enum CodingKeys: String, CodingKey { case userId = "user_id" }
    }
    private struct MediaUploadBody: Encodable {
        var fileName: String
        var fileSize: Int64
        var messageType: String
        enum CodingKeys: String, CodingKey {
            case fileName = "file_name"
            case fileSize = "file_size"
            case messageType = "message_type"
        }
    }
    private struct MediaCachedBody: Encodable {
        var messageId: String
        enum CodingKeys: String, CodingKey { case messageId = "message_id" }
    }

    private struct ImAPIEnvelope<T: Decodable>: Decodable { var code: Int?; var msg: String?; var data: T? }

    private func beforeIdQuery(_ beforeId: String?) -> String {
        guard let beforeId, !beforeId.isEmpty else { return "" }
        return "&before_id=\(beforeId)"
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        token: String,
        versioned: Bool = true
    ) async throws -> T {
        try await request(path, method: method, token: token, bodyData: nil, versioned: versioned)
    }

    private func request<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String,
        token: String,
        body: Body,
        versioned: Bool = true
    ) async throws -> T {
        try await request(
            path,
            method: method,
            token: token,
            bodyData: try encoder.encode(body),
            versioned: versioned
        )
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String,
        token: String,
        bodyData: Data?,
        versioned: Bool = true
    ) async throws -> T {
        let data = try await perform(path, method: method, token: token, bodyData: bodyData, versioned: versioned)
        let envelope = try decoder.decode(ImAPIEnvelope<T>.self, from: data)
        guard envelope.code == 0 else {
            throw ConnorBackendAPIError.server(status: 200, message: envelope.msg ?? "服务器请求失败")
        }
        guard let payload = envelope.data else { throw ConnorBackendAPIError.invalidResponse }
        return payload
    }

    private func requestVoid(
        _ path: String,
        method: String,
        token: String,
        bodyData: Data? = nil,
        versioned: Bool = true
    ) async throws {
        let data = try await perform(path, method: method, token: token, bodyData: bodyData, versioned: versioned)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let code = object["code"] as? Int, code != 0 {
            throw ConnorBackendAPIError.server(status: 200, message: object["msg"] as? String ?? "服务器请求失败")
        }
    }

    private func perform(
        _ path: String,
        method: String,
        token: String,
        bodyData: Data?,
        versioned: Bool = true
    ) async throws -> Data {
        let root = versioned ? baseURL.appendingPathComponent("api/v1/") : baseURL
        guard let url = URL(string: path, relativeTo: root) else {
            throw ConnorBackendAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnorBackendAPIError.invalidResponse }
        if http.statusCode == 401 { throw ConnorBackendAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["msg"] as? String ?? "请求失败（\(http.statusCode)）"
            throw ConnorBackendAPIError.server(status: http.statusCode, message: message)
        }
        return data
    }

    private static func mimeType(for url: URL, messageType: ImMessageType) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        default: return messageType == .audio ? "audio/mp4" : "application/octet-stream"
        }
    }
}

// MARK: - Authenticated wrapper

/// IM endpoints wrapped with the shared token-refresh session: a 401 triggers a
/// single-flight refresh through `ConnorBackendAuthenticatedSession` and one retry.
public struct ImBackendService: Sendable {
    private let api: ImAPIClient
    private let session: ConnorBackendAuthenticatedSession

    public init(api: ImAPIClient, session: ConnorBackendAuthenticatedSession) {
        self.api = api
        self.session = session
    }

    public func conversations() async throws -> [ImConversationDTO] {
        try await authenticated { try await api.conversations(token: $0) }
    }

    public func chatHistory(peerId: Int64, beforeId: String? = nil, limit: Int = 20) async throws -> ImChatHistoryDTO {
        try await authenticated { try await api.chatHistory(token: $0, peerId: peerId, beforeId: beforeId, limit: limit) }
    }

    @discardableResult
    public func markRead(peerId: Int64, messageIds: [String] = []) async throws -> ImMarkReadResultDTO {
        try await authenticated { try await api.markRead(token: $0, peerId: peerId, messageIds: messageIds) }
    }

    public func unreadSummary() async throws -> ImUnreadSummaryDTO {
        try await authenticated { try await api.unreadSummary(token: $0) }
    }

    public func uploadMedia(fileURL: URL, messageType: ImMessageType) async throws -> ImMediaUploadDTO {
        try await authenticated { try await api.mediaUpload(token: $0, fileURL: fileURL, messageType: messageType) }
    }

    public func markPrivateMediaCached(messageId: String) async throws {
        try await authenticated { try await api.markPrivateMediaCached(token: $0, messageId: messageId) }
    }

    public func markGroupMediaCached(groupId: String, messageId: String) async throws {
        try await authenticated { try await api.markGroupMediaCached(token: $0, groupId: groupId, messageId: messageId) }
    }

    public func markGroupRead(groupId: String) async throws {
        try await authenticated { try await api.markGroupRead(token: $0, groupId: groupId) }
    }

    public func myGroups() async throws -> [ImGroupDTO] {
        try await authenticated { try await api.myGroups(token: $0) }
    }

    public func groupDetail(groupId: String) async throws -> ImGroupDTO {
        try await authenticated { try await api.groupDetail(token: $0, groupId: groupId) }
    }

    public func groupMembers(groupId: String) async throws -> [ImGroupMemberDTO] {
        try await authenticated { try await api.groupMembers(token: $0, groupId: groupId) }
    }

    public func createGroup(name: String, description: String = "", memberIds: [Int64] = []) async throws -> ImGroupDTO {
        try await authenticated {
            try await api.createGroup(token: $0, name: name, description: description, memberIds: memberIds)
        }
    }

    public func groupMessages(groupId: String, beforeId: String? = nil, limit: Int = 20) async throws -> ImGroupHistoryDTO {
        try await authenticated { try await api.groupMessages(token: $0, groupId: groupId, beforeId: beforeId, limit: limit) }
    }

    public func inviteGroupMember(groupId: String, userId: Int64) async throws {
        try await authenticated { try await api.inviteGroupMember(token: $0, groupId: groupId, userId: userId) }
    }

    public func removeGroupMember(groupId: String, userId: Int64) async throws {
        try await authenticated { try await api.removeGroupMember(token: $0, groupId: groupId, userId: userId) }
    }

    public func leaveGroup(groupId: String) async throws {
        try await authenticated { try await api.leaveGroup(token: $0, groupId: groupId) }
    }

    public func friends() async throws -> [ImFriendDTO] {
        try await authenticated { try await api.friends(token: $0) }
    }

    @discardableResult
    public func sendFriendRequest(username: String, message: String = "") async throws -> ImFriendRequestDTO {
        try await authenticated { try await api.sendFriendRequest(token: $0, username: username, message: message) }
    }

    public func receivedFriendRequests() async throws -> [ImFriendRequestDTO] {
        try await authenticated { try await api.receivedFriendRequests(token: $0) }
    }

    public func sentFriendRequests() async throws -> [ImFriendRequestDTO] {
        try await authenticated { try await api.sentFriendRequests(token: $0) }
    }

    @discardableResult
    public func acceptFriendRequest(requestId: Int64) async throws -> ImFriendRequestDTO {
        try await authenticated { try await api.acceptFriendRequest(token: $0, requestId: requestId) }
    }

    @discardableResult
    public func rejectFriendRequest(requestId: Int64) async throws -> ImFriendRequestDTO {
        try await authenticated { try await api.rejectFriendRequest(token: $0, requestId: requestId) }
    }

    public func deleteFriend(userId: Int64) async throws {
        try await authenticated { try await api.deleteFriend(token: $0, userId: userId) }
    }

    public func searchUsers(query: String, limit: Int = 10) async throws -> [ImPublicUserDTO] {
        try await authenticated { try await api.searchUsers(token: $0, query: query, limit: limit) }
    }

    private func authenticated<Value: Sendable>(
        _ operation: @Sendable (String) async throws -> Value
    ) async throws -> Value {
        let token = try await session.accessToken()
        do {
            return try await operation(token)
        } catch ConnorBackendAPIError.unauthorized {
            let refreshed = try await session.refreshAccessToken(afterRejectedToken: token)
            return try await operation(refreshed)
        }
    }
}
