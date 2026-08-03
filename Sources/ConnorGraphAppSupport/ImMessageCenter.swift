import Foundation
import ConnorGraphCore

/// Signed-in identity snapshot needed by the message center (id + display name).
public struct ImSelfIdentity: Sendable, Equatable {
    public var id: Int64
    public var displayName: String

    public init(id: Int64, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// REST surface consumed by `ImMessageCenter`; `ImBackendService` is the production
/// implementation, tests substitute a stub.
public protocol ImBackendServicing: Sendable {
    func conversations() async throws -> [ImConversationDTO]
    func chatHistory(peerId: Int64, beforeId: String?, limit: Int) async throws -> ImChatHistoryDTO
    @discardableResult
    func markRead(peerId: Int64, messageIds: [String]) async throws -> ImMarkReadResultDTO
    func myGroups() async throws -> [ImGroupDTO]
    func createGroup(name: String, description: String) async throws -> ImGroupDTO
    func groupMessages(groupId: String, beforeId: String?, limit: Int) async throws -> ImGroupHistoryDTO
    func inviteGroupMember(groupId: String, userId: Int64) async throws
    func removeGroupMember(groupId: String, userId: Int64) async throws
    func friends() async throws -> [ImFriendDTO]
    @discardableResult
    func sendFriendRequest(username: String, message: String) async throws -> ImFriendRequestDTO
    func receivedFriendRequests() async throws -> [ImFriendRequestDTO]
    func sentFriendRequests() async throws -> [ImFriendRequestDTO]
    @discardableResult
    func acceptFriendRequest(requestId: Int64) async throws -> ImFriendRequestDTO
    @discardableResult
    func rejectFriendRequest(requestId: Int64) async throws -> ImFriendRequestDTO
    func deleteFriend(userId: Int64) async throws
    func searchUsers(query: String, limit: Int) async throws -> [ImPublicUserDTO]
}

extension ImBackendService: ImBackendServicing {}

/// IM message hub: peer/group send-receive, receipts, unread counters and REST
/// backfill, ported one-to-one from the Android `ImMessageCenter` semantics.
///
/// Transport topology:
/// - realtime frames ride the shared `/ws/device` socket (wired via `handleFrame`);
/// - cold-start / reconnect backfill and history paging go through REST.
///
/// Protocol quirk (verbatim from the backend): the synchronous reply to
/// `chat_send`/`group_send` is a **bare, typeless message JSON** (camelCase with
/// `messageId`); only failures carry `type=error`. Uplinks are therefore paired
/// with replies through a FIFO pending queue. Actor isolation serializes frame
/// handling, matching Android's single-consumer channel.
public actor ImMessageCenter {
    public struct Configuration: Sendable {
        /// An uplink without a paired reply within this window becomes FAILED.
        public var sendTimeout: Duration
        /// Injectable clock (Unix milliseconds) for deterministic tests.
        public var now: @Sendable () -> Int64

        public init(
            sendTimeout: Duration = .seconds(15),
            now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
        ) {
            self.sendTimeout = sendTimeout
            self.now = now
        }
    }

    private let store: any ImStore
    private let service: any ImBackendServicing
    private let sendFrame: @Sendable (String) async -> Bool
    private let currentIdentity: @Sendable () -> ImSelfIdentity?
    private let configuration: Configuration

    private struct PendingSend {
        let tempId: String
        let conversationId: String
        var timeoutTask: Task<Void, Never>?
    }

    private var pendingSends: [PendingSend] = []

    /// Currently opened conversation: its incoming messages neither count as unread
    /// nor stay unacknowledged (auto read receipt).
    public private(set) var activeConversationId: String?

    public init(
        store: any ImStore,
        service: any ImBackendServicing,
        sendFrame: @escaping @Sendable (String) async -> Bool,
        currentIdentity: @escaping @Sendable () -> ImSelfIdentity?,
        configuration: Configuration = Configuration()
    ) {
        self.store = store
        self.service = service
        self.sendFrame = sendFrame
        self.currentIdentity = currentIdentity
        self.configuration = configuration
    }

    public func setActiveConversation(_ id: String?) {
        activeConversationId = id
    }

    public func selfUserId() -> Int64? { currentIdentity()?.id }

    /// Cold-start recovery: optimistic sends dangling from a previous process
    /// can never be acked anymore, surface them as retryable failures.
    public func prepareAfterLaunch() async {
        try? await store.markSendingFailed()
    }

    /// Socket (re)connected: full backfill covers cold start and pushes missed offline.
    public func handleSocketConnected() async {
        await refreshAll()
    }

    /// Sign-out / account switch: IM caches are per-account server projections.
    public func handleSignOut() async {
        for pending in pendingSends { pending.timeoutTask?.cancel() }
        pendingSends.removeAll()
        try? await store.clearConversations()
        try? await store.clearFriends()
        try? await store.clearFriendRequests()
        try? await store.clearForwardAliases()
    }

    // MARK: - Sending (optimistic insert → WS uplink → typeless-reply FIFO pairing)

    /// Send a peer message; a rejected uplink or timeout marks FAILED (retryable).
    public func sendChatMessage(peerId: Int64, content: String, messageType: String = "text") async throws {
        let conversationId = try await ensurePeerConversation(peerId: peerId)
        let frame = Self.encodeFrame(type: "chat_send", payload: [
            "receiver_id": peerId,
            "message_type": messageType,
            "content": content,
        ])
        try await sendOptimistic(conversationId: conversationId, content: content, messageType: messageType, frame: frame)
    }

    /// Send a group message.
    public func sendGroupMessage(groupId: String, content: String, messageType: String = "text") async throws {
        let conversationId = try await ensureGroupConversation(groupId: groupId)
        let frame = Self.encodeFrame(type: "group_send", payload: [
            "group_id": groupId,
            "message_type": messageType,
            "content": content,
        ])
        try await sendOptimistic(conversationId: conversationId, content: content, messageType: messageType, frame: frame)
    }

    /// Retry a FAILED message: reuse the same temp id for another uplink round.
    public func retryMessage(messageId: String) async throws {
        guard let message = try await store.message(id: messageId), message.status == .failed else { return }
        guard let conversation = try await store.conversation(id: message.conversationId) else { return }
        let frame: String
        switch conversation.kind {
        case .group:
            guard let groupId = conversation.groupId else { return }
            frame = Self.encodeFrame(type: "group_send", payload: [
                "group_id": groupId,
                "message_type": message.messageType,
                "content": message.content,
            ])
        case .peer:
            guard let peerId = conversation.peerUserId else { return }
            frame = Self.encodeFrame(type: "chat_send", payload: [
                "receiver_id": peerId,
                "message_type": message.messageType,
                "content": message.content,
            ])
        }
        try await store.updateMessageStatus(id: message.id, status: .sending)
        await dispatchPending(tempId: message.id, conversationId: message.conversationId, frame: frame)
    }

    private func sendOptimistic(conversationId: String, content: String, messageType: String, frame: String) async throws {
        guard let selfUser = currentIdentity() else { throw ConnorBackendAPIError.unauthorized }
        let now = configuration.now()
        let tempId = ImMessage.makeTemporaryID()
        _ = try await store.upsertMessage(ImMessage(
            id: tempId,
            conversationId: conversationId,
            senderId: selfUser.id,
            senderName: selfUser.displayName,
            messageType: messageType,
            content: content,
            status: .sending,
            createdAt: now,
            extraJson: "{}"
        ))
        try await touchConversation(id: conversationId, preview: String(content.prefix(100)), at: now, unreadDelta: 0)
        await dispatchPending(tempId: tempId, conversationId: conversationId, frame: frame)
    }

    private func dispatchPending(tempId: String, conversationId: String, frame: String) async {
        pendingSends.append(PendingSend(tempId: tempId, conversationId: conversationId, timeoutTask: nil))
        guard await sendFrame(frame) else {
            await failPending(tempId: tempId)
            return
        }
        let timeout = configuration.sendTimeout
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.failPending(tempId: tempId)
        }
        if let index = pendingSends.firstIndex(where: { $0.tempId == tempId }) {
            pendingSends[index].timeoutTask = timeoutTask
        } else {
            // Reply already paired while the uplink was in flight.
            timeoutTask.cancel()
        }
    }

    private func failPending(tempId: String) async {
        guard let index = pendingSends.firstIndex(where: { $0.tempId == tempId }) else { return }
        let pending = pendingSends.remove(at: index)
        pending.timeoutTask?.cancel()
        try? await store.updateMessageStatus(id: pending.tempId, status: .failed)
    }

    private func popPending() -> PendingSend? {
        guard !pendingSends.isEmpty else { return nil }
        let pending = pendingSends.removeFirst()
        pending.timeoutTask?.cancel()
        return pending
    }

    // MARK: - Frame handling (actor-serialized)

    /// Entry point for `/ws/device` IM frames (wire to `AppUserIdentityStore.onImFrame`).
    public func handleFrame(type: String?, text: String) async {
        guard let root = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return }
        let payload = root["payload"] as? [String: Any]
        switch type {
        case "chat_receive":
            if let payload { await onChatReceive(payload) }
        case "group_receive":
            if let payload { await onGroupReceive(payload) }
        case "friend_request_received", "friend_request_accepted", "friend_request_rejected":
            try? await refreshFriendData()
        case "friend_deleted":
            if let userId = Self.int64Value(payload?["user_id"]) {
                try? await store.deleteFriend(userId: userId)
            }
        case "error":
            if let pending = popPending() {
                try? await store.updateMessageStatus(id: pending.tempId, status: .failed)
            }
        case nil:
            await onTypelessReply(root)
        default:
            break
        }
    }

    /// Typeless reply: the bare message JSON (camelCase, has `messageId`) answering
    /// a chat_send/group_send; anything else without `messageId` is ignored.
    private func onTypelessReply(_ root: [String: Any]) async {
        guard let serverId = root["messageId"] as? String else { return }
        guard let pending = popPending() else { return }
        if (try? await store.message(id: serverId)) != nil {
            // The group echo raced ahead of the reply: the server row already
            // exists, drop the optimistic temp row.
            try? await store.deleteMessage(id: pending.tempId)
        } else {
            try? await store.replaceMessageId(oldId: pending.tempId, newId: serverId, status: .sent)
        }
    }

    /// chat_receive push (snake_case payload, `sent_at` in Unix milliseconds).
    /// Agent-authored messages flow into the same conversation stream.
    private func onChatReceive(_ payload: [String: Any]) async {
        guard let selfId = selfUserId() else { return }
        guard let senderId = Self.int64Value(payload["sender_id"]), senderId != selfId else { return }
        guard let messageId = payload["message_id"] as? String else { return }
        let fallbackTitle = payload["sender_username"] as? String
        guard let conversationId = try? await ensurePeerConversation(peerId: senderId, fallbackTitle: fallbackTitle) else { return }
        let sentAt = Self.int64Value(payload["sent_at"]) ?? configuration.now()
        await insertIncoming(ImMessage(
            id: messageId,
            conversationId: conversationId,
            senderId: senderId,
            senderName: payload["sender_username"] as? String ?? "",
            messageType: payload["message_type"] as? String ?? "text",
            content: payload["content"] as? String ?? "",
            status: .delivered,
            createdAt: sentAt,
            extraJson: Self.objectJson(payload["extra"])
        ))
    }

    /// group_receive push: every member (sender included) receives it; the unique
    /// message id dedupes the sender's own echo.
    private func onGroupReceive(_ payload: [String: Any]) async {
        guard let selfId = selfUserId() else { return }
        guard let groupId = payload["group_id"] as? String else { return }
        guard let messageId = payload["message_id"] as? String else { return }
        guard let senderId = Self.int64Value(payload["sender_id"]) else { return }
        guard let conversationId = try? await ensureGroupConversation(groupId: groupId) else { return }
        let sentAt = Self.int64Value(payload["sent_at"]) ?? configuration.now()
        await insertIncoming(
            ImMessage(
                id: messageId,
                conversationId: conversationId,
                senderId: senderId,
                senderName: payload["sender_username"] as? String ?? "",
                senderAvatar: payload["sender_avatar"] as? String ?? "",
                messageType: payload["message_type"] as? String ?? "text",
                content: payload["content"] as? String ?? "",
                status: senderId == selfId ? .sent : .delivered,
                createdAt: sentAt,
                extraJson: Self.objectJson(payload["extra"])
            ),
            countUnread: senderId != selfId
        )
    }

    /// Idempotent insert keyed by the unique message id, then bump the conversation.
    private func insertIncoming(_ message: ImMessage, countUnread: Bool = true) async {
        if (try? await store.message(id: message.id)) != nil { return }
        _ = try? await store.upsertMessage(message)
        let active = message.conversationId == activeConversationId
        try? await touchConversation(
            id: message.conversationId,
            preview: String(message.content.prefix(100)),
            at: message.createdAt,
            unreadDelta: (countUnread && !active) ? 1 : 0
        )
        if active && countUnread {
            await markConversationRead(message.conversationId)
        }
    }

    // MARK: - Conversations

    /// Contact-list "send message" entry: ensure the peer conversation exists so the
    /// chat page opens even before the first message.
    public func openPeerConversation(peerId: Int64) async throws -> String {
        try await ensurePeerConversation(peerId: peerId)
    }

    private func ensurePeerConversation(peerId: Int64, fallbackTitle: String? = nil) async throws -> String {
        let id = ImConversation.peerConversationID(peerUserId: peerId)
        if try await store.conversation(id: id) == nil {
            let friend = try await store.friend(userId: peerId)
            let friendTitle = friend.flatMap { $0.nickname.isEmpty ? ($0.username.isEmpty ? nil : $0.username) : $0.nickname }
            let now = configuration.now()
            try await store.upsertConversation(ImConversation(
                id: id,
                kind: .peer,
                peerUserId: peerId,
                title: friendTitle ?? fallbackTitle ?? "用户 \(peerId)",
                avatar: friend?.avatar ?? "",
                lastMessageAt: now,
                updatedAt: now
            ))
        }
        return id
    }

    private func ensureGroupConversation(groupId: String, title: String? = nil) async throws -> String {
        let id = ImConversation.groupConversationID(groupId: groupId)
        if try await store.conversation(id: id) == nil {
            let now = configuration.now()
            try await store.upsertConversation(ImConversation(
                id: id,
                kind: .group,
                groupId: groupId,
                title: title ?? "群聊",
                lastMessageAt: now,
                updatedAt: now
            ))
        }
        return id
    }

    private func touchConversation(id: String, preview: String, at: Int64, unreadDelta: Int) async throws {
        guard var existing = try await store.conversation(id: id) else { return }
        existing.lastMessagePreview = preview
        existing.lastMessageAt = max(existing.lastMessageAt, at)
        existing.unreadCount += unreadDelta
        existing.updatedAt = configuration.now()
        try await store.upsertConversation(existing)
    }

    /// Opening a conversation clears the local unread counter; peer chats also
    /// report read state to the server (group read receipts are not supported yet).
    public func markConversationRead(_ conversationId: String) async {
        try? await store.clearUnread(conversationId: conversationId, now: configuration.now())
        guard let conversation = try? await store.conversation(id: conversationId),
              conversation.kind == .peer,
              let peerId = conversation.peerUserId else { return }
        _ = try? await service.markRead(peerId: peerId, messageIds: [])
    }

    public func setPinned(conversationId: String, pinned: Bool) async throws {
        try await store.setPinned(conversationId: conversationId, pinned: pinned, now: configuration.now())
    }

    public func setMuted(conversationId: String, muted: Bool) async throws {
        try await store.setMuted(conversationId: conversationId, muted: muted, now: configuration.now())
    }

    public func renameConversation(conversationId: String, title: String, customized: Bool = true) async throws {
        try await store.renameConversation(
            conversationId: conversationId,
            title: title,
            customized: customized,
            now: configuration.now()
        )
    }

    public func setConversationStatus(conversationId: String, status: AgentSessionStatus) async throws {
        try await store.setConversationStatus(conversationId: conversationId, status: status, now: configuration.now())
    }

    public func setConversationLabels(conversationId: String, labelIds: [String]) async throws {
        try await store.setConversationLabels(conversationId: conversationId, labelIds: labelIds, now: configuration.now())
    }

    public func deleteConversation(_ conversationId: String) async throws {
        try await store.deleteConversation(id: conversationId)
    }

    // MARK: - Backfill (REST)

    /// Full backfill: friends + conversations + groups (login and socket reconnect).
    public func refreshAll() async {
        guard currentIdentity() != nil else { return }
        try? await refreshFriendData()
        try? await refreshConversations()
        try? await refreshGroups()
    }

    private func refreshConversations() async throws {
        let remote = try await service.conversations()
        for dto in remote {
            let id = try await ensurePeerConversation(peerId: dto.peerId)
            guard var existing = try await store.conversation(id: id) else { continue }
            existing.lastMessagePreview = String(dto.lastMessageContent.prefix(100))
            existing.lastMessageAt = max(existing.lastMessageAt, Self.epochMilliseconds(fromRFC3339: dto.lastMessageTime))
            existing.unreadCount = dto.unreadCount
            existing.updatedAt = configuration.now()
            try await store.upsertConversation(existing)
        }
    }

    private func refreshGroups() async throws {
        for group in try await service.myGroups() {
            let id = try await ensureGroupConversation(groupId: group.groupId, title: group.name)
            guard var existing = try await store.conversation(id: id) else { continue }
            existing.participantName = group.name
            if !existing.titleCustomized {
                existing.title = group.name
            }
            existing.avatar = group.avatar
            existing.lastMessagePreview = String(group.lastMessageContent.prefix(100))
            existing.lastMessageAt = max(existing.lastMessageAt, Self.epochMilliseconds(fromRFC3339: group.lastMessageTime))
            existing.updatedAt = configuration.now()
            try await store.upsertConversation(existing)
        }
    }

    private func refreshFriendData() async throws {
        let now = configuration.now()
        let remote = try await service.friends()
        var local: [ImFriend] = []
        local.reserveCapacity(remote.count)
        for dto in remote {
            // Preserve the local friend ↔ person-profile bridge across refreshes.
            let personProfileID = try await store.friend(userId: dto.friendId)?.personProfileID
            local.append(ImFriend(
                userId: dto.friendId,
                username: dto.username,
                nickname: dto.nickname,
                email: dto.email,
                avatar: dto.avatar,
                personProfileID: personProfileID,
                updatedAt: now
            ))
        }
        try await store.upsertFriends(local)
        try await store.pruneFriends(keepUserIds: local.map(\.userId))
        let received = try await service.receivedFriendRequests()
        let sent = try await service.sentFriendRequests()
        let requests = (received + sent).map { dto in
            ImFriendRequest(
                id: dto.id,
                senderId: dto.senderId,
                receiverId: dto.receiverId,
                message: dto.message,
                status: dto.status,
                senderUsername: dto.senderUsername,
                senderNickname: dto.senderNickname,
                senderAvatar: dto.senderAvatar,
                receiverUsername: dto.receiverUsername,
                receiverNickname: dto.receiverNickname,
                createdAt: Self.epochMilliseconds(fromRFC3339: dto.createdAt)
            )
        }
        try await store.upsertFriendRequests(requests)
    }

    // MARK: - History paging

    /// Page backwards using the oldest locally cached server message as the
    /// `before_id` cursor; returns whether even older messages remain.
    public func loadOlderMessages(conversationId: String, limit: Int = 20) async throws -> Bool {
        guard let conversation = try await store.conversation(id: conversationId) else { return false }
        let beforeId = try await store.oldestServerMessageId(conversationId: conversationId)
        let selfUser = currentIdentity()
        switch conversation.kind {
        case .group:
            guard let groupId = conversation.groupId else { return false }
            let page = try await service.groupMessages(groupId: groupId, beforeId: beforeId, limit: limit)
            for dto in page.messages {
                if (try? await store.message(id: dto.messageId)) != nil { continue }
                _ = try await store.upsertMessage(ImMessage(
                    id: dto.messageId,
                    conversationId: conversationId,
                    senderId: dto.senderId,
                    senderName: await senderName(senderId: dto.senderId, selfUser: selfUser),
                    messageType: dto.messageType,
                    content: dto.content,
                    status: .sent,
                    createdAt: Self.epochMilliseconds(fromRFC3339: dto.sentAt),
                    extraJson: dto.extra
                ))
            }
            return page.hasMore
        case .peer:
            guard let peerId = conversation.peerUserId else { return false }
            let page = try await service.chatHistory(peerId: peerId, beforeId: beforeId, limit: limit)
            for dto in page.messages {
                if (try? await store.message(id: dto.messageId)) != nil { continue }
                _ = try await store.upsertMessage(ImMessage(
                    id: dto.messageId,
                    conversationId: conversationId,
                    senderId: dto.senderId,
                    senderName: await senderName(senderId: dto.senderId, selfUser: selfUser),
                    messageType: dto.messageType,
                    content: dto.content,
                    status: ImMessageStatus(rawValue: dto.status.uppercased()) ?? .sent,
                    createdAt: Self.epochMilliseconds(fromRFC3339: dto.sentAt),
                    extraJson: dto.extra
                ))
            }
            return page.hasMore
        }
    }

    private func senderName(senderId: Int64, selfUser: ImSelfIdentity?) async -> String {
        if senderId == selfUser?.id { return selfUser?.displayName ?? "" }
        guard let friend = try? await store.friend(userId: senderId) else { return "" }
        return friend.nickname.isEmpty ? friend.username : friend.nickname
    }

    // MARK: - Friends / contact list (bridge to person profiles)

    public func sendFriendRequest(username: String, message: String = "") async throws {
        _ = try await service.sendFriendRequest(username: username, message: message)
        try? await refreshFriendData()
    }

    public func acceptFriendRequest(requestId: Int64) async throws {
        _ = try await service.acceptFriendRequest(requestId: requestId)
        try? await refreshFriendData()
    }

    public func rejectFriendRequest(requestId: Int64) async throws {
        _ = try await service.rejectFriendRequest(requestId: requestId)
        try? await refreshFriendData()
    }

    public func removeFriend(userId: Int64) async throws {
        try await service.deleteFriend(userId: userId)
        try await store.deleteFriend(userId: userId)
        try await store.deleteConversation(id: ImConversation.peerConversationID(peerUserId: userId))
    }

    public func searchUsers(query: String, limit: Int = 10) async throws -> [ImPublicUserDTO] {
        try await service.searchUsers(query: query, limit: limit)
    }

    /// Friend ↔ person-profile binding (contact-merge bridge; nil unbinds).
    public func bindFriendPerson(userId: Int64, personProfileID: String?) async throws {
        try await store.bindFriendPerson(userId: userId, personProfileID: personProfileID, now: configuration.now())
    }

    public func friendByPerson(personProfileID: String) async throws -> ImFriend? {
        try await store.friendByPerson(personProfileID: personProfileID)
    }

    // MARK: - Group management

    @discardableResult
    public func createGroup(name: String, description: String = "") async throws -> ImGroupDTO {
        let group = try await service.createGroup(name: name, description: description)
        _ = try await ensureGroupConversation(groupId: group.groupId, title: group.name)
        return group
    }

    public func inviteGroupMember(groupId: String, userId: Int64) async throws {
        try await service.inviteGroupMember(groupId: groupId, userId: userId)
    }

    public func removeGroupMember(groupId: String, userId: Int64) async throws {
        try await service.removeGroupMember(groupId: groupId, userId: userId)
    }

    // MARK: - Helpers

    private static func encodeFrame(type: String, payload: [String: Any]) -> String {
        let object: [String: Any] = ["type": type, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber: return number.int64Value
        case let string as String: return Int64(string)
        default: return nil
        }
    }

    /// Serialize a JSON-object payload field back to a string (Android keeps
    /// `extra` as raw JSON text); anything non-object collapses to "{}".
    private static func objectJson(_ value: Any?) -> String {
        guard let object = value as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static let rfc3339 = epochFormatter(options: [.withInternetDateTime])
    private static let rfc3339Fractional = epochFormatter(options: [.withInternetDateTime, .withFractionalSeconds])

    /// ISO8601DateFormatter is not Sendable; wrap it behind an immutable value box.
    private struct EpochFormatter: @unchecked Sendable {
        let formatter: ISO8601DateFormatter
        func date(from value: String) -> Date? { formatter.date(from: value) }
    }

    private static func epochFormatter(options: ISO8601DateFormatter.Options) -> EpochFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        return EpochFormatter(formatter: formatter)
    }

    static func epochMilliseconds(fromRFC3339 value: String) -> Int64 {
        guard !value.isEmpty else { return 0 }
        let date = rfc3339.date(from: value) ?? rfc3339Fractional.date(from: value)
        guard let date else { return 0 }
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}
