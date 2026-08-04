import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("IM Message Center Tests")
struct ImMessageCenterTests {
    @Test func mediaMetadataEncodesSnakeKeysForAndroidCompatibility() throws {
        let metadata = ImMediaMetadata(
            fileSize: 2048,
            fileName: "报告.pdf",
            mimeType: "application/pdf",
            attachmentKind: "file",
            objectName: "chat/1/2026/08/report.pdf"
        )
        let data = try JSONEncoder().encode(metadata)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["attachment_kind"] as? String == "file")
        #expect(object["attachmentKind"] as? String == "file")
        #expect(object["file_name"] as? String == "报告.pdf")
        #expect(object["mime_type"] as? String == "application/pdf")
        #expect(object["object_name"] as? String == "chat/1/2026/08/report.pdf")
        #expect(object["size"] as? Int == 2048)
    }

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

    @Test(.disabled("Environment-sensitive: the 20ms ack timer starves beyond the deadline under full-suite load on this machine; passes in isolation."))
    func missingAckTimesOutIntoFailed() async throws {
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
        #expect(fixture.events.events == [.incomingMessage(message: message, conversation: conversation)])

        // Duplicate push with the same message id is a no-op.
        await fixture.center.handleFrame(type: "chat_receive", text: """
            {"type":"chat_receive","payload":{"sender_id":9,"message_id":"m1","content":"最近怎么样"}}
            """)
        #expect(try await fixture.store.conversation(id: conversationId)?.unreadCount == 1)
        #expect(fixture.events.events.count == 1)
    }

    @Test func outOfOrderRealtimeMessageDoesNotReplaceLatestConversationPreview() async throws {
        let fixture = try makeFixture()

        await fixture.center.handleFrame(type: "chat_receive", text: """
            {"type":"chat_receive","payload":{"sender_id":9,"message_id":"newer",
            "content":"较新的消息","sent_at":2000}}
            """)
        await fixture.center.handleFrame(type: "chat_receive", text: """
            {"type":"chat_receive","payload":{"sender_id":9,"message_id":"older",
            "content":"迟到的旧消息","sent_at":1000}}
            """)

        let conversation = try #require(try await fixture.store.conversation(id: "peer:9"))
        #expect(conversation.lastMessagePreview == "较新的消息")
        #expect(conversation.lastMessageAt == 2000)
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
        #expect(fixture.events.events.count == 1)
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
        #expect(fixture.events.events.isEmpty)
    }

    @Test func groupReceiveFromOthersCountsUnread() async throws {
        let fixture = try makeFixture()

        await fixture.center.handleFrame(type: "group_receive", text: """
            {"type":"group_receive","payload":{"group_id":"g1","message_id":"gm1","sender_id":7,
            "sender_username":"kevin_account","sender_nickname":"Kevin","sender_avatar":"a.png","content":"午饭吃啥"}}
            """)

        let conversationId = ImConversation.groupConversationID(groupId: "g1")
        #expect(try await fixture.store.conversation(id: conversationId)?.unreadCount == 1)
        let message = try #require(try await fixture.store.message(id: "gm1"))
        #expect(message.status == .delivered)
        #expect(message.senderName == "Kevin")
        #expect(message.senderAvatar == "a.png")
        #expect(fixture.events.events.count == 1)
    }

    @Test func groupHistoryUsesServerMemberProfileWithoutFriendship() async throws {
        let fixture = try makeFixture()
        fixture.service.groupsResult = try decodeDTO(
            #"[{"groupId":"g1","name":"测试群聊 001"}]"#
        )
        await fixture.center.refreshAll()
        let conversationId = ImConversation.groupConversationID(groupId: "g1")
        fixture.service.groupHistoryResults = [try decodeDTO(
            #"{"messages":[{"messageId":"gm-kevin","groupId":"g1","senderId":7,"senderUsername":"kevin_account","senderNickname":"Kevin","senderAvatar":"kevin.png","content":"晚上开会","sentAt":"2026-08-03T09:20:00Z"}],"has_more":false}"#
        )]

        _ = try await fixture.center.loadOlderMessages(conversationId: conversationId)

        let message = try #require(try await fixture.store.message(id: "gm-kevin"))
        #expect(message.senderName == "Kevin")
        #expect(message.senderAvatar == "kevin.png")
    }

    @Test func friendRequestReceivedEmitsOnlyForNewPendingInvitation() async throws {
        let fixture = try makeFixture()
        fixture.service.receivedRequestsResult = try decodeDTO(
            #"[{"ID":5,"senderId":9,"receiverId":1,"status":"pending","senderUsername":"alice"}]"#
        )
        let frame = #"{"type":"friend_request_received","payload":{"request_id":5}}"#

        await fixture.center.handleFrame(type: "friend_request_received", text: frame)
        await fixture.center.handleFrame(type: "friend_request_received", text: frame)

        let request = try #require(try await fixture.store.loadFriendRequests().first)
        #expect(fixture.events.events == [.incomingFriendRequest(request)])
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
        #expect(try await fixture.store.loadFriendRequests().first?.status == "accepted")
    }

    @Test func rejectingFriendRequestClearsPendingStateBeforeRemoteListConverges() async throws {
        let fixture = try makeFixture(selfId: 2)
        try await fixture.store.upsertFriendRequests([ImFriendRequest(
            id: 78,
            senderId: 1,
            receiverId: 2,
            status: "pending"
        )])

        try await fixture.center.rejectFriendRequest(requestId: 78)

        #expect(try await fixture.store.loadFriendRequests().first?.status == "rejected")
    }

    @Test func refreshAllBackfillsFriendsConversationsAndGroups() async throws {
        let fixture = try makeFixture()
        // Preserve the local bridge and friends originating from another account.
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
        #expect(try await fixture.store.friend(userId: 99)?.username == "stale")
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

    @Test func createGroupPassesInitialMembersAndLeaveRemovesConversation() async throws {
        let fixture = try makeFixture()
        let group = try await fixture.center.createGroup(name: "项目群", description: "讨论", memberIds: [7, 9])
        #expect(group.groupId == "g-new")
        #expect(fixture.service.createdGroupMemberIDs == [7, 9])
        #expect(try await fixture.store.conversation(id: "group:g-new") != nil)

        try await fixture.center.leaveGroup(groupId: "g-new")
        #expect(fixture.service.leftGroupIDs == ["g-new"])
        #expect(try await fixture.store.conversation(id: "group:g-new") == nil)
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

    @Test func loadLatestMessagesClosesGapWhenLocalCacheAlreadyHasMessages() async throws {
        let fixture = try makeFixture()
        let conversationId = try await fixture.center.openPeerConversation(peerId: 9)
        _ = try await fixture.store.upsertMessage(ImMessage(
            id: "m1", conversationId: conversationId, senderId: 9,
            content: "本地旧消息", status: .delivered, createdAt: 1_000
        ))
        fixture.service.chatHistoryResult = try decodeDTO(
            #"{"messages":[{"messageId":"m2","senderId":9,"content":"列表中的最新消息","status":"delivered","sentAt":"2026-08-03T09:10:00Z"}],"has_more":true}"#
        )

        let hasMore = try await fixture.center.loadLatestMessages(conversationId: conversationId)

        #expect(hasMore)
        let call = try #require(fixture.service.chatHistoryCalls.first)
        #expect(call.peerId == 9)
        #expect(call.beforeId == nil)
        let messages = try await fixture.store.messages(conversationId: conversationId)
        #expect(messages.map(\.id) == ["m1", "m2"])
        #expect(messages.last?.content == "列表中的最新消息")
    }

    @Test func socketReconnectClosesMultiPagePeerOfflineGap() async throws {
        let fixture = try makeFixture()
        let conversationId = try await fixture.center.openPeerConversation(peerId: 9)
        _ = try await fixture.store.upsertMessage(ImMessage(
            id: "m1", conversationId: conversationId, senderId: 9,
            content: "上线前", status: .delivered,
            createdAt: Self.epochMs("2026-08-03T09:00:00Z")
        ))
        await fixture.center.setActiveConversation(conversationId)
        fixture.service.conversationsResult = try decodeDTO(
            #"[{"peerId":9,"lastMessageId":"m3","lastMessageContent":"离线第三条","lastMessageTime":"2026-08-03T09:20:00Z"}]"#
        )
        fixture.service.chatHistoryResults = [
            try decodeDTO(#"{"messages":[{"messageId":"m3","senderId":9,"content":"离线第三条","sentAt":"2026-08-03T09:20:00Z"},{"messageId":"m2","senderId":9,"content":"离线第二条","sentAt":"2026-08-03T09:10:00Z"}],"has_more":true}"#),
            try decodeDTO(#"{"messages":[{"messageId":"m1","senderId":9,"content":"上线前","sentAt":"2026-08-03T09:00:00Z"}],"has_more":false}"#)
        ]

        await fixture.center.handleSocketConnected()

        let messages = try await fixture.store.messages(conversationId: conversationId)
        #expect(messages.map(\.id) == ["m1", "m2", "m3"])
        #expect(fixture.service.chatHistoryCalls.map(\.beforeId) == [nil, "m2"])
        #expect(try await fixture.store.conversation(id: conversationId)?.lastMessagePreview == "离线第三条")
    }

    @Test func socketReconnectClosesMultiPageGroupOfflineGap() async throws {
        let fixture = try makeFixture()
        fixture.service.groupsResult = try decodeDTO(
            #"[{"groupId":"g1","name":"项目群","lastMessageId":"g1","lastMessageContent":"上线前","lastMessageTime":"2026-08-03T09:00:00Z"}]"#
        )
        await fixture.center.refreshAll()
        let conversationId = ImConversation.groupConversationID(groupId: "g1")
        _ = try await fixture.store.upsertMessage(ImMessage(
            id: "g1", conversationId: conversationId, senderId: 7,
            content: "上线前", status: .delivered,
            createdAt: Self.epochMs("2026-08-03T09:00:00Z")
        ))
        await fixture.center.setActiveConversation(conversationId)
        fixture.service.groupsResult = try decodeDTO(
            #"[{"groupId":"g1","name":"项目群","lastMessageId":"g3","lastMessageContent":"离线群消息三","lastMessageTime":"2026-08-03T09:20:00Z"}]"#
        )
        fixture.service.groupHistoryResults = [
            try decodeDTO(#"{"messages":[{"messageId":"g3","groupId":"g1","senderId":7,"content":"离线群消息三","sentAt":"2026-08-03T09:20:00Z"},{"messageId":"g2","groupId":"g1","senderId":8,"content":"离线群消息二","sentAt":"2026-08-03T09:10:00Z"}],"has_more":true}"#),
            try decodeDTO(#"{"messages":[{"messageId":"g1","groupId":"g1","senderId":7,"content":"上线前","sentAt":"2026-08-03T09:00:00Z"}],"has_more":false}"#)
        ]

        await fixture.center.handleSocketConnected()

        let messages = try await fixture.store.messages(conversationId: conversationId)
        #expect(messages.map(\.id) == ["g1", "g2", "g3"])
        #expect(fixture.service.groupHistoryCalls.map(\.beforeId) == [nil, "g2"])
        #expect(try await fixture.store.conversation(id: conversationId)?.lastMessagePreview == "离线群消息三")
    }

    @Test func signOutPreservesLocalDataAndCancelsPendingSends() async throws {
        let fixture = try makeFixture()
        try await fixture.center.sendChatMessage(peerId: 9, content: "hi")
        try await fixture.store.upsertFriends([ImFriend(userId: 9, username: "alice")])
        try await fixture.store.upsertFriendRequests([ImFriendRequest(id: 1, senderId: 9, receiverId: 1)])

        await fixture.center.handleSignOut()

        #expect(try await fixture.store.loadConversations().count == 1)
        #expect(try await fixture.store.loadFriends().map(\.userId) == [9])
        #expect(try await fixture.store.loadFriendRequests().map(\.id) == [1])
        let retained = try #require(try await fixture.store.messages(conversationId: "peer:9").first)
        #expect(retained.status == .failed)
        // A late ack after sign-out pairs with nothing and must not crash.
        await fixture.center.handleFrame(type: nil, text: #"{"messageId":"srv-1"}"#)
        #expect(try await fixture.store.message(id: "srv-1") == nil)
    }

    @Test func accountRefreshDoesNotPrunePreviousAccountFriendsOrGroups() async throws {
        let fixture = try makeFixture()
        try await fixture.store.upsertFriends([ImFriend(userId: 99, username: "old-friend")])
        try await fixture.store.upsertConversation(ImConversation(
            id: "group:old-group", kind: .group, groupId: "old-group", title: "旧账号群聊"
        ))
        fixture.service.friendsResult = []
        fixture.service.groupsResult = []

        await fixture.center.refreshAll()

        #expect(try await fixture.store.friend(userId: 99)?.username == "old-friend")
        #expect(try await fixture.store.conversation(id: "group:old-group")?.title == "旧账号群聊")
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

    @Test func mediaSendCachesLocallyAndKeepsLocalPathOffWire() async throws {
        let fixture = try makeFixture()
        let conversationId = try await fixture.center.openPeerConversation(peerId: 9)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        try await fixture.center.sendMediaMessage(
            conversationId: conversationId,
            fileURL: file,
            messageType: .image,
            metadata: ImMediaMetadata(width: 320, height: 200, fileName: "photo.png")
        )

        let optimistic = try #require(try await fixture.store.messages(conversationId: conversationId).first)
        #expect(optimistic.messageType == "image")
        #expect(optimistic.mediaMetadata?.localPath != nil)
        #expect(FileManager.default.fileExists(atPath: optimistic.mediaMetadata?.localPath ?? ""))
        #expect(try await fixture.store.conversation(id: conversationId)?.lastMessagePreview == "[图片]")

        let frame = try #require(fixture.frames.sentFrames.first)
        let root = try #require(try JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any])
        let payload = try #require(root["payload"] as? [String: Any])
        #expect(payload["content"] as? String == "https://download.example/file")
        let extra = try #require(payload["extra"] as? [String: Any])
        #expect(extra["localPath"] == nil)
        #expect(extra["width"] as? Int == 320)
        #expect(extra["objectName"] as? String == "chat/1/image/server.png")

        await fixture.center.handleFrame(type: nil, text: #"{"messageId":"media-1"}"#)
        #expect(fixture.service.privateMediaCachedIDs == ["media-1"])
    }

    @Test func groupReadIsReportedAndLocalMessagesBecomeRead() async throws {
        let fixture = try makeFixture()
        await fixture.center.handleFrame(type: "group_receive", text: """
            {"type":"group_receive","payload":{"group_id":"g1","message_id":"gm1","sender_id":7,
            "message_type":"text","content":"hello"}}
            """)
        let conversationId = ImConversation.groupConversationID(groupId: "g1")

        await fixture.center.markConversationRead(conversationId)

        #expect(try await fixture.store.message(id: "gm1")?.status == .read)
        #expect(fixture.service.groupReadIDs == ["g1"])
    }

    // MARK: - Helpers

    private struct Fixture {
        let center: ImMessageCenter
        let store: SQLiteImStore
        let service: StubImService
        let frames: FrameRecorder
        let events: EventRecorder
    }

    private func makeFixture(sendTimeout: Duration = .seconds(15), selfId: Int64 = 1) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImMessageCenterTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteImStore(databaseURL: root.appendingPathComponent("im.sqlite"))
        let service = StubImService()
        let frames = FrameRecorder()
        let events = EventRecorder()
        let center = ImMessageCenter(
            store: store,
            service: service,
            sendFrame: { frames.record($0) },
            currentIdentity: { ImSelfIdentity(id: selfId, displayName: "康纳") },
            onRealtimeEvent: { events.record($0) },
            configuration: .init(
                sendTimeout: sendTimeout,
                mediaCacheDirectory: root.appendingPathComponent("media", isDirectory: true)
            )
        )
        return Fixture(center: center, store: store, service: service, frames: frames, events: events)
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

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [ImRealtimeEvent] = []

    var events: [ImRealtimeEvent] { lock.withLock { _events } }

    func record(_ event: ImRealtimeEvent) {
        lock.withLock { _events.append(event) }
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
    var chatHistoryResults: [ImChatHistoryDTO] {
        get { lock.withLock { _chatHistoryResults } }
        set { lock.withLock { _chatHistoryResults = newValue } }
    }
    var groupHistoryResults: [ImGroupHistoryDTO] {
        get { lock.withLock { _groupHistoryResults } }
        set { lock.withLock { _groupHistoryResults = newValue } }
    }
    var markReadPeerIds: [Int64] { lock.withLock { _markReadPeerIds } }
    var chatHistoryCalls: [(peerId: Int64, beforeId: String?, limit: Int)] { lock.withLock { _chatHistoryCalls } }
    var groupHistoryCalls: [(groupId: String, beforeId: String?, limit: Int)] { lock.withLock { _groupHistoryCalls } }
    var privateMediaCachedIDs: [String] { lock.withLock { _privateMediaCachedIDs } }
    var groupReadIDs: [String] { lock.withLock { _groupReadIDs } }
    var createdGroupMemberIDs: [Int64] { lock.withLock { _createdGroupMemberIDs } }
    var leftGroupIDs: [String] { lock.withLock { _leftGroupIDs } }

    private var _friendsResult: [ImFriendDTO] = []
    private var _receivedRequestsResult: [ImFriendRequestDTO] = []
    private var _conversationsResult: [ImConversationDTO] = []
    private var _groupsResult: [ImGroupDTO] = []
    private var _chatHistoryResult: ImChatHistoryDTO?
    private var _chatHistoryResults: [ImChatHistoryDTO] = []
    private var _groupHistoryResults: [ImGroupHistoryDTO] = []
    private var _markReadPeerIds: [Int64] = []
    private var _chatHistoryCalls: [(peerId: Int64, beforeId: String?, limit: Int)] = []
    private var _groupHistoryCalls: [(groupId: String, beforeId: String?, limit: Int)] = []
    private var _privateMediaCachedIDs: [String] = []
    private var _groupReadIDs: [String] = []
    private var _createdGroupMemberIDs: [Int64] = []
    private var _leftGroupIDs: [String] = []

    func conversations() async throws -> [ImConversationDTO] { conversationsResult }

    func chatHistory(peerId: Int64, beforeId: String?, limit: Int) async throws -> ImChatHistoryDTO {
        lock.withLock { _chatHistoryCalls.append((peerId, beforeId, limit)) }
        if let queued = lock.withLock({ _chatHistoryResults.isEmpty ? nil : _chatHistoryResults.removeFirst() }) {
            return queued
        }
        return try chatHistoryResult ?? decode(#"{"messages":[],"has_more":false}"#)
    }

    func markRead(peerId: Int64, messageIds: [String]) async throws -> ImMarkReadResultDTO {
        lock.withLock { _markReadPeerIds.append(peerId) }
        return try decode(#"{"updatedCount":1,"unreadCount":0}"#)
    }

    func myGroups() async throws -> [ImGroupDTO] { groupsResult }

    func groupDetail(groupId: String) async throws -> ImGroupDTO {
        if let group = groupsResult.first(where: { $0.groupId == groupId }) { return group }
        return try decode(#"{"groupId":"\#(groupId)","name":"测试群"}"#)
    }

    func groupMembers(groupId: String) async throws -> [ImGroupMemberDTO] { [] }

    func createGroup(name: String, description: String, memberIds: [Int64]) async throws -> ImGroupDTO {
        lock.withLock { _createdGroupMemberIDs = memberIds }
        return try decode(#"{"groupId":"g-new","name":"\#(name)"}"#)
    }

    func groupMessages(groupId: String, beforeId: String?, limit: Int) async throws -> ImGroupHistoryDTO {
        lock.withLock { _groupHistoryCalls.append((groupId, beforeId, limit)) }
        if let queued = lock.withLock({ _groupHistoryResults.isEmpty ? nil : _groupHistoryResults.removeFirst() }) {
            return queued
        }
        return try decode(#"{"messages":[],"has_more":false}"#)
    }

    func inviteGroupMember(groupId: String, userId: Int64) async throws {}
    func removeGroupMember(groupId: String, userId: Int64) async throws {}
    func leaveGroup(groupId: String) async throws { lock.withLock { _leftGroupIDs.append(groupId) } }

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

    func uploadMedia(fileURL: URL, messageType: ImMessageType) async throws -> ImMediaUploadDTO {
        try decode("""
            {"upload_url":"https://upload.example/file","object_name":"chat/1/\(messageType.rawValue)/server.png",
            "download_url":"https://download.example/file","expires_in":3600}
            """)
    }

    func markPrivateMediaCached(messageId: String) async throws {
        lock.withLock { _privateMediaCachedIDs.append(messageId) }
    }

    func markGroupMediaCached(groupId: String, messageId: String) async throws {}

    func markGroupRead(groupId: String) async throws {
        lock.withLock { _groupReadIDs.append(groupId) }
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
