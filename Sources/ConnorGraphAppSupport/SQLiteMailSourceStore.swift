import Foundation
import SQLite3
import ConnorGraphCore

// MARK: - Error

public enum SQLiteMailSourceStoreError: Error, Sendable, CustomStringConvertible {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let m): "SQLiteMailSourceStore.openFailed: \(m)"
        case .executeFailed(let m): "SQLiteMailSourceStore.executeFailed: \(m)"
        case .prepareFailed(let m): "SQLiteMailSourceStore.prepareFailed: \(m)"
        case .stepFailed(let m): "SQLiteMailSourceStore.stepFailed: \(m)"
        case .decodeFailed(let m): "SQLiteMailSourceStore.decodeFailed: \(m)"
        }
    }
}

private struct MailSQLitePageCursor: Codable {
    var date: Date
    var id: String

    func encode() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self).base64EncodedString()
    }

    static func decode(_ raw: String) throws -> Self {
        guard let data = Data(base64Encoded: raw) else {
            throw SQLiteMailSourceStoreError.decodeFailed("Invalid mail page cursor")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(Self.self, from: data) }
        catch { throw SQLiteMailSourceStoreError.decodeFailed("Invalid mail page cursor") }
    }
}

// MARK: - SQLiteMailSourceStore

public final class SQLiteMailSourceStore: MailStoreProtocol, IncrementalMailSyncSource, @unchecked Sendable {

    // MARK: Properties

    private let db: OpaquePointer
    private let lock = NSRecursiveLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let searchService: (any NativeSourceSearchBackend)?
    private var hasPrimedSearchIndex: Bool = false

    // MARK: Init

    public init(databaseURL: URL, searchService: (any NativeSourceSearchBackend)? = nil) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else {
            throw SQLiteMailSourceStoreError.openFailed("Cannot open \(databaseURL.path)")
        }
        self.db = db

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.searchService = searchService

        try configurePragmas()
        try transaction { try createTables() }
    }

    deinit {
        lock.lock()
        sqlite3_close(db)
        lock.unlock()
    }

    // MARK: Pragmas & Schema

    private func configurePragmas() throws {
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try execute("PRAGMA busy_timeout = 5000;")
        try execute("PRAGMA temp_store = MEMORY;")
        try execute("PRAGMA cache_size = -8000;") // 8MB
    }

    private func createTables() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS mail_account_sync_deletions (id TEXT PRIMARY KEY, deleted_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS mail_accounts (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                email TEXT NOT NULL DEFAULT '',
                provider TEXT,
                updated_at TEXT NOT NULL,
                raw_json TEXT NOT NULL
            );
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS mail_mailboxes (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                name TEXT NOT NULL,
                path TEXT NOT NULL,
                role TEXT,
                message_count INTEGER DEFAULT 0,
                unread_count INTEGER DEFAULT 0,
                last_synced_at TEXT,
                raw_json TEXT NOT NULL,
                FOREIGN KEY (account_id) REFERENCES mail_accounts(id) ON DELETE CASCADE
            );
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS mail_messages (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                mailbox_id TEXT NOT NULL,
                uid TEXT NOT NULL,
                subject TEXT NOT NULL DEFAULT '',
                from_email TEXT NOT NULL DEFAULT '',
                from_name TEXT,
                date TEXT NOT NULL,
                snippet TEXT NOT NULL DEFAULT '',
                is_read INTEGER DEFAULT 0,
                is_flagged INTEGER DEFAULT 0,
                is_answered INTEGER DEFAULT 0,
                is_deleted INTEGER DEFAULT 0,
                has_attachments INTEGER DEFAULT 0,
                body_plain TEXT,
                raw_json TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
        """)

        let columns = try querySQL("PRAGMA table_info(mail_messages)").map { $0[1] }
        if !columns.contains("body_available") {
            try execute("ALTER TABLE mail_messages ADD COLUMN body_available INTEGER NOT NULL DEFAULT 0")
            try execute("""
                UPDATE mail_messages SET body_available=1 WHERE length(COALESCE(body_plain,''))>0
                  OR length(COALESCE(json_extract(raw_json,'$.body.htmlText.text'),''))>0
                  OR length(COALESCE(json_extract(raw_json,'$.body.redactedPreview'),''))>0;
            """)
        }
        try execute("CREATE INDEX IF NOT EXISTS idx_mail_backfill ON mail_messages(body_available, date DESC)")
        try execute("CREATE TABLE IF NOT EXISTS mail_body_backfill_retry (id TEXT PRIMARY KEY, failures INTEGER NOT NULL, retry_at REAL NOT NULL)")
        try execute("""
            CREATE TABLE IF NOT EXISTS mail_sync_clock (singleton INTEGER PRIMARY KEY CHECK(singleton=1), store_id TEXT NOT NULL, revision INTEGER NOT NULL);
            INSERT OR IGNORE INTO mail_sync_clock VALUES (1, '\(UUID().uuidString)', 0);
            CREATE TABLE IF NOT EXISTS mail_sync_changes (id TEXT PRIMARY KEY, revision INTEGER NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_mail_sync_revision ON mail_sync_changes(revision);
            CREATE TABLE IF NOT EXISTS mail_sync_imports (source_id TEXT PRIMARY KEY, revision INTEGER NOT NULL);
            INSERT OR IGNORE INTO mail_sync_changes SELECT id, (SELECT revision FROM mail_sync_clock WHERE singleton=1) FROM mail_messages;
        """)
        for (operation, row) in [("INSERT", "NEW"), ("UPDATE", "NEW"), ("DELETE", "OLD")] {
            try execute("""
                CREATE TRIGGER IF NOT EXISTS mail_sync_\(operation.lowercased()) AFTER \(operation) ON mail_messages BEGIN
                    UPDATE mail_sync_clock SET revision=revision+1 WHERE singleton=1;
                    INSERT INTO mail_sync_changes VALUES (\(row).id, (SELECT revision FROM mail_sync_clock WHERE singleton=1))
                    ON CONFLICT(id) DO UPDATE SET revision=excluded.revision;
                END;
            """)
        }
        // Mail identity depends on account address and mailbox UIDValidity/path,
        // not the frequently updated sync-health timestamps.
        for operation in ["INSERT", "UPDATE"] {
            let condition = operation == "UPDATE" ? "WHEN OLD.email IS NOT NEW.email" : ""
            try execute("""
                CREATE TRIGGER IF NOT EXISTS mail_sync_account_\(operation.lowercased()) AFTER \(operation) ON mail_accounts \(condition) BEGIN
                    UPDATE mail_sync_clock SET revision=revision+1 WHERE singleton=1;
                    INSERT INTO mail_sync_changes SELECT id, (SELECT revision FROM mail_sync_clock WHERE singleton=1) FROM mail_messages WHERE account_id=NEW.id
                    ON CONFLICT(id) DO UPDATE SET revision=excluded.revision;
                END;
            """)
            let mailboxCondition = operation == "UPDATE" ? "WHEN OLD.path IS NOT NEW.path OR OLD.role IS NOT NEW.role OR OLD.account_id IS NOT NEW.account_id OR json_extract(OLD.raw_json, '$.status.syncCursor.uidValidity') IS NOT json_extract(NEW.raw_json, '$.status.syncCursor.uidValidity')" : ""
            try execute("""
                CREATE TRIGGER IF NOT EXISTS mail_sync_mailbox_\(operation.lowercased()) AFTER \(operation) ON mail_mailboxes \(mailboxCondition) BEGIN
                    UPDATE mail_sync_clock SET revision=revision+1 WHERE singleton=1;
                    INSERT INTO mail_sync_changes SELECT id, (SELECT revision FROM mail_sync_clock WHERE singleton=1) FROM mail_messages WHERE mailbox_id=NEW.id
                    ON CONFLICT(id) DO UPDATE SET revision=excluded.revision;
                END;
            """)
        }

        try execute("CREATE INDEX IF NOT EXISTS idx_msg_account ON mail_messages(account_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_msg_mailbox ON mail_messages(mailbox_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_msg_date ON mail_messages(date DESC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_msg_date_page ON mail_messages(date DESC, id ASC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_msg_account_page ON mail_messages(account_id, date DESC, id ASC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_msg_mailbox_page ON mail_messages(mailbox_id, date DESC, id ASC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_msg_uid ON mail_messages(account_id, uid);")
    }

    func syncSnapshot(storeID: String?, after revision: Int64?) throws -> MailSyncSnapshot {
        lock.lock(); defer { lock.unlock() }
        try executeUnlocked("SAVEPOINT mail_sync_snapshot;")
        defer { try? executeUnlocked("RELEASE mail_sync_snapshot;") }
        let clock = try querySQLUnlocked("SELECT store_id, revision FROM mail_sync_clock WHERE singleton=1")[0]
        let upper = Int64(clock[1])!
        let lower = storeID == clock[0] && revision != nil && revision! >= 0 && revision! <= upper ? revision! : -1
        let ids = try querySQLUnlocked("SELECT id FROM mail_sync_changes WHERE revision > \(lower) AND revision <= \(upper) ORDER BY id").map { $0[0] }
        return MailSyncSnapshot(storeID: clock[0], revision: upper, messageIDs: ids)
    }

    func seedSyncIDs(_ ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let values = ids.map { "('\(esc($0))', (SELECT revision FROM mail_sync_clock WHERE singleton=1))" }.joined(separator: ",")
        try execute("INSERT OR IGNORE INTO mail_sync_changes VALUES \(values)")
    }

    func recordSyncChange(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        try executeUnlocked("SAVEPOINT shared_mail_change;")
        do {
            try executeUnlocked("""
                UPDATE mail_sync_clock SET revision=revision+1 WHERE singleton=1;
                INSERT INTO mail_sync_changes VALUES ('\(esc(id))', (SELECT revision FROM mail_sync_clock WHERE singleton=1))
                ON CONFLICT(id) DO UPDATE SET revision=excluded.revision;
            """)
            try executeUnlocked("RELEASE shared_mail_change;")
        } catch {
            try? executeUnlocked("ROLLBACK TO shared_mail_change; RELEASE shared_mail_change;")
            throw error
        }
    }

    func importedRevision(sourceID: String) throws -> Int64? {
        try querySQL("SELECT revision FROM mail_sync_imports WHERE source_id='\(esc(sourceID))'").first.flatMap { Int64($0[0]) }
    }

    func acknowledgeImport(_ snapshot: MailSyncSnapshot) throws {
        try execute("INSERT INTO mail_sync_imports VALUES ('\(esc(snapshot.storeID))', \(snapshot.revision)) ON CONFLICT(source_id) DO UPDATE SET revision=excluded.revision")
    }

    // MARK: - MailSourceRepository

    public func listAccounts() async throws -> [MailAccount] {
        let rows = try querySQL("SELECT raw_json FROM mail_accounts ORDER BY display_name COLLATE NOCASE")
        return try rows.map { try decoder.decode(MailAccount.self, from: Data($0[0].utf8)) }
    }

    public func saveAccount(_ account: MailAccount) async throws {
        let data = try encoder.encode(account)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        try execute("""
            INSERT INTO mail_accounts (id, display_name, email, provider, updated_at, raw_json)
            VALUES ('\(esc(account.id.rawValue))', '\(esc(account.displayName))', '\(esc(account.identities.first?.address.email ?? ""))', '\(esc(account.provider.rawValue))', '\(esc(iso8601(account.updatedAt)))', '\(esc(json))')
            ON CONFLICT(id) DO UPDATE SET display_name=excluded.display_name, email=excluded.email, provider=excluded.provider, updated_at=excluded.updated_at, raw_json=excluded.raw_json
        """)
    }

    public func account(id: MailAccountID) async throws -> MailAccount? {
        let rows = try querySQL("SELECT raw_json FROM mail_accounts WHERE id = '\(esc(id.rawValue))' LIMIT 1")
        guard let row = rows.first else { return nil }
        return try decoder.decode(MailAccount.self, from: Data(row[0].utf8))
    }

    public func pendingAccountDeletions() async throws -> [String:Int64] {
        Dictionary(uniqueKeysWithValues: try querySQL("SELECT id, deleted_at FROM mail_account_sync_deletions").map { ($0[0], Int64($0[1]) ?? 0) })
    }
    public func clearAccountDeletion(id: MailAccountID) async throws {
        try execute("DELETE FROM mail_account_sync_deletions WHERE id = '\(esc(id.rawValue))'")
    }
    public func applyRemoteAccountDelete(id: MailAccountID) async throws {
        try execute("DELETE FROM mail_accounts WHERE id = '\(esc(id.rawValue))'")
    }
    public func deleteAccount(id: MailAccountID) async throws {
        try execute("INSERT OR REPLACE INTO mail_account_sync_deletions (id, deleted_at) VALUES ('\(esc(id.rawValue))', \(Int64(Date().timeIntervalSince1970 * 1_000)))")
        // 邮箱/邮件缓存随 mail_mailboxes 的 ON DELETE CASCADE 一并清理；
        // 凭证由 credential store 单独清理，不经此路径。
        try execute("DELETE FROM mail_accounts WHERE id = '\(esc(id.rawValue))'")
    }

    // MARK: - MailSourceCache

    public func listMailboxes(accountID: MailAccountID) async throws -> [MailMailbox] {
        let rows = try querySQL("SELECT raw_json FROM mail_mailboxes WHERE account_id = '\(esc(accountID.rawValue))' ORDER BY path COLLATE NOCASE")
        return try rows.map { try decoder.decode(MailMailbox.self, from: Data($0[0].utf8)) }
    }

    public func saveMailbox(_ mailbox: MailMailbox) async throws {
        let data = try encoder.encode(mailbox)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        try execute("""
            INSERT INTO mail_mailboxes (id, account_id, name, path, role, message_count, unread_count, last_synced_at, raw_json)
            VALUES ('\(esc(mailbox.id.rawValue))', '\(esc(mailbox.accountID.rawValue))', '\(esc(mailbox.name))', '\(esc(mailbox.path))', '\(esc(mailbox.role.rawValue))', \(mailbox.status.messageCount), \(mailbox.status.unreadCount), \(mailbox.status.lastSyncedAt.map { "'\(esc(iso8601($0)))'" } ?? "NULL"), '\(esc(json))')
            ON CONFLICT(id) DO UPDATE SET account_id=excluded.account_id, name=excluded.name, path=excluded.path, role=excluded.role, message_count=excluded.message_count, unread_count=excluded.unread_count, last_synced_at=excluded.last_synced_at, raw_json=excluded.raw_json
        """)
    }

    public func saveMessage(_ message: MailMessageDetail) async throws {
        guard try saveMessageInternal(message) else { return }
        AppAccountSyncSignal.postLocalDataDidChange()
        try await searchService?.upsert([NativeSourceSearchAdapters.mailDocument(from: message)])
    }

    public func saveMessagesBatch(_ messages: [MailMessageDetail]) async throws {
        guard !messages.isEmpty else { return }
        let changed = try transaction {
            try messages.filter { try saveMessageInternal($0) }
        }
        guard !changed.isEmpty else { return }
        AppAccountSyncSignal.postLocalDataDidChange()
        try await searchService?.upsert(changed.map(NativeSourceSearchAdapters.mailDocument(from:)))
    }

    public func searchMessages(query: String, accountID: MailAccountID?) async throws -> [MailMessageSummary] {
        try await searchMessages(query: query, accountID: accountID, temporalFilter: nil, temporalSort: .relevanceThenTimeDesc, limit: Int.max)
    }

    public func recentMessages(accountID: MailAccountID?, direction: MailMessageDirectionFilter, limit: Int) async throws -> [MailMessageSummary] {
        let limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        var sql = """
            SELECT m.raw_json
            FROM mail_messages m
            LEFT JOIN mail_mailboxes b ON m.mailbox_id = b.id
            WHERE 1=1
        """
        if let accountID { sql += " AND m.account_id = '\(esc(accountID.rawValue))'" }
        switch direction {
        case .all:
            break
        case .received:
            sql += " AND COALESCE(b.role, '') != 'sent'"
        case .sent:
            sql += " AND b.role = 'sent'"
        }
        sql += " ORDER BY m.date DESC, m.id ASC LIMIT \(limit)"
        let rows = try querySQL(sql)
        return try rows.map { try decoder.decode(MailMessageDetail.self, from: Data($0[0].utf8)).summary }
    }

    public func messagePage(_ request: MailMessagePageRequest) async throws -> MailMessagePage {
        let cursor = try request.cursor.map(MailSQLitePageCursor.decode)
        var sql = """
            SELECT m.raw_json
            FROM mail_messages m
            LEFT JOIN mail_mailboxes b ON m.mailbox_id = b.id
            WHERE m.is_deleted = 0
        """
        if let accountID = request.accountID { sql += " AND m.account_id = '\(esc(accountID.rawValue))'" }
        if let mailboxID = request.mailboxID { sql += " AND m.mailbox_id = '\(esc(mailboxID.rawValue))'" }
        switch request.direction {
        case .all: break
        case .received: sql += " AND COALESCE(b.role, '') != 'sent'"
        case .sent: sql += " AND b.role = 'sent'"
        }
        let normalized = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            let term = escLike(normalized)
            sql += " AND (m.subject LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR m.snippet LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR m.from_email LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR COALESCE(m.from_name, '') LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR COALESCE(m.body_plain, '') LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE)"
        }
        if let cursor {
            let date = esc(iso8601(cursor.date))
            sql += " AND (m.date < '\(date)' OR (m.date = '\(date)' AND m.id > '\(esc(cursor.id))'))"
        }
        sql += " ORDER BY m.date DESC, m.id ASC LIMIT \(request.pageSize + 1)"
        let rows = try querySQL(sql)
        let details = try rows.map { try decoder.decode(MailMessageDetail.self, from: Data($0[0].utf8)) }
        let pageDetails = Array(details.prefix(request.pageSize))
        let nextCursor = details.count > request.pageSize
            ? try pageDetails.last.map { try MailSQLitePageCursor(date: $0.summary.date, id: $0.id.rawValue).encode() }
            : nil
        return MailMessagePage(messages: pageDetails.map(\.summary), nextCursor: nextCursor)
    }

    public func presentationPage(_ request: MailMessagePageRequest) async throws -> (NativeMailBrowserPresentation, String?) {
        let accounts = try await listAccounts()
        let mailboxRows = try querySQL("SELECT raw_json FROM mail_mailboxes ORDER BY path COLLATE NOCASE")
        let mailboxes = try mailboxRows.map { try decoder.decode(MailMailbox.self, from: Data($0[0].utf8)) }
        let page = try await messagePage(request)
        return (NativeMailBrowserPresentation(accounts: accounts, mailboxes: mailboxes, messages: page.messages), page.nextCursor)
    }

    public func diagnosticCounts() async throws -> MailStoreDiagnosticCounts {
        let accountCount = Int(try querySQL("SELECT COUNT(*) FROM mail_accounts").first?.first ?? "0") ?? 0
        let mailboxCount = Int(try querySQL("SELECT COUNT(*) FROM mail_mailboxes").first?.first ?? "0") ?? 0
        let messageCount = Int(try querySQL("SELECT COUNT(*) FROM mail_messages").first?.first ?? "0") ?? 0
        let roleRows = try querySQL("SELECT role, COUNT(*) FROM mail_mailboxes GROUP BY role")
        let roles = Dictionary(uniqueKeysWithValues: roleRows.compactMap { row -> (String, Int)? in
            guard row.count == 2, let count = Int(row[1]) else { return nil }
            return (row[0], count)
        })
        return MailStoreDiagnosticCounts(accounts: accountCount, mailboxes: mailboxCount, messages: messageCount, mailboxRoles: roles)
    }

    public func searchMessages(query: String, accountID: MailAccountID?, temporalFilter: NativeSearchTemporalFilter?, temporalSort: NativeSearchTemporalSort, limit: Int) async throws -> [MailMessageSummary] {
        let limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        if let searchService, hasPrimedSearchIndex {
            let results = try await searchService.search(NativeSearchQuery(text: query, sourceKinds: [.mail], sourceInstanceIDs: accountID.map { Set([$0.rawValue]) }, temporalFilter: temporalFilter, temporalSort: temporalSort, limit: limit, rankingProfile: .recentFirst))
            var summaries: [MailMessageSummary] = []
            summaries.reserveCapacity(results.count)
            for result in results {
                if let detail = try await message(id: MailMessageID(rawValue: result.externalID)) {
                    summaries.append(detail.summary)
                }
            }
            return summaries
        }
        // Fallback: SQL query
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var sql = "SELECT raw_json FROM mail_messages WHERE 1=1"
        if let accountID { sql += " AND account_id = '\(esc(accountID.rawValue))'" }
        if let start = temporalFilter?.start { sql += " AND date >= '\(esc(iso8601(start)))'" }
        if let end = temporalFilter?.end { sql += " AND date < '\(esc(iso8601(end)))'" }
        if !normalized.isEmpty {
            let term = escLike(normalized)
            sql += " AND (LOWER(subject) LIKE '%\(term)%' ESCAPE '\\' OR LOWER(snippet) LIKE '%\(term)%' ESCAPE '\\' OR LOWER(from_email) LIKE '%\(term)%' ESCAPE '\\' OR LOWER(COALESCE(from_name,'')) LIKE '%\(term)%' ESCAPE '\\' OR LOWER(COALESCE(body_plain,'')) LIKE '%\(term)%' ESCAPE '\\')"
        }
        let ascending = temporalSort == .timeAscThenRelevance || temporalSort == .relevanceThenTimeAsc
        sql += " ORDER BY date \(ascending ? "ASC" : "DESC"), id ASC LIMIT \(limit)"
        let rows = try querySQL(sql)
        return try rows.map { try decoder.decode(MailMessageDetail.self, from: Data($0[0].utf8)).summary }
    }

    public func message(id: MailMessageID) async throws -> MailMessageDetail? {
        let rows = try querySQL("SELECT raw_json FROM mail_messages WHERE id = '\(esc(id.rawValue))' LIMIT 1")
        guard let row = rows.first else { return nil }
        return try decoder.decode(MailMessageDetail.self, from: Data(row[0].utf8))
    }

    public func allMessageIDs() async throws -> [MailMessageID] {
        let rows = try querySQL("SELECT id FROM mail_messages ORDER BY date DESC")
        return rows.map { MailMessageID(rawValue: $0[0]) }
    }

    /// 返回本地缓存中还没有可搜索正文的邮件（列表同步只拉取头部/摘要，正文按需或后台回填）。
    /// 按时间倒序取最新 `limit` 封，避免一次性回填过多占用服务器与网络。
    public func messagesMissingBody(limit: Int) async throws -> [MailMessageDetail] {
        let capped = max(1, min(limit, 2000))
        let rows = try querySQL("SELECT m.raw_json FROM mail_messages m LEFT JOIN mail_body_backfill_retry r ON r.id=m.id WHERE m.body_available=0 AND (m.body_plain IS NULL OR m.body_plain='') AND (r.retry_at IS NULL OR r.retry_at <= \(Date().timeIntervalSince1970)) ORDER BY m.date DESC LIMIT \(capped)")
        return try rows.map { try decoder.decode(MailMessageDetail.self, from: Data($0[0].utf8)) }
    }

    func recordBackfillAttempts(_ ids: [MailMessageID], now: Date = Date()) throws {
        guard !ids.isEmpty else { return }
        let keys = ids.map { "'\(esc($0.rawValue))'" }.joined(separator: ",")
        try execute("""
            INSERT INTO mail_body_backfill_retry
            SELECT id, 1, \(now.timeIntervalSince1970 + 60) FROM mail_messages
            WHERE id IN (\(keys)) AND body_available=0
            ON CONFLICT(id) DO UPDATE SET failures=failures+1,
              retry_at=\(now.timeIntervalSince1970)+MIN(3600, 60*(1 << MIN(failures,6)));
        """)
    }

    public func clearCachedMailData() async throws {
        try transaction {
            try execute("DELETE FROM mail_messages;")
            try execute("DELETE FROM mail_mailboxes;")
            try execute("DELETE FROM mail_body_backfill_retry;")
        }
        hasPrimedSearchIndex = false
        try await searchService?.deleteBySource(kind: .mail, sourceInstanceID: nil)
    }

    public func updateFlags(messageIDs: [MailMessageID], transform: @Sendable (MailMessageFlags) -> MailMessageFlags) async throws {
        let changed = try transaction {
            var changed: [MailMessageDetail] = []
            for messageID in messageIDs {
                guard let detail = try loadMessageByIDs([messageID]).first else { continue }
                var copy = detail
                copy.summary.flags = transform(copy.summary.flags)
                if try saveMessageInternal(copy) { changed.append(copy) }
            }
            return changed
        }
        guard !changed.isEmpty else { return }
        AppAccountSyncSignal.postLocalDataDidChange()
        try await searchService?.upsert(changed.map(NativeSourceSearchAdapters.mailDocument(from:)))
    }

    public func presentation() async throws -> NativeMailBrowserPresentation {
        let accounts = try await listAccounts()
        let mailboxRows = try querySQL("SELECT raw_json FROM mail_mailboxes ORDER BY path COLLATE NOCASE")
        let mailboxes = try mailboxRows.map { try decoder.decode(MailMailbox.self, from: Data($0[0].utf8)) }
        let messageRows = try querySQL("SELECT raw_json FROM mail_messages ORDER BY date DESC")
        let details = try messageRows.map { try decoder.decode(MailMessageDetail.self, from: Data($0[0].utf8)) }
        try await repairSearchIndexIfNeeded(details: details)
        let messages = details.map(\.summary)
        return NativeMailBrowserPresentation(accounts: accounts, mailboxes: mailboxes, messages: messages)
    }

    public func repairSearchIndexIfNeeded() async throws {
        let ids = try allStoredMessageIDs()
        let details = try loadMessageByIDs(ids.map(MailMessageID.init(rawValue:)))
        try await repairSearchIndexIfNeeded(details: details)
    }

    // MARK: - Private Helpers

    @discardableResult private func saveMessageInternal(_ message: MailMessageDetail) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        let data = try encoder.encode(message)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let summary = message.summary
        let bodyPlain = message.body?.plainText?.text ?? ""
        try execute("""
            INSERT INTO mail_messages (id, account_id, mailbox_id, uid, subject, from_email, from_name, date, snippet, is_read, is_flagged, is_answered, is_deleted, has_attachments, body_plain, raw_json, body_available)
            VALUES ('\(esc(summary.id.rawValue))', '\(esc(summary.accountID.rawValue))', '\(esc(summary.mailboxID.rawValue))', '\(esc(summary.threadID?.rawValue ?? ""))', '\(esc(summary.subject))', '\(esc(summary.from.email))', \(summary.from.name.map { "'\(esc($0))'" } ?? "NULL"), '\(esc(iso8601(summary.date)))', '\(esc(summary.snippet))', \(summary.flags.isRead ? 1 : 0), \(summary.flags.isFlagged ? 1 : 0), \(summary.flags.isAnswered ? 1 : 0), \(summary.flags.isDeleted ? 1 : 0), \(summary.hasAttachments ? 1 : 0), '\(esc(bodyPlain))', '\(esc(json))', \(MailBodyOnDemandFetchPlanner.hasDisplayableBody(message) ? 1 : 0))
            ON CONFLICT(id) DO UPDATE SET account_id=excluded.account_id, mailbox_id=excluded.mailbox_id, uid=excluded.uid, subject=excluded.subject, from_email=excluded.from_email, from_name=excluded.from_name, date=excluded.date, snippet=excluded.snippet, is_read=excluded.is_read, is_flagged=excluded.is_flagged, is_answered=excluded.is_answered, is_deleted=excluded.is_deleted, has_attachments=excluded.has_attachments, body_plain=excluded.body_plain, raw_json=excluded.raw_json, body_available=excluded.body_available
            WHERE mail_messages.raw_json IS NOT excluded.raw_json
        """)
        let changed = sqlite3_changes(db) > 0
        if changed { try execute("DELETE FROM mail_body_backfill_retry WHERE id='\(esc(message.id.rawValue))'") }
        return changed
    }

    private func loadMessageByIDs(_ ids: [MailMessageID]) throws -> [MailMessageDetail] {
        guard !ids.isEmpty else { return [] }
        let inClause = ids.map { "'\(esc($0.rawValue))'" }.joined(separator: ",")
        let rows = try querySQL("SELECT raw_json FROM mail_messages WHERE id IN (\(inClause))")
        return try rows.map { try decoder.decode(MailMessageDetail.self, from: Data($0[0].utf8)) }
    }

    private func allStoredMessageIDs() throws -> [String] {
        let rows = try querySQL("SELECT id FROM mail_messages")
        return rows.map { $0[0] }
    }

    private func escLike(_ value: String) -> String {
        esc(value)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func repairSearchIndexIfNeeded(details: [MailMessageDetail]) async throws {
        guard let searchService, !hasPrimedSearchIndex else { return }
        guard !details.isEmpty else {
            hasPrimedSearchIndex = true
            try await searchService.deleteBySource(kind: .mail, sourceInstanceID: nil)
            return
        }

        let health = await searchService.health()
        let indexedCount = health.documentCountBySource[.mail] ?? 0
        guard indexedCount > 0 else {
            try await rebuildSearchIndex(details: details)
            return
        }

        let expectedIDs = Set(details.map { $0.id.rawValue })
        let sampleLimit = min(50, max(1, indexedCount))
        let sampleResults = try await searchService.search(NativeSearchQuery(
            text: "",
            sourceKinds: [.mail],
            temporalSort: .timeDescThenRelevance,
            limit: sampleLimit,
            rankingProfile: .recentFirst
        ))
        let matchedSampleCount = sampleResults.reduce(into: 0) { count, result in
            if expectedIDs.contains(result.externalID) { count += 1 }
        }
        let hasBadSample = !sampleResults.isEmpty && matchedSampleCount * 2 < sampleResults.count
        let hasLargeCountMismatch = abs(indexedCount - details.count) > max(10, details.count / 5)
        guard hasBadSample || hasLargeCountMismatch else {
            hasPrimedSearchIndex = true
            return
        }

        try await rebuildSearchIndex(details: details)
    }

    private func rebuildSearchIndex(details: [MailMessageDetail]) async throws {
        guard let searchService else { return }
        try await searchService.rebuildSource(kind: .mail, sourceInstanceID: nil, documents: details.map(NativeSourceSearchAdapters.mailDocument(from:)))
        hasPrimedSearchIndex = true
    }

    // MARK: - SQLite Helpers

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try executeUnlocked("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try executeUnlocked("COMMIT;")
            return result
        } catch {
            try? executeUnlocked("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try executeUnlocked(sql)
    }

    private func executeUnlocked(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteMailSourceStoreError.executeFailed(lastError())
        }
    }



    private func querySQL(_ sql: String) throws -> [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return try querySQLUnlocked(sql)
    }

    private func querySQLUnlocked(_ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteMailSourceStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(statement) }
        var rows: [[String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                let count = sqlite3_column_count(statement)
                var row: [String] = []
                for i in 0..<count {
                    if let cString = sqlite3_column_text(statement, i) {
                        row.append(String(cString: cString))
                    } else {
                        row.append("")
                    }
                }
                rows.append(row)
            } else if result == SQLITE_DONE {
                break
            } else {
                throw SQLiteMailSourceStoreError.stepFailed(lastError())
            }
        }
        return rows
    }

    private func lastError() -> String {
        if let cString = sqlite3_errmsg(db) { return String(cString: cString) }
        return "unknown SQLite error"
    }

    /// Escape single quotes for SQL string literals
    private func esc(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
