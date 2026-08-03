import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("SQLite IM Store Tests")
struct SQLiteImStoreTests {
    @Test func newDatabaseStartsEmpty() async throws {
        let store = try makeStore()

        #expect(try await store.loadConversations().isEmpty)
        #expect(try await store.loadFriends().isEmpty)
        #expect(try await store.loadFriendRequests().isEmpty)
    }

    @Test func conversationsOrderPinnedFirstThenLastMessageDescending() async throws {
        let store = try makeStore()
        try await store.upsertConversations([
            makeConversation(id: "peer:1", peerUserId: 1, lastMessageAt: 100),
            makeConversation(id: "peer:2", peerUserId: 2, lastMessageAt: 300),
            makeConversation(id: "peer:3", peerUserId: 3, lastMessageAt: 200, pinned: true)
        ])

        let ordered = try await store.loadConversations().map(\.id)

        #expect(ordered == ["peer:3", "peer:2", "peer:1"])
    }

    @Test func conversationLocalPreferenceUpdatesRoundTrip() async throws {
        let store = try makeStore()
        try await store.upsertConversation(makeConversation(id: "peer:9", peerUserId: 9, unreadCount: 5))

        try await store.setPinned(conversationId: "peer:9", pinned: true, now: 10)
        try await store.setMuted(conversationId: "peer:9", muted: true, now: 20)
        try await store.clearUnread(conversationId: "peer:9", now: 30)

        let conversation = try #require(try await store.conversation(id: "peer:9"))
        #expect(conversation.pinned)
        #expect(conversation.muted)
        #expect(conversation.unreadCount == 0)
        #expect(conversation.updatedAt == 30)
    }

    @Test func conversationGovernanceAndCustomTitleRoundTrip() async throws {
        let store = try makeStore()
        try await store.upsertConversation(makeConversation(id: "peer:9", peerUserId: 9))

        try await store.renameConversation(conversationId: "peer:9", title: "项目讨论", customized: true, now: 10)
        try await store.setConversationStatus(conversationId: "peer:9", status: .inProgress, now: 20)
        try await store.setConversationLabels(conversationId: "peer:9", labelIds: ["important", "project"], now: 30)

        let conversation = try #require(try await store.conversation(id: "peer:9"))
        #expect(conversation.title == "项目讨论")
        #expect(conversation.participantName == "用户 9")
        #expect(conversation.titleCustomized)
        #expect(conversation.status == .inProgress)
        #expect(conversation.labelIds == ["important", "project"])
        #expect(conversation.updatedAt == 30)
    }

    @Test func messagesOrderByCreatedAtThenSeqAndUpsertIsIdempotentById() async throws {
        let store = try makeStore()
        try await store.upsertConversation(makeConversation(id: "peer:1", peerUserId: 1))

        let first = try await store.upsertMessage(makeMessage(id: "m1", createdAt: 100, content: "first"))
        _ = try await store.upsertMessage(makeMessage(id: "m2", createdAt: 100, content: "second"))
        _ = try await store.upsertMessage(makeMessage(id: "m0", createdAt: 50, content: "oldest"))

        // Same id again: row updated in place, seq preserved, no duplicate.
        let updated = try await store.upsertMessage(makeMessage(id: "m1", createdAt: 100, content: "first-edited"))
        #expect(updated.seq == first.seq)

        let messages = try await store.messages(conversationId: "peer:1")
        #expect(messages.map(\.id) == ["m0", "m1", "m2"])
        #expect(messages.map(\.content) == ["oldest", "first-edited", "second"])
    }

    @Test func replaceMessageIdKeepsSeqForStableOrdering() async throws {
        let store = try makeStore()
        try await store.upsertConversation(makeConversation(id: "peer:1", peerUserId: 1))
        let tempId = ImMessage.makeTemporaryID()
        let optimistic = try await store.upsertMessage(makeMessage(id: tempId, status: .sending, createdAt: 100))
        _ = try await store.upsertMessage(makeMessage(id: "later", createdAt: 100))

        try await store.replaceMessageId(oldId: tempId, newId: "server-id", status: .sent)

        let messages = try await store.messages(conversationId: "peer:1")
        #expect(messages.map(\.id) == ["server-id", "later"])
        let acked = try #require(try await store.message(id: "server-id"))
        #expect(acked.seq == optimistic.seq)
        #expect(acked.status == .sent)
        #expect(try await store.message(id: tempId) == nil)
    }

    @Test func deleteConversationCascadesMessages() async throws {
        let store = try makeStore()
        try await store.upsertConversation(makeConversation(id: "peer:1", peerUserId: 1))
        _ = try await store.upsertMessage(makeMessage(id: "m1"))

        try await store.deleteConversation(id: "peer:1")

        #expect(try await store.message(id: "m1") == nil)
        #expect(try await store.conversation(id: "peer:1") == nil)
    }

    @Test func markSenderMessagesReadSkipsFailed() async throws {
        let store = try makeStore()
        try await store.upsertConversation(makeConversation(id: "peer:1", peerUserId: 1))
        _ = try await store.upsertMessage(makeMessage(id: "sent", senderId: 7, status: .sent))
        _ = try await store.upsertMessage(makeMessage(id: "failed", senderId: 7, status: .failed))
        _ = try await store.upsertMessage(makeMessage(id: "other-sender", senderId: 8, status: .sent))

        try await store.markSenderMessagesRead(conversationId: "peer:1", senderId: 7)

        #expect(try await store.message(id: "sent")?.status == .read)
        #expect(try await store.message(id: "failed")?.status == .failed)
        #expect(try await store.message(id: "other-sender")?.status == .sent)
    }

    @Test func oldestServerMessageIdIgnoresOptimisticMessages() async throws {
        let store = try makeStore()
        try await store.upsertConversation(makeConversation(id: "peer:1", peerUserId: 1))
        _ = try await store.upsertMessage(makeMessage(id: "temp", status: .sending, createdAt: 10))
        _ = try await store.upsertMessage(makeMessage(id: "failed", status: .failed, createdAt: 20))
        _ = try await store.upsertMessage(makeMessage(id: "server-old", status: .sent, createdAt: 30))
        _ = try await store.upsertMessage(makeMessage(id: "server-new", status: .read, createdAt: 40))

        #expect(try await store.oldestServerMessageId(conversationId: "peer:1") == "server-old")
    }

    @Test func markSendingFailedRecoversDanglingOptimisticMessages() async throws {
        let store = try makeStore()
        try await store.upsertConversation(makeConversation(id: "peer:1", peerUserId: 1))
        _ = try await store.upsertMessage(makeMessage(id: "dangling", status: .sending))
        _ = try await store.upsertMessage(makeMessage(id: "done", status: .sent))

        try await store.markSendingFailed()

        #expect(try await store.message(id: "dangling")?.status == .failed)
        #expect(try await store.message(id: "done")?.status == .sent)
    }

    @Test func friendsUpsertBindAndPrune() async throws {
        let store = try makeStore()
        try await store.upsertFriends([
            ImFriend(userId: 1, username: "alice"),
            ImFriend(userId: 2, username: "bob"),
            ImFriend(userId: 3, username: "carol")
        ])

        try await store.bindFriendPerson(userId: 2, personProfileID: "person-bob", now: 99)
        #expect(try await store.friend(userId: 2)?.personProfileID == "person-bob")
        #expect(try await store.friendByPerson(personProfileID: "person-bob")?.userId == 2)

        try await store.bindFriendPerson(userId: 2, personProfileID: nil, now: 100)
        #expect(try await store.friend(userId: 2)?.personProfileID == nil)

        try await store.pruneFriends(keepUserIds: [1, 3])
        #expect(try await store.loadFriends().map(\.userId) == [1, 3])

        try await store.deleteFriend(userId: 1)
        #expect(try await store.loadFriends().map(\.userId) == [3])
    }

    @Test func friendRequestsOrderByCreatedAtDescending() async throws {
        let store = try makeStore()
        try await store.upsertFriendRequests([
            ImFriendRequest(id: 1, senderId: 10, receiverId: 20, createdAt: 100),
            ImFriendRequest(id: 2, senderId: 11, receiverId: 20, createdAt: 300),
            ImFriendRequest(id: 3, senderId: 12, receiverId: 20, createdAt: 300)
        ])

        #expect(try await store.loadFriendRequests().map(\.id) == [3, 2, 1])
    }

    @Test func aliasLookupsBySenderTokenAndPerson() async throws {
        let store = try makeStore()
        let alias = ImForwardAlias(
            aliasToken: "@CXA1B2C3",
            senderId: 42,
            imConversationId: "peer:42",
            personProfileID: "person-42",
            displayName: "张三",
            createdAt: 100
        )

        try await store.insertAlias(alias)

        #expect(try await store.aliasBySender(senderId: 42) == alias)
        #expect(try await store.aliasByToken("@CXA1B2C3") == alias)
        #expect(try await store.aliasesForPerson(personProfileID: "person-42") == [alias])
        #expect(try await store.aliasBySender(senderId: 43) == nil)
    }

    @Test func signOutCleanupClearsAllTables() async throws {
        let store = try makeStore()
        try await store.upsertConversation(makeConversation(id: "peer:1", peerUserId: 1))
        _ = try await store.upsertMessage(makeMessage(id: "m1"))
        try await store.upsertFriends([ImFriend(userId: 1, username: "alice")])
        try await store.upsertFriendRequests([ImFriendRequest(id: 1, senderId: 1, receiverId: 2)])
        try await store.insertAlias(ImForwardAlias(aliasToken: "@CX000001", senderId: 1, imConversationId: "peer:1", personProfileID: "p", displayName: "d", createdAt: 1))

        try await store.clearConversations()
        try await store.clearFriends()
        try await store.clearFriendRequests()
        try await store.clearForwardAliases()

        #expect(try await store.loadConversations().isEmpty)
        #expect(try await store.message(id: "m1") == nil)
        #expect(try await store.loadFriends().isEmpty)
        #expect(try await store.loadFriendRequests().isEmpty)
        #expect(try await store.aliasBySender(senderId: 1) == nil)
    }

    @Test func messageStatusMachineAdvancesOneWayOnly() {
        #expect(ImMessageStatus.sending.canAdvance(to: .sent))
        #expect(ImMessageStatus.sent.canAdvance(to: .delivered))
        #expect(ImMessageStatus.sent.canAdvance(to: .read))
        #expect(!ImMessageStatus.read.canAdvance(to: .sent))
        #expect(!ImMessageStatus.delivered.canAdvance(to: .sending))
        #expect(ImMessageStatus.sending.canAdvance(to: .failed))
        #expect(!ImMessageStatus.sent.canAdvance(to: .failed))
        #expect(ImMessageStatus.failed.canAdvance(to: .sending))
    }

    @Test func conversationIDBuilders() {
        #expect(ImConversation.peerConversationID(peerUserId: 42) == "peer:42")
        #expect(ImConversation.groupConversationID(groupId: "g-1") == "group:g-1")
    }

    // MARK: - Helpers

    private func makeStore() throws -> SQLiteImStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteImStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try SQLiteImStore(databaseURL: root.appendingPathComponent("im.sqlite"))
    }

    private func makeConversation(
        id: String,
        peerUserId: Int64,
        lastMessageAt: Int64 = 0,
        unreadCount: Int = 0,
        pinned: Bool = false
    ) -> ImConversation {
        ImConversation(
            id: id,
            kind: .peer,
            peerUserId: peerUserId,
            title: "用户 \(peerUserId)",
            lastMessageAt: lastMessageAt,
            unreadCount: unreadCount,
            pinned: pinned
        )
    }

    private func makeMessage(
        id: String,
        conversationId: String = "peer:1",
        senderId: Int64 = 1,
        status: ImMessageStatus = .sent,
        createdAt: Int64 = 100,
        content: String = "hello"
    ) -> ImMessage {
        ImMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            status: status,
            createdAt: createdAt
        )
    }
}
