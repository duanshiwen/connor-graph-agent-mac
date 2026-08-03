import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("IM Message Center Tests")
struct ImMessageCenterTests {
    @Test func sendChatMessageInsertsOptimisticallyAndSendsFrame() async throws {
        let fixture = try makeFixture()
        try await fixture.center.sendChatMessage(peerId: 9, content: "你好")

        let conversationId = ImConversation.peerConversationID(peerUserId: 9)
        let messages = try await fixture.store.messages(conversationId: conversationId)
        #expect(messages.count == 1)
        let message = try #require(messages.first)
        #expect(message.hasTemporaryID)
        #expect(message.status == .sending)
        #expect(message.senderId == 1)
        #expect(message.senderName == "康纳")

        let conversation = try #require(try await fixture.store.conversation(id: conversationId))
        #expect(conversation.lastMessagePreview == "你好")
        #expect(conversation.unreadCount == 0)

        let frame = try #require(fixture.frames.sentFrames.first)
        let root = try #require(try JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any])
        #expect(root["type"] as? String == "chat_send")
        let payload = try #require(root["payload"] as? [String: Any])
        #expect(payload["receiver_id"] as? Int == 9)
        #expect(payload["message_type"] as? String == "text")
        #expect(payload["content"] as? String == "你好")
    }

    @Test func typelessAckReplacesTempIdInPlace() async throws {
        let fixture = try makeFixture()
        try await fixture.center.sendChatMessage(peerId: 9, content: "hi")
        let conversationId = ImConversation.peerConversationID(peerUserId: 9)
        let optimistic = try #require(try await fixture.store.messages(conversationId: conversationId).first)

        await fixture.center.handleFrame(type: nil, text: #"{"messageId":"srv-1","senderId":1,"content":"hi"}"#)

        let messages = try await fixture.store.messages(conversationId: conversationId)
        #expect(messages.count == 1)
        let acked = try #require(messages.first)
        #expect(acked.id == "srv-1")
        #expect(acked.status == .sent)
        #expect(acked.seq == optimistic.seq)
    }

    @Test func errorFrameFailsOldestPendingSend() async throws {
        let fixture = try makeFixture()
        try await fixture.center.sendChatMessage(peerId: 9, content: "hi")
        let conversationId = ImConversation.peerConversationID(peerUserId: 9)
        let tempId = try #require(try await fixture.store.messages(conversationId: conversationId).first).id

        await fixture.center.handleFrame(type: "error", text: #"{"type":"error","payload":{"message":"forbidden"}}"#)

        let message = try #require(try await fixture.store.message(id: tempId))
        #expect(message.status == .failed)
    }

    @Test func rejectedUplinkFailsImmediately() async throws {
        let fixture = try makeFixture()
        fixture.frames.accept = false
        try await fixture.center.sendChatMessage(peerId: 9, content: "hi")

        let conversationId = ImConversation.peerConversationID(peerUserId: 9)
        let message = try #require(try await fixture.store.messages(conversationId: conversationId).first)
        #expect(message.status == .failed)
    }

    @Test func missingAckTimesOutIntoFailed() async throws {
        let fixture = try makeFixture(sendTimeout: .milliseconds(20))
        try await fixture.center.sendChatMessage(peerId: 9, content: "hi")
        let conversationId = ImConversation.peerConversationID(peerUserId: 9)
        let tempId = try #require(try await fixture.store.messages(conversationId: conversationId).first).id

        // Generous deadline: the 20ms ack timer can starve under full-suite parallel load.
        let failed = try await waitUntil(timeout: .seconds(10)) {
            try await fixture.store.message(id: tempId)?.status == .failed
        }
        #expect(failed)
    }

    @Test func retryReusesTempIdAndResends() async throws {
        let fixture = try makeFixture()
        fixture.frames.accept = false
        try await fixture.center.sendChatMessage(peerId: 9, content: "重发我")
        let conversationId = ImConversation.peerConversationID(peerUserId: 9)
        let tempId = try #require(try await fixture.store.messages(conversationId: conversationId).first).id

        fixture.frames.accept = true
        try await fixture.center.retryMessage(messageId: tempId)

        let retried = try #require(try await fixture.store.message(id: tempId))
        #expect(retried.status == .sending)
        #expect(fixture.frames.sentFrames.count == 2)

        await fixture.center.handleFrame(type: nil, text: #"{"messageId":"srv-2"}"#)
        #expect(try await fixture.store.message(id: "srv-2")?.status == .sent)
    }

    @Test func chatReceiveCreatesConversationAndCountsUnread() async throws {
        let fixture = try makeFixture()

        await fixture.center.handleFrame(type: "chat_receive", text: """
            {"type":"chat_receive","payload":{"sender_id":9,"message_id":"m1","sender_username":"alice",
            "content":"最近怎么样","message_type":"text","sent_at":1722400000000,"extra":{"k":"v"}}}
            """)

        let conversationId = ImConversation.peerConversationID(peerUserId: 9)
        let conversation = try #require(try await fixture.store.conversation(id: conversationId))
        #expect(conversation.title == "alice")
        #expect(conversation.unreadCount == 1)
        #expect(conversation.lastMessagePreview == "最近怎么样")

        let message = try #require(try await fixture.store.message(id: "m1"))
        #expect(message.status == .delivered)
        #expect(message.createdAt == 1722400000000)
        #expect(message.extraJson == #"{"k":"v"}"#)

        // Duplicate push with the same message id is a no-op.
        await fixture.center.handleFrame(type: "chat_receive", text: """
            {"type":"chat_receive","payload":{"sender_id":9,"message_id":"m1","content":"最近怎么样"}}
            """)
        #expect(try await fixture.store.conversation(id: conversationId)?.unreadCount == 1)
    }

    @Test func activeConversationSuppressesUnreadAndAutoReads() async throws {
        let fixture = try makeFixture()
        let conversationId = try await fixture.center.openPeerConversation(peerId: 9)
        await fixture.center.setActiveConversation(conversationId)

        await fixture.center.handleFrame(type: "chat_receive", text: """
            {"type":"chat_receive","payload":{"sender_id":9,"message_id":"m1","content":"在吗"}}
            """)

        #expect(try await fixture.store.conversation(id: conversationId)?.unreadCount == 0)
        #expect(fixture.service.markReadPeerIds == [9])
    }

    @Test func groupEchoBeforeAckDeduplicatesByServerId() async throws {
        let fixture = try makeFixture()
        try await fixture.center.sendGroupMessage(groupId: "g1", content: "大家好")
        let conversationId = ImConversation.groupConversationID(groupId: "g1")

        // Self echo arrives before the typeless reply: stored as SENT, no unread.
        await fixture.center.handleFrame(type: "group_receive", text: """
            {"type":"group_receive","payload":{"group_id":"g1","message_id":"srv-9","sender_id":1,
            "sender_username":"connor","content":"大家好","sent_at":1722400000000}}
            """)
        #expect(try await fixture.store.message(id: "srv-9")?.status == .sent)
        #expect(try await fixture.store.conversation(id: conversationId)?.unreadCount == 0)

        // The late reply pairs the pending send and drops the optimistic temp row.
        await fixture.center.handleFrame(type: nil, text: #"{"messageId":"srv-9"}"#)
        let messages = try await fixture.store.messages(conversationId: conversationId)
        #expect(messages.count == 1)
        #expect(messages.first?.id == "srv-9")
    }

    @Test func groupReceiveFromOthersCountsUnread() async throws {
        let fixture = try makeFixture()

        await fixture.center.handleFrame(type: "group_receive", text: """
            {"type":"group_receive","payload":{"group_id":"g1","message_id":"gm1","sender_id":7,
            "sender_username":"bob","sender_avatar":"a.png","content":"午饭吃啥"}}
            """)

        let conversationId = ImConversation.groupConversationID(groupId: "g1")
        #expect(try await fixture.store.conversation(id: conversationId)?.unreadCount == 1)
        let message = try #require(try await fixture.store.message(id: "gm1"))
        #expect(message.status == .delivered)
        #expect(message.senderAvatar == "a.png")
    }

    @Test func friendDeletedFrameRemovesLocalFriend() async throws {
        let fixture = try makeFixture()
        try await fixture.store.upsertFriends([ImFriend(userId: 9, username: "alice")])

        await fixture.center.handleFrame(type: "friend_deleted", text: #"{"type":"friend_deleted","payload":{"user_id":9}}"#)

        #expect(try await fixture.store.friend(userId: 9) == nil)
    }

    @Test func acceptingFriendRequestCachesFriendBeforeRemoteListConverges() async throws {
        let fixture = try makeFixture(selfId: 2)
        try await fixture.store.upsertFriendRequests([ImFriendRequest(
            id: 77,
            senderId: 1,
            receiverId: 2,
            senderUsername: "alice",
            senderNickname: "爱丽丝",
            senderAvatar: "https://example.com/alice.png"
        )])
        fixture.service.friendsResult = []

        try await fixture.center.acceptFriendRequest(requestId: 77)

        let friend = try #require(try await fixture.store.friend(userId: 1))
        #expect(friend.username == "alice")
        #expect(friend.nickname == "爱丽丝")
        #expect(friend.avatar == "https://example.com/alice.png")
    }

    @Test func refreshAllBackfillsFriendsConversationsAndGroups() async throws {
        let fixture = try makeFixture()
        // Pre-existing bridge + a stale friend that the server no longer returns.
        try await fixture.store.upsertFriends([
            ImFriend(userId: 9, username: "alice", personProfileID: "person-1"),
            ImFriend(userId: 99, username: "stale"),
        ])
        fixture.service.friendsResult = try decodeDTO(#"[{"ID":1,"userId":1,"friendId":9,"username":"alice","nickname":"艾丽"}]"#)
        fixture.service.receivedRequestsResult = try decodeDTO(#"[{"ID":5,"senderId":9,"receiverId":1,"message":"加好友","createdAt":"2026-07-30T10:00:00Z"}]"#)
        fixture.service.conversationsResult = try decodeDTO(#"[{"peerId":9,"lastMessageContent":"最近怎么样","unreadCount":2,"lastMessageTime":"2026-07-30T10:00:00Z"}]"#)
        fixture.service.groupsResult = try decodeDTO(#"[{"groupId":"g1","name":"同事群","avatar":"g.png","lastMessageContent":"收到","lastMessageTime":"2026-07-30T11:00:00Z"}]"#)

        await fixture.center.refreshAll()

        let friend = try #require(try await fixture.store.friend(userId: 9))
        #expect(friend.nickname == "艾丽")
        #expect(friend.personProfileID == "person-1")
        #expect(try await fixture.store.friend(userId: 99) == nil)
        #expect(try await fixture.store.loadFriendRequests().map(\.id) == [5])

        let peer = try #require(try await fixture.store.conversation(id: "peer:9"))
        #expect(peer.title == "艾丽")
        #expect(peer.unreadCount == 2)
        #expect(peer.lastMessagePreview == "最近怎么样")

        let group = try #require(try await fixture.store.conversation(id: "group:g1"))
        #expect(group.title == "同事群")
        #expect(group.avatar == "g.png")
        #expect(group.lastMessagePreview == "收到")
    }

    @Test func loadOlderMessagesUsesOldestServerCursor() async throws {
        let fixture = try makeFixture()
        let conversationId = try await fixture.center.openPeerConversation(peerId: 9)
        _ = try await fixture.store.upsertMessage(ImMessage(
            id: "m5", conversationId: conversationId, senderId: 9,
            content: "旧消息", status: .delivered, createdAt: 2000
        ))
        _ = try await fixture.store.upsertMessage(ImMessage(
            id: "temp_x", conversationId: conversationId, senderId: 1,
            content: "乐观", status: .sending, createdAt: 1000
        ))
        fixture.service.chatHistoryResult = try decodeDTO(
            #"{"messages":[{"messageId":"m1","senderId":9,"content":"早","status":"read","sentAt":"2026-07-30T09:00:00Z"}],"has_more":true}"#
        )

        let hasMore = try await fixture.center.loadOlderMessages(conversationId: conversationId)

        #expect(hasMore)
        let call = try #require(fixture.service.chatHistoryCalls.first)
        #expect(call.peerId == 9)
        #expect(call.beforeId == "m5")
        let paged = try #require(try await fixture.store.message(id: "m1"))
        #expect(paged.status == .read)
        #expect(paged.createdAt == ImMessageCenterTests.epochMs("2026-07-30T09:00:00Z"))
    }

    @Test func signOutClearsCachesAndCancelsPendingSends() async throws {
        let fixture = try makeFixture()
        try await fixture.center.sendChatMessage(peerId: 9, content: "hi")
        try await fixture.store.upsertFriends([ImFriend(userId: 9, username: "alice")])

        await fixture.center.handleSignOut()

        #expect(try await fixture.store.loadConversations().isEmpty)
        #expect(try await fixture.store.loadFriends().isEmpty)
        #expect(try await fixture.store.loadFriendRequests().isEmpty)
        // A late ack after sign-out pairs with nothing and must not crash.
        await fixture.center.handleFrame(type: nil, text: #"{"messageId":"srv-1"}"#)
        #expect(try await fixture.store.message(id: "srv-1") == nil)
    }

    @Test func prepareAfterLaunchFailsDanglingOptimisticSends() async throws {
        let fixture = try makeFixture()
        let conversationId = try await fixture.center.openPeerConversation(peerId: 9)
        _ = try await fixture.store.upsertMessage(ImMessage(
            id: "temp_dangling", conversationId: conversationId, senderId: 1,
            content: "上次进程遗留", status: .sending, createdAt: 1000
        ))

        await fixture.center.prepareAfterLaunch()

        #expect(try await fixture.store.message(id: "temp_dangling")?.status == .failed)
    }

    // MARK: - Helpers

    private struct Fixture {
        let center: ImMessageCenter
        let store: SQLiteImStore
        let service: StubImService
        let frames: FrameRecorder
    }

    private func makeFixture(sendTimeout: Duration = .seconds(15), selfId: Int64 = 1) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImMessageCenterTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteImStore(databaseURL: root.appendingPathComponent("im.sqlite"))
        let service = StubImService()
        let frames = FrameRecorder()
        let center = ImMessageCenter(
            store: store,
            service: service,
            sendFrame: { frames.record($0) },
            currentIdentity: { ImSelfIdentity(id: selfId, displayName: "康纳") },
            configuration: .init(sendTimeout: sendTimeout)
        )
        return Fixture(center: center, store: store, service: service, frames: frames)
    }

    private func decodeDTO<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @Sendable () async throws -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try await condition()
    }

    static func epochMs(_ rfc3339: String) -> Int64 {
        Int64(ISO8601DateFormatter().date(from: rfc3339)!.timeIntervalSince1970 * 1000)
    }
}

// MARK: - Test doubles

private final class FrameRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _accept = true
    private var _sentFrames: [String] = []

    var accept: Bool {
        get { lock.withLock { _accept } }
        set { lock.withLock { _accept = newValue } }
    }

    var sentFrames: [String] { lock.withLock { _sentFrames } }

    func record(_ frame: String) -> Bool {
        lock.withLock {
            _sentFrames.append(frame)
            return _accept
        }
    }
}

private final class StubImService: ImBackendServicing, @unchecked Sendable {
    private let lock = NSLock()

    var friendsResult: [ImFriendDTO] {
        get { lock.withLock { _friendsResult } }
        set { lock.withLock { _friendsResult = newValue } }
    }
    var receivedRequestsResult: [ImFriendRequestDTO] {
        get { lock.withLock { _receivedRequestsResult } }
        set { lock.withLock { _receivedRequestsResult = newValue } }
    }
    var conversationsResult: [ImConversationDTO] {
        get { lock.withLock { _conversationsResult } }
        set { lock.withLock { _conversationsResult = newValue } }
    }
    var groupsResult: [ImGroupDTO] {
        get { lock.withLock { _groupsResult } }
        set { lock.withLock { _groupsResult = newValue } }
    }
    var chatHistoryResult: ImChatHistoryDTO? {
        get { lock.withLock { _chatHistoryResult } }
        set { lock.withLock { _chatHistoryResult = newValue } }
    }
    var markReadPeerIds: [Int64] { lock.withLock { _markReadPeerIds } }
    var chatHistoryCalls: [(peerId: Int64, beforeId: String?, limit: Int)] { lock.withLock { _chatHistoryCalls } }

    private var _friendsResult: [ImFriendDTO] = []
    private var _receivedRequestsResult: [ImFriendRequestDTO] = []
    private var _conversationsResult: [ImConversationDTO] = []
    private var _groupsResult: [ImGroupDTO] = []
    private var _chatHistoryResult: ImChatHistoryDTO?
    private var _markReadPeerIds: [Int64] = []
    private var _chatHistoryCalls: [(peerId: Int64, beforeId: String?, limit: Int)] = []

    func conversations() async throws -> [ImConversationDTO] { conversationsResult }

    func chatHistory(peerId: Int64, beforeId: String?, limit: Int) async throws -> ImChatHistoryDTO {
        lock.withLock { _chatHistoryCalls.append((peerId, beforeId, limit)) }
        return try chatHistoryResult ?? decode(#"{"messages":[],"has_more":false}"#)
    }

    func markRead(peerId: Int64, messageIds: [String]) async throws -> ImMarkReadResultDTO {
        lock.withLock { _markReadPeerIds.append(peerId) }
        return try decode(#"{"updatedCount":1,"unreadCount":0}"#)
    }

    func myGroups() async throws -> [ImGroupDTO] { groupsResult }

    func createGroup(name: String, description: String) async throws -> ImGroupDTO {
        try decode(#"{"groupId":"g-new","name":"\#(name)"}"#)
    }

    func groupMessages(groupId: String, beforeId: String?, limit: Int) async throws -> ImGroupHistoryDTO {
        try decode(#"{"messages":[],"has_more":false}"#)
    }

    func inviteGroupMember(groupId: String, userId: Int64) async throws {}
    func removeGroupMember(groupId: String, userId: Int64) async throws {}

    func friends() async throws -> [ImFriendDTO] { friendsResult }

    func sendFriendRequest(username: String, message: String) async throws -> ImFriendRequestDTO {
        try decode(#"{"ID":1,"senderId":1,"receiverId":2}"#)
    }

    func receivedFriendRequests() async throws -> [ImFriendRequestDTO] { receivedRequestsResult }
    func sentFriendRequests() async throws -> [ImFriendRequestDTO] { [] }

    func acceptFriendRequest(requestId: Int64) async throws -> ImFriendRequestDTO {
        try decode(#"{"ID":\#(requestId),"senderId":1,"receiverId":2,"status":"accepted"}"#)
    }

    func rejectFriendRequest(requestId: Int64) async throws -> ImFriendRequestDTO {
        try decode(#"{"ID":\#(requestId),"senderId":1,"receiverId":2,"status":"rejected"}"#)
    }

    func deleteFriend(userId: Int64) async throws {}

    func searchUsers(query: String, limit: Int) async throws -> [ImPublicUserDTO] { [] }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
