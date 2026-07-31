import Foundation
import SQLite3
import ConnorGraphCore

/// Local cache for the peer-to-peer IM feature. Five tables mirroring the Android
/// client's Room schema: conversations, messages, friends, friend requests and
/// forwarding alias tokens. This data is a per-account server projection and is
/// intentionally excluded from cross-device data sync.
public protocol ImStore: Sendable {
    // Conversations
    func loadConversations() async throws -> [ImConversation]
    func conversation(id: String) async throws -> ImConversation?
    func upsertConversation(_ conversation: ImConversation) async throws
    func upsertConversations(_ conversations: [ImConversation]) async throws
    func clearUnread(conversationId: String, now: Int64) async throws
    func setPinned(conversationId: String, pinned: Bool, now: Int64) async throws
    func setMuted(conversationId: String, muted: Bool, now: Int64) async throws
    func deleteConversation(id: String) async throws

    // Messages
    func messages(conversationId: String) async throws -> [ImMessage]
    func message(id: String) async throws -> ImMessage?
    @discardableResult
    func upsertMessage(_ message: ImMessage) async throws -> ImMessage
    func replaceMessageId(oldId: String, newId: String, status: ImMessageStatus) async throws
    func updateMessageStatus(id: String, status: ImMessageStatus) async throws
    func deleteMessage(id: String) async throws
    func markSenderMessagesRead(conversationId: String, senderId: Int64) async throws
    func oldestServerMessageId(conversationId: String) async throws -> String?
    func markSendingFailed() async throws

    // Friends
    func loadFriends() async throws -> [ImFriend]
    func friend(userId: Int64) async throws -> ImFriend?
    func friendByPerson(personProfileID: String) async throws -> ImFriend?
    func upsertFriends(_ friends: [ImFriend]) async throws
    func bindFriendPerson(userId: Int64, personProfileID: String?, now: Int64) async throws
    func deleteFriend(userId: Int64) async throws
    func pruneFriends(keepUserIds: [Int64]) async throws

    // Friend requests
    func loadFriendRequests() async throws -> [ImFriendRequest]
    func upsertFriendRequests(_ requests: [ImFriendRequest]) async throws

    // Forwarding aliases
    func aliasBySender(senderId: Int64) async throws -> ImForwardAlias?
    func aliasByToken(_ token: String) async throws -> ImForwardAlias?
    func aliasesForPerson(personProfileID: String) async throws -> [ImForwardAlias]
    func insertAlias(_ alias: ImForwardAlias) async throws

    // Sign-out / account-switch cleanup
    func clearConversations() async throws
    func clearFriends() async throws
    func clearFriendRequests() async throws
    func clearForwardAliases() async throws
}

public enum SQLiteImStoreError: Error, LocalizedError, Sendable, Equatable {
    case openFailed(String)
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): return message
        case .sqlite(let message): return message
        }
    }
}

public enum ImStoreChangeScope: String, Sendable {
    case conversations
    case messages
    case friends
    case friendRequests
    case forwardAliases
}

public extension Notification.Name {
    static let connorImStoreDidChange = Notification.Name("ConnorImStoreDidChange")
}

public enum ImStoreChangeNotificationUserInfoKey {
    public static let scope = "scope"
    public static let conversationID = "conversationID"
}

public final class SQLiteImStore: ImStore, @unchecked Sendable {
    private let db: OpaquePointer
    private let queue = DispatchQueue(label: "ConnorGraphAppSupport.SQLiteImStore")

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let openedDB = db else {
            throw SQLiteImStoreError.openFailed("Cannot open \(databaseURL.path)")
        }
        self.db = openedDB

        try Self.configurePragmas(db: openedDB)
        try Self.createTables(db: openedDB)
    }

    deinit {
        queue.sync {
            _ = sqlite3_close(db)
        }
    }

    // MARK: - Conversations

    public func loadConversations() async throws -> [ImConversation] {
        try queue.sync {
            try queryConversations(sql: "SELECT * FROM im_conversations ORDER BY pinned DESC, last_message_at DESC;", bindings: [])
        }
    }

    public func conversation(id: String) async throws -> ImConversation? {
        try queue.sync {
            try queryConversations(sql: "SELECT * FROM im_conversations WHERE id = ? LIMIT 1;", bindings: [.text(id)]).first
        }
    }

    public func upsertConversation(_ conversation: ImConversation) async throws {
        try queue.sync {
            try upsertConversationInternal(conversation)
        }
        postChange(scope: .conversations, conversationID: conversation.id)
    }

    public func upsertConversations(_ conversations: [ImConversation]) async throws {
        guard !conversations.isEmpty else { return }
        try queue.sync {
            try inTransaction {
                for conversation in conversations {
                    try upsertConversationInternal(conversation)
                }
            }
        }
        postChange(scope: .conversations)
    }

    public func clearUnread(conversationId: String, now: Int64) async throws {
        try queue.sync {
            try executePrepared(
                "UPDATE im_conversations SET unread_count = 0, updated_at = ? WHERE id = ?;",
                bindings: [.integer(now), .text(conversationId)]
            )
        }
        postChange(scope: .conversations, conversationID: conversationId)
    }

    public func setPinned(conversationId: String, pinned: Bool, now: Int64) async throws {
        try queue.sync {
            try executePrepared(
                "UPDATE im_conversations SET pinned = ?, updated_at = ? WHERE id = ?;",
                bindings: [.integer(pinned ? 1 : 0), .integer(now), .text(conversationId)]
            )
        }
        postChange(scope: .conversations, conversationID: conversationId)
    }

    public func setMuted(conversationId: String, muted: Bool, now: Int64) async throws {
        try queue.sync {
            try executePrepared(
                "UPDATE im_conversations SET muted = ?, updated_at = ? WHERE id = ?;",
                bindings: [.integer(muted ? 1 : 0), .integer(now), .text(conversationId)]
            )
        }
        postChange(scope: .conversations, conversationID: conversationId)
    }

    /// Deletes a conversation; its messages are removed via FK cascade.
    public func deleteConversation(id: String) async throws {
        try queue.sync {
            try executePrepared("DELETE FROM im_conversations WHERE id = ?;", bindings: [.text(id)])
        }
        postChange(scope: .conversations, conversationID: id)
    }

    // MARK: - Messages

    public func messages(conversationId: String) async throws -> [ImMessage] {
        try queue.sync {
            try queryMessages(
                sql: "SELECT * FROM im_messages WHERE conversation_id = ? ORDER BY created_at ASC, seq ASC;",
                bindings: [.text(conversationId)]
            )
        }
    }

    public func message(id: String) async throws -> ImMessage? {
        try queue.sync {
            try messageInternal(id: id)
        }
    }

    /// Idempotent by message `id`: an existing row is updated in place keeping its `seq`
    /// so in-conversation ordering stays stable; a new row gets the next sequence.
    @discardableResult
    public func upsertMessage(_ message: ImMessage) async throws -> ImMessage {
        let saved = try queue.sync {
            try upsertMessageInternal(message)
        }
        postChange(scope: .messages, conversationID: message.conversationId)
        return saved
    }

    /// Ack arrived: replace the optimistic temp id with the server id in place (seq unchanged).
    public func replaceMessageId(oldId: String, newId: String, status: ImMessageStatus) async throws {
        let conversationID = try queue.sync {
            let conversationID = try messageInternal(id: oldId)?.conversationId
            try executePrepared(
                "UPDATE im_messages SET id = ?, status = ? WHERE id = ?;",
                bindings: [.text(newId), .text(status.rawValue), .text(oldId)]
            )
            return conversationID
        }
        postChange(scope: .messages, conversationID: conversationID)
    }

    public func updateMessageStatus(id: String, status: ImMessageStatus) async throws {
        let conversationID = try queue.sync {
            let conversationID = try messageInternal(id: id)?.conversationId
            try executePrepared(
                "UPDATE im_messages SET status = ? WHERE id = ?;",
                bindings: [.text(status.rawValue), .text(id)]
            )
            return conversationID
        }
        postChange(scope: .messages, conversationID: conversationID)
    }

    /// Group echo arrived before the ack: the server id row already exists, drop the temp row.
    public func deleteMessage(id: String) async throws {
        let conversationID = try queue.sync {
            let conversationID = try messageInternal(id: id)?.conversationId
            try executePrepared("DELETE FROM im_messages WHERE id = ?;", bindings: [.text(id)])
            return conversationID
        }
        postChange(scope: .messages, conversationID: conversationID)
    }

    /// Peer read receipt: mark every message from `senderId` in the conversation READ.
    public func markSenderMessagesRead(conversationId: String, senderId: Int64) async throws {
        try queue.sync {
            try executePrepared(
                "UPDATE im_messages SET status = 'READ' WHERE conversation_id = ? AND sender_id = ? AND status != 'FAILED';",
                bindings: [.text(conversationId), .integer(senderId)]
            )
        }
        postChange(scope: .messages, conversationID: conversationId)
    }

    /// `before_id` paging cursor: oldest cached server message id (optimistic temp
    /// messages in SENDING/FAILED never participate in paging).
    public func oldestServerMessageId(conversationId: String) async throws -> String? {
        try queue.sync {
            try queryMessages(
                sql: """
                    SELECT * FROM im_messages WHERE conversation_id = ?
                    AND status NOT IN ('SENDING', 'FAILED') ORDER BY created_at ASC, seq ASC LIMIT 1;
                    """,
                bindings: [.text(conversationId)]
            ).first?.id
        }
    }

    /// Startup recovery: optimistic messages left dangling by a killed process fail out.
    public func markSendingFailed() async throws {
        try queue.sync {
            try executeInternal("UPDATE im_messages SET status = 'FAILED' WHERE status = 'SENDING';")
        }
        postChange(scope: .messages)
    }

    // MARK: - Friends

    public func loadFriends() async throws -> [ImFriend] {
        try queue.sync {
            try queryFriends(sql: "SELECT * FROM im_friends ORDER BY username ASC;", bindings: [])
        }
    }

    public func friend(userId: Int64) async throws -> ImFriend? {
        try queue.sync {
            try queryFriends(sql: "SELECT * FROM im_friends WHERE user_id = ? LIMIT 1;", bindings: [.integer(userId)]).first
        }
    }

    public func friendByPerson(personProfileID: String) async throws -> ImFriend? {
        try queue.sync {
            try queryFriends(sql: "SELECT * FROM im_friends WHERE person_profile_id = ? LIMIT 1;", bindings: [.text(personProfileID)]).first
        }
    }

    public func upsertFriends(_ friends: [ImFriend]) async throws {
        guard !friends.isEmpty else { return }
        try queue.sync {
            try inTransaction {
                for friend in friends {
                    try executePrepared(
                        """
                        INSERT OR REPLACE INTO im_friends (
                            user_id, username, nickname, email, avatar, person_profile_id, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?);
                        """,
                        bindings: [
                            .integer(friend.userId),
                            .text(friend.username),
                            .text(friend.nickname),
                            .text(friend.email),
                            .text(friend.avatar),
                            .optionalText(friend.personProfileID),
                            .integer(friend.updatedAt)
                        ]
                    )
                }
            }
        }
        postChange(scope: .friends)
    }

    /// Friend ↔ person binding (pass nil to unbind).
    public func bindFriendPerson(userId: Int64, personProfileID: String?, now: Int64) async throws {
        try queue.sync {
            try executePrepared(
                "UPDATE im_friends SET person_profile_id = ?, updated_at = ? WHERE user_id = ?;",
                bindings: [.optionalText(personProfileID), .integer(now), .integer(userId)]
            )
        }
        postChange(scope: .friends)
    }

    public func deleteFriend(userId: Int64) async throws {
        try queue.sync {
            try executePrepared("DELETE FROM im_friends WHERE user_id = ?;", bindings: [.integer(userId)])
        }
        postChange(scope: .friends)
    }

    /// Full-refresh convergence: drop local friends missing from the server list.
    public func pruneFriends(keepUserIds: [Int64]) async throws {
        try queue.sync {
            if keepUserIds.isEmpty {
                try executeInternal("DELETE FROM im_friends;")
            } else {
                let placeholders = Array(repeating: "?", count: keepUserIds.count).joined(separator: ", ")
                try executePrepared(
                    "DELETE FROM im_friends WHERE user_id NOT IN (\(placeholders));",
                    bindings: keepUserIds.map { .integer($0) }
                )
            }
        }
        postChange(scope: .friends)
    }

    // MARK: - Friend requests

    public func loadFriendRequests() async throws -> [ImFriendRequest] {
        try queue.sync {
            try queryFriendRequests(sql: "SELECT * FROM im_friend_requests ORDER BY created_at DESC, id DESC;", bindings: [])
        }
    }

    public func upsertFriendRequests(_ requests: [ImFriendRequest]) async throws {
        guard !requests.isEmpty else { return }
        try queue.sync {
            try inTransaction {
                for request in requests {
                    try executePrepared(
                        """
                        INSERT OR REPLACE INTO im_friend_requests (
                            id, sender_id, receiver_id, message, status,
                            sender_username, sender_nickname, sender_avatar,
                            receiver_username, receiver_nickname, created_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                        """,
                        bindings: [
                            .integer(request.id),
                            .integer(request.senderId),
                            .integer(request.receiverId),
                            .text(request.message),
                            .text(request.status),
                            .text(request.senderUsername),
                            .text(request.senderNickname),
                            .text(request.senderAvatar),
                            .text(request.receiverUsername),
                            .text(request.receiverNickname),
                            .integer(request.createdAt)
                        ]
                    )
                }
            }
        }
        postChange(scope: .friendRequests)
    }

    // MARK: - Forwarding aliases

    /// Token reuse: one sender gets exactly one alias token across forwards.
    public func aliasBySender(senderId: Int64) async throws -> ImForwardAlias? {
        try queue.sync {
            try queryAliases(sql: "SELECT * FROM im_forward_alias WHERE sender_id = ? LIMIT 1;", bindings: [.integer(senderId)]).first
        }
    }

    public func aliasByToken(_ token: String) async throws -> ImForwardAlias? {
        try queue.sync {
            try queryAliases(sql: "SELECT * FROM im_forward_alias WHERE alias_token = ? LIMIT 1;", bindings: [.text(token)]).first
        }
    }

    /// Synchronous token lookup for the projection path: the Memory OS projection
    /// pipeline is synchronous, so the alias rewriter cannot await the async API.
    public func forwardAlias(token: String) throws -> ImForwardAlias? {
        try queue.sync {
            try queryAliases(sql: "SELECT * FROM im_forward_alias WHERE alias_token = ? LIMIT 1;", bindings: [.text(token)]).first
        }
    }

    public func aliasesForPerson(personProfileID: String) async throws -> [ImForwardAlias] {
        try queue.sync {
            try queryAliases(sql: "SELECT * FROM im_forward_alias WHERE person_profile_id = ?;", bindings: [.text(personProfileID)])
        }
    }

    public func insertAlias(_ alias: ImForwardAlias) async throws {
        try queue.sync {
            try executePrepared(
                """
                INSERT OR REPLACE INTO im_forward_alias (
                    alias_token, sender_id, im_conversation_id, person_profile_id, display_name, created_at
                ) VALUES (?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(alias.aliasToken),
                    .integer(alias.senderId),
                    .text(alias.imConversationId),
                    .text(alias.personProfileID),
                    .text(alias.displayName),
                    .integer(alias.createdAt)
                ]
            )
        }
        postChange(scope: .forwardAliases)
    }

    // MARK: - Cleanup

    public func clearConversations() async throws {
        try queue.sync {
            try executeInternal("DELETE FROM im_conversations;")
        }
        postChange(scope: .conversations)
    }

    public func clearFriends() async throws {
        try queue.sync {
            try executeInternal("DELETE FROM im_friends;")
        }
        postChange(scope: .friends)
    }

    public func clearFriendRequests() async throws {
        try queue.sync {
            try executeInternal("DELETE FROM im_friend_requests;")
        }
        postChange(scope: .friendRequests)
    }

    public func clearForwardAliases() async throws {
        try queue.sync {
            try executeInternal("DELETE FROM im_forward_alias;")
        }
        postChange(scope: .forwardAliases)
    }

    // MARK: - Schema

    private static func configurePragmas(db: OpaquePointer) throws {
        try execute("PRAGMA journal_mode = WAL;", db: db)
        try execute("PRAGMA synchronous = NORMAL;", db: db)
        try execute("PRAGMA busy_timeout = 5000;", db: db)
        try execute("PRAGMA temp_store = MEMORY;", db: db)
        try execute("PRAGMA cache_size = -8000;", db: db)
        try execute("PRAGMA foreign_keys = ON;", db: db)
    }

    private static func createTables(db: OpaquePointer) throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS im_conversations (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                peer_user_id INTEGER,
                group_id TEXT,
                title TEXT NOT NULL,
                avatar TEXT NOT NULL,
                last_message_preview TEXT NOT NULL,
                last_message_at INTEGER NOT NULL,
                unread_count INTEGER NOT NULL,
                pinned INTEGER NOT NULL,
                muted INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
        """, db: db)
        try execute("""
            CREATE TABLE IF NOT EXISTS im_messages (
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT NOT NULL,
                conversation_id TEXT NOT NULL,
                sender_id INTEGER NOT NULL,
                sender_name TEXT NOT NULL,
                sender_avatar TEXT NOT NULL,
                message_type TEXT NOT NULL,
                content TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                extra_json TEXT NOT NULL,
                FOREIGN KEY(conversation_id) REFERENCES im_conversations(id) ON DELETE CASCADE
            );
        """, db: db)
        try execute("""
            CREATE TABLE IF NOT EXISTS im_friends (
                user_id INTEGER PRIMARY KEY,
                username TEXT NOT NULL,
                nickname TEXT NOT NULL,
                email TEXT NOT NULL,
                avatar TEXT NOT NULL,
                person_profile_id TEXT,
                updated_at INTEGER NOT NULL
            );
        """, db: db)
        try execute("""
            CREATE TABLE IF NOT EXISTS im_friend_requests (
                id INTEGER PRIMARY KEY,
                sender_id INTEGER NOT NULL,
                receiver_id INTEGER NOT NULL,
                message TEXT NOT NULL,
                status TEXT NOT NULL,
                sender_username TEXT NOT NULL,
                sender_nickname TEXT NOT NULL,
                sender_avatar TEXT NOT NULL,
                receiver_username TEXT NOT NULL,
                receiver_nickname TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
        """, db: db)
        try execute("""
            CREATE TABLE IF NOT EXISTS im_forward_alias (
                alias_token TEXT PRIMARY KEY,
                sender_id INTEGER NOT NULL,
                im_conversation_id TEXT NOT NULL,
                person_profile_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
        """, db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_im_conversations_last_message_at ON im_conversations(last_message_at);", db: db)
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_im_messages_id ON im_messages(id);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_im_messages_conversation ON im_messages(conversation_id);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_im_friends_person ON im_friends(person_profile_id);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_im_friend_requests_status ON im_friend_requests(status);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_im_forward_alias_sender ON im_forward_alias(sender_id);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_im_forward_alias_person ON im_forward_alias(person_profile_id);", db: db)
    }

    // MARK: - Internal writes

    private func upsertConversationInternal(_ conversation: ImConversation) throws {
        // ON CONFLICT DO UPDATE (not INSERT OR REPLACE): REPLACE deletes the old row
        // first, which would cascade-delete every message of the conversation.
        try executePrepared(
            """
            INSERT INTO im_conversations (
                id, kind, peer_user_id, group_id, title, avatar, last_message_preview,
                last_message_at, unread_count, pinned, muted, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind, peer_user_id = excluded.peer_user_id,
                group_id = excluded.group_id, title = excluded.title, avatar = excluded.avatar,
                last_message_preview = excluded.last_message_preview,
                last_message_at = excluded.last_message_at, unread_count = excluded.unread_count,
                pinned = excluded.pinned, muted = excluded.muted, updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(conversation.id),
                .text(conversation.kind.rawValue),
                .optionalInteger(conversation.peerUserId),
                .optionalText(conversation.groupId),
                .text(conversation.title),
                .text(conversation.avatar),
                .text(conversation.lastMessagePreview),
                .integer(conversation.lastMessageAt),
                .integer(Int64(conversation.unreadCount)),
                .integer(conversation.pinned ? 1 : 0),
                .integer(conversation.muted ? 1 : 0),
                .integer(conversation.updatedAt)
            ]
        )
    }

    private func upsertMessageInternal(_ message: ImMessage) throws -> ImMessage {
        if let existing = try messageInternal(id: message.id) {
            var updated = message
            updated.seq = existing.seq
            try executePrepared(
                """
                UPDATE im_messages SET conversation_id = ?, sender_id = ?, sender_name = ?, sender_avatar = ?,
                    message_type = ?, content = ?, status = ?, created_at = ?, extra_json = ?
                WHERE seq = ?;
                """,
                bindings: [
                    .text(updated.conversationId),
                    .integer(updated.senderId),
                    .text(updated.senderName),
                    .text(updated.senderAvatar),
                    .text(updated.messageType),
                    .text(updated.content),
                    .text(updated.status.rawValue),
                    .integer(updated.createdAt),
                    .text(updated.extraJson),
                    .integer(existing.seq)
                ]
            )
            return updated
        }

        try executePrepared(
            """
            INSERT INTO im_messages (
                id, conversation_id, sender_id, sender_name, sender_avatar,
                message_type, content, status, created_at, extra_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(message.id),
                .text(message.conversationId),
                .integer(message.senderId),
                .text(message.senderName),
                .text(message.senderAvatar),
                .text(message.messageType),
                .text(message.content),
                .text(message.status.rawValue),
                .integer(message.createdAt),
                .text(message.extraJson)
            ]
        )
        var inserted = message
        inserted.seq = sqlite3_last_insert_rowid(db)
        return inserted
    }

    private func messageInternal(id: String) throws -> ImMessage? {
        try queryMessages(sql: "SELECT * FROM im_messages WHERE id = ? LIMIT 1;", bindings: [.text(id)]).first
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        try executeInternal("BEGIN TRANSACTION;")
        do {
            try body()
            try executeInternal("COMMIT;")
        } catch {
            try? executeInternal("ROLLBACK;")
            throw error
        }
    }

    private func postChange(scope: ImStoreChangeScope, conversationID: String? = nil) {
        var userInfo: [String: Any] = [ImStoreChangeNotificationUserInfoKey.scope: scope.rawValue]
        if let conversationID {
            userInfo[ImStoreChangeNotificationUserInfoKey.conversationID] = conversationID
        }
        NotificationCenter.default.post(name: .connorImStoreDidChange, object: self, userInfo: userInfo)
    }

    // MARK: - Row readers

    private func queryConversations(sql: String, bindings: [Binding]) throws -> [ImConversation] {
        try queryRows(sql: sql, bindings: bindings) { statement in
            ImConversation(
                id: columnText(statement, 0),
                kind: ImConversationKind(rawValue: columnText(statement, 1)) ?? .peer,
                peerUserId: columnOptionalInt64(statement, 2),
                groupId: columnOptionalText(statement, 3),
                title: columnText(statement, 4),
                avatar: columnText(statement, 5),
                lastMessagePreview: columnText(statement, 6),
                lastMessageAt: sqlite3_column_int64(statement, 7),
                unreadCount: Int(sqlite3_column_int64(statement, 8)),
                pinned: sqlite3_column_int64(statement, 9) != 0,
                muted: sqlite3_column_int64(statement, 10) != 0,
                updatedAt: sqlite3_column_int64(statement, 11)
            )
        }
    }

    private func queryMessages(sql: String, bindings: [Binding]) throws -> [ImMessage] {
        try queryRows(sql: sql, bindings: bindings) { statement in
            ImMessage(
                seq: sqlite3_column_int64(statement, 0),
                id: columnText(statement, 1),
                conversationId: columnText(statement, 2),
                senderId: sqlite3_column_int64(statement, 3),
                senderName: columnText(statement, 4),
                senderAvatar: columnText(statement, 5),
                messageType: columnText(statement, 6),
                content: columnText(statement, 7),
                status: ImMessageStatus(rawValue: columnText(statement, 8)) ?? .sent,
                createdAt: sqlite3_column_int64(statement, 9),
                extraJson: columnText(statement, 10)
            )
        }
    }

    private func queryFriends(sql: String, bindings: [Binding]) throws -> [ImFriend] {
        try queryRows(sql: sql, bindings: bindings) { statement in
            ImFriend(
                userId: sqlite3_column_int64(statement, 0),
                username: columnText(statement, 1),
                nickname: columnText(statement, 2),
                email: columnText(statement, 3),
                avatar: columnText(statement, 4),
                personProfileID: columnOptionalText(statement, 5),
                updatedAt: sqlite3_column_int64(statement, 6)
            )
        }
    }

    private func queryFriendRequests(sql: String, bindings: [Binding]) throws -> [ImFriendRequest] {
        try queryRows(sql: sql, bindings: bindings) { statement in
            ImFriendRequest(
                id: sqlite3_column_int64(statement, 0),
                senderId: sqlite3_column_int64(statement, 1),
                receiverId: sqlite3_column_int64(statement, 2),
                message: columnText(statement, 3),
                status: columnText(statement, 4),
                senderUsername: columnText(statement, 5),
                senderNickname: columnText(statement, 6),
                senderAvatar: columnText(statement, 7),
                receiverUsername: columnText(statement, 8),
                receiverNickname: columnText(statement, 9),
                createdAt: sqlite3_column_int64(statement, 10)
            )
        }
    }

    private func queryAliases(sql: String, bindings: [Binding]) throws -> [ImForwardAlias] {
        try queryRows(sql: sql, bindings: bindings) { statement in
            ImForwardAlias(
                aliasToken: columnText(statement, 0),
                senderId: sqlite3_column_int64(statement, 1),
                imConversationId: columnText(statement, 2),
                personProfileID: columnText(statement, 3),
                displayName: columnText(statement, 4),
                createdAt: sqlite3_column_int64(statement, 5)
            )
        }
    }

    // MARK: - SQLite plumbing

    private enum Binding {
        case text(String)
        case optionalText(String?)
        case integer(Int64)
        case optionalInteger(Int64?)
    }

    private func queryRows<Row>(sql: String, bindings: [Binding], read: (OpaquePointer) -> Row) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [Row] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw lastError() }
            rows.append(read(statement))
        }
        return rows
    }

    private func executePrepared(_ sql: String, bindings: [Binding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .optionalText(let value):
                if let value {
                    result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .optionalInteger(let value):
                if let value {
                    result = sqlite3_bind_int64(statement, index, value)
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            }
            guard result == SQLITE_OK else { throw lastError() }
        }
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func columnOptionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return columnText(statement, index)
    }

    private func columnOptionalInt64(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private static func execute(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw SQLiteImStoreError.sqlite(message)
        }
    }

    private func executeInternal(_ sql: String) throws {
        try Self.execute(sql, db: db)
    }

    private func lastError() -> SQLiteImStoreError {
        SQLiteImStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
