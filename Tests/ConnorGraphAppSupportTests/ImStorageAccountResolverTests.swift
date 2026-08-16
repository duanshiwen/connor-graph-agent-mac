import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("IM 账号存储隔离")
struct ImStorageAccountResolverTests {
    private var root: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ImStorageAccountResolverTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test func databaseURLResolvesPerAccount() {
        let appSupport = root
        let shared = ImStorageAccountResolver.databaseURL(applicationSupportDirectory: appSupport, userID: nil)
        #expect(shared.lastPathComponent == "im.sqlite")

        let account = ImStorageAccountResolver.databaseURL(applicationSupportDirectory: appSupport, userID: 7)
        #expect(account.lastPathComponent == "im-7.sqlite")
        #expect(account.deletingLastPathComponent().lastPathComponent == "im")
        #expect(account != shared)
    }

    @Test func userIDFromAccessTokenDecodesPayload() {
        // header.payload.signature（payload: {"user_id":3,"username":"段诗闻"}）
        let payload = "eyJ1c2VyX2lkIjozLCJ1c2VybmFtZSI6Iuauteivl-mXuyJ9"
        let token = "header.\(payload).signature"
        #expect(ImStorageAccountResolver.userID(fromAccessToken: token) == 3)
        #expect(ImStorageAccountResolver.userID(fromAccessToken: "not-a-jwt") == nil)
        #expect(ImStorageAccountResolver.userID(fromAccessToken: "a.b.c.d") == nil)
    }

    @Test func soleMessageOwnerReturnsSingleOwnerOnly() async throws {
        let dir = root
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("legacy.sqlite")
        let store = try SQLiteImStore(databaseURL: url)
        try await store.upsertConversation(makeConversation(id: "peer:2", peerUserId: 2))
        try await store.upsertConversation(makeConversation(id: "peer:9", peerUserId: 9))
        // 单账号：全部已发送消息来自 sender 3
        _ = try await store.upsertMessage(makeMessage(id: "m1", senderId: 3, status: .sent))
        _ = try await store.upsertMessage(makeMessage(id: "m2", senderId: 3, status: .failed))
        _ = try await store.upsertMessage(makeMessage(id: "m3", conversationId: "peer:2", senderId: 2, status: .read))

        #expect(try ImStorageAccountResolver.soleMessageOwner(databaseURL: url) == 3)

        // 混入另一账号的已发送消息后不再迁移
        _ = try await store.upsertMessage(makeMessage(id: "m4", conversationId: "peer:9", senderId: 1, status: .sent))
        #expect(try ImStorageAccountResolver.soleMessageOwner(databaseURL: url) == nil)
    }

    @Test func migrateLegacyDatabaseOnlyForSoleOwner() async throws {
        let appSupport = root
        try FileManager.default.createDirectory(
            at: ImStorageAccountResolver.imDirectory(applicationSupportDirectory: appSupport),
            withIntermediateDirectories: true
        )
        let legacyURL = ImStorageAccountResolver.sharedDatabaseURL(applicationSupportDirectory: appSupport)
        let store = try SQLiteImStore(databaseURL: legacyURL)
        try await store.upsertConversation(makeConversation(id: "peer:2", peerUserId: 2))
        _ = try await store.upsertMessage(makeMessage(id: "m1", senderId: 3, status: .sent))
        // 只属于账号 3：迁移成功
        try ImStorageAccountResolver.migrateLegacyDatabaseIfNeeded(applicationSupportDirectory: appSupport, userID: 3)
        #expect(FileManager.default.fileExists(
            atPath: ImStorageAccountResolver.accountDatabaseURL(applicationSupportDirectory: appSupport, userID: 3).path
        ))
        // 目标库存在后不再重复迁移
        try ImStorageAccountResolver.migrateLegacyDatabaseIfNeeded(applicationSupportDirectory: appSupport, userID: 3)
        #expect(FileManager.default.fileExists(
            atPath: ImStorageAccountResolver.accountDatabaseURL(applicationSupportDirectory: appSupport, userID: 3).path
        ))
        // 属于账号 3 的库不迁移给账号 7（避免把旧账号历史混进新账号）
        try ImStorageAccountResolver.migrateLegacyDatabaseIfNeeded(applicationSupportDirectory: appSupport, userID: 7)
        #expect(!FileManager.default.fileExists(
            atPath: ImStorageAccountResolver.accountDatabaseURL(applicationSupportDirectory: appSupport, userID: 7).path
        ))
    }

    @Test func migrateLegacyDatabaseSkipsMixedAccounts() async throws {
        let appSupport = root
        try FileManager.default.createDirectory(
            at: ImStorageAccountResolver.imDirectory(applicationSupportDirectory: appSupport),
            withIntermediateDirectories: true
        )
        let legacyURL = ImStorageAccountResolver.sharedDatabaseURL(applicationSupportDirectory: appSupport)
        let store = try SQLiteImStore(databaseURL: legacyURL)
        try await store.upsertConversation(makeConversation(id: "peer:2", peerUserId: 2))
        try await store.upsertConversation(makeConversation(id: "peer:9", peerUserId: 9))
        _ = try await store.upsertMessage(makeMessage(id: "m1", senderId: 3, status: .sent))
        _ = try await store.upsertMessage(makeMessage(id: "m2", conversationId: "peer:9", senderId: 1, status: .sent))

        // 混合账号数据不迁移，任何账号都不继承旧库。
        try ImStorageAccountResolver.migrateLegacyDatabaseIfNeeded(applicationSupportDirectory: appSupport, userID: 3)
        try ImStorageAccountResolver.migrateLegacyDatabaseIfNeeded(applicationSupportDirectory: appSupport, userID: 1)
        #expect(!FileManager.default.fileExists(
            atPath: ImStorageAccountResolver.accountDatabaseURL(applicationSupportDirectory: appSupport, userID: 3).path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: ImStorageAccountResolver.accountDatabaseURL(applicationSupportDirectory: appSupport, userID: 1).path
        ))
    }

    // MARK: - Helpers

    private func makeConversation(id: String, peerUserId: Int64) -> ImConversation {
        ImConversation(
            id: id,
            kind: .peer,
            peerUserId: peerUserId,
            title: "用户 \(peerUserId)",
            lastMessageAt: 0,
            unreadCount: 0,
            pinned: false
        )
    }

    private func makeMessage(
        id: String,
        conversationId: String = "peer:2",
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
