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

public enum ImRealtimeEvent: Sendable, Equatable {
    case incomingMessage(message: ImMessage, conversation: ImConversation)
    case incomingFriendRequest(ImFriendRequest)
}

/// REST surface consumed by `ImMessageCenter`; `ImBackendService` is the production
/// implementation, tests substitute a stub.
public protocol ImBackendServicing: Sendable {
    func conversations() async throws -> [ImConversationDTO]
    func chatHistory(peerId: Int64, beforeId: String?, limit: Int) async throws -> ImChatHistoryDTO
    @discardableResult
    func markRead(peerId: Int64, messageIds: [String]) async throws -> ImMarkReadResultDTO
    func myGroups() async throws -> [ImGroupDTO]
    func groupDetail(groupId: String) async throws -> ImGroupDTO
    func groupMembers(groupId: String) async throws -> [ImGroupMemberDTO]
    func createGroup(name: String, description: String, memberIds: [Int64]) async throws -> ImGroupDTO
    func groupMessages(groupId: String, beforeId: String?, limit: Int) async throws -> ImGroupHistoryDTO
    func inviteGroupMember(groupId: String, userId: Int64) async throws
    func removeGroupMember(groupId: String, userId: Int64) async throws
    func leaveGroup(groupId: String) async throws
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
    func uploadMedia(fileURL: URL, messageType: ImMessageType) async throws -> ImMediaUploadDTO
    func markPrivateMediaCached(messageId: String) async throws
    func markGroupMediaCached(groupId: String, messageId: String) async throws
    func markGroupRead(groupId: String) async throws
}

public extension ImBackendServicing {
    func uploadMedia(fileURL: URL, messageType: ImMessageType) async throws -> ImMediaUploadDTO {
        throw ConnorBackendAPIError.invalidResponse
    }
    func markPrivateMediaCached(messageId: String) async throws {}
    func markGroupMediaCached(groupId: String, messageId: String) async throws {}
    func markGroupRead(groupId: String) async throws {}
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
        public var mediaCacheDirectory: URL
        public var downloadMedia: @Sendable (URL) async throws -> Data

        public init(
            sendTimeout: Duration = .seconds(15),
            now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
            mediaCacheDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Connor/IMMedia", isDirectory: true),
            downloadMedia: @escaping @Sendable (URL) async throws -> Data = {
                let (data, response) = try await URLSession.shared.data(from: $0)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return data
            }
        ) {
            self.sendTimeout = sendTimeout
            self.now = now
            self.mediaCacheDirectory = mediaCacheDirectory
            self.downloadMedia = downloadMedia
        }
    }

    private let store: any ImStore
    private let service: any ImBackendServicing
    private let sendFrame: @Sendable (String) async -> Bool
    private let currentIdentity: @Sendable () -> ImSelfIdentity?
    private let onRealtimeEvent: @Sendable (ImRealtimeEvent) async -> Void
    private let configuration: Configuration
    private var knownGroupIDs: Set<String> = []

    private struct PendingSend {
        let tempId: String
        let conversationId: String
        var timeoutTask: Task<Void, Never>?
    }

    private var pendingSends: [PendingSend] = []
    private var latestReconciliationTasks: [String: Task<Bool, Error>] = [:]
    private var refreshAllTask: Task<Bool, Never>?
    private var refreshRetryTask: Task<Void, Never>?

    /// Currently opened conversation: its incoming messages neither count as unread
    /// nor stay unacknowledged (auto read receipt).
    public private(set) var activeConversationId: String?

    public init(
        store: any ImStore,
        service: any ImBackendServicing,
        sendFrame: @escaping @Sendable (String) async -> Bool,
        currentIdentity: @escaping @Sendable () -> ImSelfIdentity?,
        onRealtimeEvent: @escaping @Sendable (ImRealtimeEvent) async -> Void = { _ in },
        configuration: Configuration = Configuration()
    ) {
        self.store = store
        self.service = service
        self.sendFrame = sendFrame
        self.currentIdentity = currentIdentity
        self.onRealtimeEvent = onRealtimeEvent
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
        if let activeConversationId {
            _ = try? await reconcileLatestMessages(conversationId: activeConversationId)
        }
    }

    /// Sign-out / account switch stops account-bound work while preserving local
    /// conversations, messages, friends, requests, and forwarding aliases.
    public func handleSignOut() async {
        let pendingIDs = pendingSends.map(\.tempId)
        for pending in pendingSends { pending.timeoutTask?.cancel() }
        pendingSends.removeAll()
        let reconciliationTasks = Array(latestReconciliationTasks.values)
        for task in reconciliationTasks { task.cancel() }
        latestReconciliationTasks.removeAll()
        let activeRefreshTask = refreshAllTask
        activeRefreshTask?.cancel()
        refreshAllTask = nil
        let activeRetryTask = refreshRetryTask
        activeRetryTask?.cancel()
        refreshRetryTask = nil
        for task in reconciliationTasks { _ = try? await task.value }
        _ = await activeRefreshTask?.value
        await activeRetryTask?.value
        for id in pendingIDs {
            try? await store.updateMessageStatus(id: id, status: .failed)
        }
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

    public func sendMediaMessage(
        conversationId: String,
        fileURL: URL,
        messageType: ImMessageType,
        metadata: ImMediaMetadata
    ) async throws {
        guard messageType.isMedia else { return }
        guard let conversation = try await store.conversation(id: conversationId) else { return }
        try Self.validateMedia(fileURL: fileURL, messageType: messageType)

        let tempId = ImMessage.makeTemporaryID()
        let localURL = try cacheLocalFile(fileURL, messageId: tempId, messageType: messageType)
        var localMetadata = metadata
        localMetadata.localPath = localURL.path
        let upload = try await service.uploadMedia(fileURL: localURL, messageType: messageType)
        localMetadata.objectName = upload.objectName

        var remoteMetadata = metadata
        remoteMetadata.objectName = upload.objectName
        remoteMetadata.localPath = nil
        remoteMetadata.localThumbnailPath = nil
        let remoteExtra = Self.jsonObject(from: remoteMetadata)
        let localExtra = Self.jsonString(from: localMetadata)
        let payload: [String: Any]
        let frameType: String
        switch conversation.kind {
        case .peer:
            guard let peerId = conversation.peerUserId else { return }
            frameType = "chat_send"
            payload = [
                "receiver_id": peerId,
                "message_type": messageType == .file ? ImMessageType.text.rawValue : messageType.rawValue,
                "content": upload.downloadURL.isEmpty ? upload.objectName : upload.downloadURL,
                "extra": remoteExtra,
            ]
        case .group:
            guard let groupId = conversation.groupId else { return }
            frameType = "group_send"
            payload = [
                "group_id": groupId,
                "message_type": messageType == .file ? ImMessageType.text.rawValue : messageType.rawValue,
                "content": upload.downloadURL.isEmpty ? upload.objectName : upload.downloadURL,
                "extra": remoteExtra,
            ]
        }
        try await sendOptimistic(
            conversationId: conversationId,
            content: upload.downloadURL.isEmpty ? upload.objectName : upload.downloadURL,
            messageType: messageType.rawValue,
            frame: Self.encodeFrame(type: frameType, payload: payload),
            tempId: tempId,
            extraJson: localExtra,
            preview: messageType.conversationPreview
        )
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
                "extra": Self.remoteExtraObject(message.extraJson),
            ])
        case .peer:
            guard let peerId = conversation.peerUserId else { return }
            frame = Self.encodeFrame(type: "chat_send", payload: [
                "receiver_id": peerId,
                "message_type": message.messageType,
                "content": message.content,
                "extra": Self.remoteExtraObject(message.extraJson),
            ])
        }
        try await store.updateMessageStatus(id: message.id, status: .sending)
        await dispatchPending(tempId: message.id, conversationId: message.conversationId, frame: frame)
    }

    private func sendOptimistic(
        conversationId: String,
        content: String,
        messageType: String,
        frame: String,
        tempId: String = ImMessage.makeTemporaryID(),
        extraJson: String = "{}",
        preview: String? = nil
    ) async throws {
        guard let selfUser = currentIdentity() else { throw ConnorBackendAPIError.unauthorized }
        let now = configuration.now()
        _ = try await store.upsertMessage(ImMessage(
            id: tempId,
            conversationId: conversationId,
            senderId: selfUser.id,
            senderName: selfUser.displayName,
            messageType: messageType,
            content: content,
            status: .sending,
            createdAt: now,
            extraJson: extraJson
        ))
        try await touchConversation(
            id: conversationId,
            preview: preview ?? String(content.prefix(100)),
            at: now,
            unreadDelta: 0
        )
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
        case "friend_request_received":
            let existingPendingIDs = await pendingIncomingRequestIDs()
            try? await refreshFriendData()
            guard let selfId = selfUserId() else { break }
            let requests = (try? await store.loadFriendRequests()) ?? []
            for request in requests where request.receiverId == selfId
                && request.status == "pending"
                && !existingPendingIDs.contains(request.id) {
                await onRealtimeEvent(.incomingFriendRequest(request))
            }
        case "friend_request_accepted", "friend_request_rejected":
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
        if let message = try? await store.message(id: serverId) {
            await cacheMediaIfNeeded(message)
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
        guard await isKnownGroup(groupId) else { return }
        guard let conversationId = try? await ensureGroupConversation(groupId: groupId) else { return }
        let sentAt = Self.int64Value(payload["sent_at"]) ?? configuration.now()
        let senderNickname = payload["sender_nickname"] as? String ?? ""
        let senderUsername = payload["sender_username"] as? String ?? ""
        await insertIncoming(
            ImMessage(
                id: messageId,
                conversationId: conversationId,
                senderId: senderId,
                senderName: senderNickname.isEmpty ? senderUsername : senderNickname,
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
        if var existing = try? await store.message(id: message.id) {
            if existing.senderName.isEmpty, !message.senderName.isEmpty {
                existing.senderName = message.senderName
                existing.senderAvatar = message.senderAvatar
                _ = try? await store.upsertMessage(existing)
            }
            return
        }
        guard let storedMessage = try? await store.upsertMessage(message) else { return }
        let active = storedMessage.conversationId == activeConversationId
        try? await touchConversation(
            id: storedMessage.conversationId,
            preview: Self.preview(for: storedMessage),
            at: storedMessage.createdAt,
            unreadDelta: (countUnread && !active) ? 1 : 0
        )
        if active && countUnread {
            await markConversationRead(storedMessage.conversationId)
        }
        if countUnread, let conversation = try? await store.conversation(id: storedMessage.conversationId) {
            await onRealtimeEvent(.incomingMessage(message: storedMessage, conversation: conversation))
        }
        await cacheMediaIfNeeded(storedMessage)
    }

    private func pendingIncomingRequestIDs() async -> Set<Int64> {
        guard let selfId = selfUserId() else { return [] }
        let requests = (try? await store.loadFriendRequests()) ?? []
        return Set(requests.lazy.filter { $0.receiverId == selfId && $0.status == "pending" }.map(\.id))
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
                lastMessageAt: 0,
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
                lastMessageAt: 0,
                updatedAt: now
            ))
        }
        return id
    }

    private func touchConversation(id: String, preview: String, at: Int64, unreadDelta: Int) async throws {
        guard var existing = try await store.conversation(id: id) else { return }
        if at >= existing.lastMessageAt {
            existing.lastMessagePreview = preview
            existing.lastMessageAt = at
        }
        existing.unreadCount += unreadDelta
        existing.updatedAt = configuration.now()
        try await store.upsertConversation(existing)
    }

    /// Opening a conversation clears local unread state and reports the matching
    /// private/group read cursor to the server.
    public func markConversationRead(_ conversationId: String) async {
        try? await store.clearUnread(conversationId: conversationId, now: configuration.now())
        guard let conversation = try? await store.conversation(id: conversationId) else { return }
        switch conversation.kind {
        case .peer:
            guard let peerId = conversation.peerUserId else { return }
            try? await store.markSenderMessagesRead(conversationId: conversationId, senderId: peerId)
            _ = try? await service.markRead(peerId: peerId, messageIds: [])
        case .group:
            guard let groupId = conversation.groupId else { return }
            let selfID = currentIdentity()?.id
            let senderIDs = Set(((try? await store.messages(conversationId: conversationId)) ?? []).map(\.senderId))
            for senderID in senderIDs where senderID != selfID {
                try? await store.markSenderMessagesRead(conversationId: conversationId, senderId: senderID)
            }
            try? await service.markGroupRead(groupId: groupId)
        }
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
        let succeeded = await coalescedRefreshAll()
        if succeeded {
            refreshRetryTask?.cancel()
            refreshRetryTask = nil
        } else {
            scheduleRefreshRetry()
        }
    }

    private func coalescedRefreshAll() async -> Bool {
        if let refreshAllTask { return await refreshAllTask.value }
        let task = Task { await self.performRefreshAll() }
        refreshAllTask = task
        let result = await task.value
        refreshAllTask = nil
        return result
    }

    private func performRefreshAll() async -> Bool {
        guard currentIdentity() != nil, !Task.isCancelled else { return true }
        var succeeded = true
        do { try await refreshFriendData() } catch { succeeded = false }
        do { try await refreshConversations() } catch { succeeded = false }
        do { try await refreshGroups() } catch { succeeded = false }
        return succeeded
    }

    private func scheduleRefreshRetry() {
        guard refreshRetryTask == nil, currentIdentity() != nil else { return }
        refreshRetryTask = Task { [weak self] in
            var delay = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                if await self.coalescedRefreshAll() {
                    await self.finishRefreshRetry()
                    return
                }
                delay = min(delay * 2, 30)
            }
        }
    }

    private func finishRefreshRetry() {
        refreshRetryTask = nil
    }

    private func refreshConversations() async throws {
        let remote = try await service.conversations()
        for dto in remote {
            let id = try await ensurePeerConversation(peerId: dto.peerId)
            guard var existing = try await store.conversation(id: id) else { continue }
            existing.lastMessagePreview = Self.preview(type: dto.lastMessageType, content: dto.lastMessageContent)
            existing.lastMessageAt = max(existing.lastMessageAt, Self.epochMilliseconds(fromRFC3339: dto.lastMessageTime))
            existing.unreadCount = dto.unreadCount
            existing.updatedAt = configuration.now()
            try await store.upsertConversation(existing)
        }
    }

    private func refreshGroups() async throws {
        let groups = try await service.myGroups()
        knownGroupIDs = Set(groups.map(\.groupId))
        for group in groups {
            let id = try await ensureGroupConversation(groupId: group.groupId, title: group.name)
            guard var existing = try await store.conversation(id: id) else { continue }
            existing.participantName = group.name
            if !existing.titleCustomized {
                existing.title = group.name
            }
            existing.avatar = group.avatar
            existing.lastMessagePreview = Self.preview(type: group.lastMessageType, content: group.lastMessageContent)
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
        // 收敛本地好友表：删除服务端已不存在的好友，避免“幽灵好友”残留在搜索/人际关系里。
        try await store.pruneFriends(keepUserIds: remote.map(\.friendId))
        for friend in local {
            let conversationID = ImConversation.peerConversationID(peerUserId: friend.userId)
            guard var conversation = try await store.conversation(id: conversationID) else { continue }
            conversation.participantName = friend.displayName
            conversation.avatar = friend.avatar
            if !conversation.titleCustomized {
                conversation.title = friend.displayName
            }
            conversation.updatedAt = now
            try await store.upsertConversation(conversation)
        }
        let received = try await service.receivedFriendRequests()
        let sent = try await service.sentFriendRequests()
        let requests = (received + sent).map(Self.friendRequest(from:))
        try await store.upsertFriendRequests(requests)
    }

    // MARK: - History paging

    /// Fetches the newest server page without a cursor. This closes gaps where the
    /// conversation summary advanced while the local message cache missed a push.
    public func loadLatestMessages(conversationId: String, limit: Int = 20) async throws -> Bool {
        guard let conversation = try await store.conversation(id: conversationId) else { return false }
        let selfUser = currentIdentity()
        switch conversation.kind {
        case .group:
            guard let groupId = conversation.groupId else { return false }
            let page = try await service.groupMessages(groupId: groupId, beforeId: nil, limit: limit)
            try await storeGroupHistory(page.messages, conversationId: conversationId, selfUser: selfUser)
            return page.hasMore
        case .peer:
            guard let peerId = conversation.peerUserId else { return false }
            let page = try await service.chatHistory(peerId: peerId, beforeId: nil, limit: limit)
            try await storePeerHistory(page.messages, conversationId: conversationId, selfUser: selfUser)
            return page.hasMore
        }
    }

    /// Reconciles a missed-offline gap from the newest server page backwards until
    /// it overlaps the pre-existing local cache. An empty local cache intentionally
    /// fetches only the newest page; older history remains user-paged.
    public func reconcileLatestMessages(conversationId: String, limit: Int = 50) async throws -> Bool {
        if let task = latestReconciliationTasks[conversationId] {
            return try await task.value
        }
        let task = Task {
            try await self.performLatestReconciliation(conversationId: conversationId, limit: limit)
        }
        latestReconciliationTasks[conversationId] = task
        do {
            let result = try await task.value
            latestReconciliationTasks[conversationId] = nil
            return result
        } catch {
            latestReconciliationTasks[conversationId] = nil
            throw error
        }
    }

    private func performLatestReconciliation(conversationId: String, limit: Int) async throws -> Bool {
        guard let conversation = try await store.conversation(id: conversationId) else { return false }
        let baselineIDs = Set(try await store.messages(conversationId: conversationId)
            .filter { !$0.hasTemporaryID }
            .map(\.id))
        let selfUser = currentIdentity()
        var beforeId: String?
        var usedCursors: Set<String> = []

        while !Task.isCancelled {
            switch conversation.kind {
            case .peer:
                guard let peerId = conversation.peerUserId else { return false }
                let page = try await service.chatHistory(peerId: peerId, beforeId: beforeId, limit: limit)
                try Task.checkCancellation()
                let overlap = page.messages.contains { baselineIDs.contains($0.messageId) }
                try await storePeerHistory(page.messages, conversationId: conversationId, selfUser: selfUser)
                if baselineIDs.isEmpty || overlap || !page.hasMore { return page.hasMore }
                guard let cursor = oldestPeerMessageID(page.messages), usedCursors.insert(cursor).inserted else {
                    return page.hasMore
                }
                beforeId = cursor
            case .group:
                guard let groupId = conversation.groupId else { return false }
                let page = try await service.groupMessages(groupId: groupId, beforeId: beforeId, limit: limit)
                try Task.checkCancellation()
                let overlap = page.messages.contains { baselineIDs.contains($0.messageId) }
                try await storeGroupHistory(page.messages, conversationId: conversationId, selfUser: selfUser)
                if baselineIDs.isEmpty || overlap || !page.hasMore { return page.hasMore }
                guard let cursor = oldestGroupMessageID(page.messages), usedCursors.insert(cursor).inserted else {
                    return page.hasMore
                }
                beforeId = cursor
            }
        }
        throw CancellationError()
    }

    private func oldestPeerMessageID(_ messages: [ImChatMessageDTO]) -> String? {
        messages.min {
            Self.epochMilliseconds(fromRFC3339: $0.sentAt) < Self.epochMilliseconds(fromRFC3339: $1.sentAt)
        }?.messageId
    }

    private func oldestGroupMessageID(_ messages: [ImGroupMessageDTO]) -> String? {
        messages.min {
            Self.epochMilliseconds(fromRFC3339: $0.sentAt) < Self.epochMilliseconds(fromRFC3339: $1.sentAt)
        }?.messageId
    }

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
            try await storeGroupHistory(page.messages, conversationId: conversationId, selfUser: selfUser)
            return page.hasMore
        case .peer:
            guard let peerId = conversation.peerUserId else { return false }
            let page = try await service.chatHistory(peerId: peerId, beforeId: beforeId, limit: limit)
            try await storePeerHistory(page.messages, conversationId: conversationId, selfUser: selfUser)
            return page.hasMore
        }
    }

    private func storeGroupHistory(
        _ messages: [ImGroupMessageDTO],
        conversationId: String,
        selfUser: ImSelfIdentity?
    ) async throws {
        var pending: [ImMessage] = []
        pending.reserveCapacity(messages.count)
        for dto in messages {
            let resolvedName: String
            if let serverName = dto.senderDisplayName.nonEmpty {
                resolvedName = serverName
            } else {
                resolvedName = await senderName(senderId: dto.senderId, selfUser: selfUser)
            }
            if var existing = try? await store.message(id: dto.messageId) {
                if existing.senderName.isEmpty, !resolvedName.isEmpty {
                    existing.senderName = resolvedName
                    existing.senderAvatar = dto.senderAvatar
                    pending.append(existing)
                }
                continue
            }
            pending.append(ImMessage(
                id: dto.messageId,
                conversationId: conversationId,
                senderId: dto.senderId,
                senderName: resolvedName,
                senderAvatar: dto.senderAvatar,
                messageType: dto.messageType,
                content: dto.content,
                status: .sent,
                createdAt: Self.epochMilliseconds(fromRFC3339: dto.sentAt),
                extraJson: dto.extra
            ))
        }
        for stored in try await store.upsertMessages(pending, conversationId: conversationId) {
            await cacheMediaIfNeeded(stored)
        }
        if let latest = messages.max(by: {
            Self.epochMilliseconds(fromRFC3339: $0.sentAt) < Self.epochMilliseconds(fromRFC3339: $1.sentAt)
        }) {
            try await touchConversation(
                id: conversationId,
                preview: Self.preview(type: latest.messageType, content: latest.content),
                at: Self.epochMilliseconds(fromRFC3339: latest.sentAt),
                unreadDelta: 0
            )
        }
    }

    private func storePeerHistory(
        _ messages: [ImChatMessageDTO],
        conversationId: String,
        selfUser: ImSelfIdentity?
    ) async throws {
        var pending: [ImMessage] = []
        pending.reserveCapacity(messages.count)
        for dto in messages {
            if (try? await store.message(id: dto.messageId)) != nil { continue }
            pending.append(ImMessage(
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
        for stored in try await store.upsertMessages(pending, conversationId: conversationId) {
            await cacheMediaIfNeeded(stored)
        }
        if let latest = messages.max(by: {
            Self.epochMilliseconds(fromRFC3339: $0.sentAt) < Self.epochMilliseconds(fromRFC3339: $1.sentAt)
        }) {
            try await touchConversation(
                id: conversationId,
                preview: Self.preview(type: latest.messageType, content: latest.content),
                at: Self.epochMilliseconds(fromRFC3339: latest.sentAt),
                unreadDelta: 0
            )
        }
    }

    private func senderName(senderId: Int64, selfUser: ImSelfIdentity?) async -> String {
        if senderId == selfUser?.id { return selfUser?.displayName ?? "" }
        guard let friend = try? await store.friend(userId: senderId) else { return "" }
        return friend.nickname.isEmpty ? friend.username : friend.nickname
    }

    // MARK: - Media cache lifecycle

    private func cacheMediaIfNeeded(_ message: ImMessage) async {
        var metadata = message.mediaMetadata ?? ImMediaMetadata()
        let messageType: ImMessageType
        if metadata.attachmentKind == "file" {
            messageType = .file
        } else if let type = message.type, type.isMedia {
            messageType = type
        } else {
            return
        }
        if let localPath = metadata.localPath,
           FileManager.default.fileExists(atPath: localPath) {
            await acknowledgeMediaCached(message)
            return
        }
        guard !metadata.expired, let remoteURL = URL(string: message.content), remoteURL.scheme != nil else { return }
        do {
            let data = try await configuration.downloadMedia(remoteURL)
            guard !data.isEmpty else { return }
            let localURL = try mediaCacheURL(
                messageId: message.id,
                messageType: messageType,
                preferredExtension: Self.preferredExtension(message: message, metadata: metadata)
            )
            try data.write(to: localURL, options: .atomic)
            metadata.localPath = localURL.path
            var updated = message
            updated.extraJson = Self.jsonString(from: metadata)
            _ = try await store.upsertMessage(updated)
            await acknowledgeMediaCached(updated)
        } catch {
            // Signed download URLs are short-lived. A later history refresh can retry.
        }
    }

    private func acknowledgeMediaCached(_ message: ImMessage) async {
        guard !message.hasTemporaryID,
              let conversation = try? await store.conversation(id: message.conversationId) else { return }
        switch conversation.kind {
        case .peer:
            try? await service.markPrivateMediaCached(messageId: message.id)
        case .group:
            guard let groupId = conversation.groupId else { return }
            try? await service.markGroupMediaCached(groupId: groupId, messageId: message.id)
        }
    }

    private func cacheLocalFile(_ source: URL, messageId: String, messageType: ImMessageType) throws -> URL {
        let destination = try mediaCacheURL(
            messageId: messageId,
            messageType: messageType,
            preferredExtension: source.pathExtension
        )
        if source.standardizedFileURL != destination.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return destination
    }

    private func mediaCacheURL(
        messageId: String,
        messageType: ImMessageType,
        preferredExtension: String
    ) throws -> URL {
        let directory = configuration.mediaCacheDirectory.appendingPathComponent(messageType.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitizedID = messageId.replacingOccurrences(of: "/", with: "_")
        let ext = preferredExtension.isEmpty ? Self.defaultExtension(for: messageType) : preferredExtension
        return directory.appendingPathComponent(sanitizedID).appendingPathExtension(ext)
    }

    private static func validateMedia(fileURL: URL, messageType: ImMessageType) throws {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let limits: [ImMessageType: Int] = [.image: 25 * 1_024 * 1_024, .video: 25 * 1_024 * 1_024, .audio: 25 * 1_024 * 1_024, .file: 25 * 1_024 * 1_024]
        guard size <= (limits[messageType] ?? 0) else { throw CocoaError(.fileWriteOutOfSpace) }
        let allowed: [ImMessageType: Set<String>] = [
            .image: ["jpg", "jpeg", "png", "gif", "webp"],
            .video: ["mp4", "mov", "avi", "mkv"],
            .audio: ["mp3", "m4a", "wav", "ogg"],
            .file: ["pdf", "txt", "md", "csv", "json", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp"],
        ]
        guard allowed[messageType]?.contains(fileURL.pathExtension.lowercased()) == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    private static func preferredExtension(message: ImMessage, metadata: ImMediaMetadata) -> String {
        if let fileName = metadata.fileName, !URL(fileURLWithPath: fileName).pathExtension.isEmpty {
            return URL(fileURLWithPath: fileName).pathExtension
        }
        if let url = URL(string: message.content), !url.pathExtension.isEmpty { return url.pathExtension }
        return defaultExtension(for: message.type ?? .image)
    }

    private static func defaultExtension(for type: ImMessageType) -> String {
        switch type {
        case .image: return "jpg"
        case .video: return "mp4"
        case .audio: return "m4a"
        case .file: return "bin"
        case .text, .system: return "bin"
        }
    }

    // MARK: - Friends / contact list (bridge to person profiles)

    public func sendFriendRequest(username: String, message: String = "") async throws {
        _ = try await service.sendFriendRequest(username: username, message: message)
        try? await refreshFriendData()
    }

    public func acceptFriendRequest(requestId: Int64) async throws {
        let cachedRequest = try? await store.loadFriendRequests().first { $0.id == requestId }
        let accepted = try await service.acceptFriendRequest(requestId: requestId)
        try? await refreshFriendData()
        try await store.upsertFriendRequests([Self.friendRequest(from: accepted)])
        try await cacheAcceptedFriendIfNeeded(accepted, cachedRequest: cachedRequest)
    }

    public func rejectFriendRequest(requestId: Int64) async throws {
        let rejected = try await service.rejectFriendRequest(requestId: requestId)
        try? await refreshFriendData()
        try await store.upsertFriendRequests([Self.friendRequest(from: rejected)])
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

    private func cacheAcceptedFriendIfNeeded(
        _ accepted: ImFriendRequestDTO,
        cachedRequest: ImFriendRequest?
    ) async throws {
        guard let selfID = currentIdentity()?.id else { return }
        let friend: ImFriend
        if accepted.receiverId == selfID {
            friend = ImFriend(
                userId: accepted.senderId,
                username: accepted.senderUsername.nonEmpty ?? cachedRequest?.senderUsername ?? "",
                nickname: accepted.senderNickname.nonEmpty ?? cachedRequest?.senderNickname ?? "",
                email: accepted.senderEmail,
                avatar: accepted.senderAvatar.nonEmpty ?? cachedRequest?.senderAvatar ?? "",
                updatedAt: configuration.now()
            )
        } else if accepted.senderId == selfID {
            friend = ImFriend(
                userId: accepted.receiverId,
                username: accepted.receiverUsername.nonEmpty ?? cachedRequest?.receiverUsername ?? "",
                nickname: accepted.receiverNickname.nonEmpty ?? cachedRequest?.receiverNickname ?? "",
                email: accepted.receiverEmail,
                avatar: accepted.receiverAvatar,
                updatedAt: configuration.now()
            )
        } else {
            return
        }
        guard friend.userId > 0, try await store.friend(userId: friend.userId) == nil else { return }
        try await store.upsertFriends([friend])
    }

    private static func friendRequest(from dto: ImFriendRequestDTO) -> ImFriendRequest {
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
            createdAt: epochMilliseconds(fromRFC3339: dto.createdAt)
        )
    }

    // MARK: - Group management

    @discardableResult
    public func createGroup(name: String, description: String = "", memberIds: [Int64] = []) async throws -> ImGroupDTO {
        let group = try await service.createGroup(name: name, description: description, memberIds: memberIds)
        knownGroupIDs.insert(group.groupId)
        _ = try await ensureGroupConversation(groupId: group.groupId, title: group.name)
        return group
    }

    public func groupDetail(groupId: String) async throws -> ImGroupDTO {
        let group = try await service.groupDetail(groupId: groupId)
        knownGroupIDs.insert(groupId)
        return group
    }

    public func groupMembers(groupId: String) async throws -> [ImGroupMemberDTO] {
        _ = try await groupDetail(groupId: groupId)
        return try await service.groupMembers(groupId: groupId)
    }

    public func inviteGroupMember(groupId: String, userId: Int64) async throws {
        _ = try await groupDetail(groupId: groupId)
        try await service.inviteGroupMember(groupId: groupId, userId: userId)
    }

    public func removeGroupMember(groupId: String, userId: Int64) async throws {
        _ = try await groupDetail(groupId: groupId)
        try await service.removeGroupMember(groupId: groupId, userId: userId)
    }

    public func leaveGroup(groupId: String) async throws {
        _ = try await groupDetail(groupId: groupId)
        try await service.leaveGroup(groupId: groupId)
        knownGroupIDs.remove(groupId)
        try await store.deleteConversation(id: ImConversation.groupConversationID(groupId: groupId))
    }

    // MARK: - Helpers

    private static func encodeFrame(type: String, payload: [String: Any]) -> String {
        let object: [String: Any] = ["type": type, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func isKnownGroup(_ groupId: String) async -> Bool {
        if knownGroupIDs.contains(groupId) { return true }
        guard (try? await service.groupDetail(groupId: groupId)) != nil else {
            return false
        }
        knownGroupIDs.insert(groupId)
        return true
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

    private static func jsonString<T: Encodable>(from value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func jsonObject<T: Encodable>(from value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func remoteExtraObject(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        object.removeValue(forKey: "localPath")
        object.removeValue(forKey: "localThumbnailPath")
        return object
    }

    private static func preview(for message: ImMessage) -> String {
        preview(type: message.messageType, content: message.content)
    }

    private static func preview(type rawType: String, content: String) -> String {
        if let bundle = ForwardedChatBundleCodec.decode(content) { return "[聊天记录] \(bundle.title)" }
        let normalizedType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let type = normalizedType.isEmpty ? ImMessageType.text : ImMessageType(rawValue: normalizedType)
        guard let type else { return "[不支持的消息]" }
        return type == .text ? String(content.prefix(100)) : type.conversationPreview
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
        if let milliseconds = Int64(value) { return milliseconds }
        let date = rfc3339.date(from: value) ?? rfc3339Fractional.date(from: value)
        guard let date else { return 0 }
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
