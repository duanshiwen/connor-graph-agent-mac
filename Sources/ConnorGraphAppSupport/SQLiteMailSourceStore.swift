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

// MARK: - SQLiteMailSourceStore

public final class SQLiteMailSourceStore: MailStoreProtocol, @unchecked Sendable {

    // MARK: Properties

    private let db: OpaquePointer
    private let lock = NSLock()
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
        try createTables()
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

        try execute("CREATE INDEX IF NOT EXISTS idx_msg_account ON mail_messages(account_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_msg_mailbox ON mail_messages(mailbox_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_msg_date ON mail_messages(date DESC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_msg_uid ON mail_messages(account_id, uid);")
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
            INSERT OR REPLACE INTO mail_accounts (id, display_name, email, provider, updated_at, raw_json)
            VALUES ('\(esc(account.id.rawValue))', '\(esc(account.displayName))', '\(esc(account.identities.first?.address.email ?? ""))', '\(esc(account.provider.rawValue))', '\(esc(iso8601(account.updatedAt)))', '\(esc(json))')
        """)
    }

    public func account(id: MailAccountID) async throws -> MailAccount? {
        let rows = try querySQL("SELECT raw_json FROM mail_accounts WHERE id = '\(esc(id.rawValue))' LIMIT 1")
        guard let row = rows.first else { return nil }
        return try decoder.decode(MailAccount.self, from: Data(row[0].utf8))
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
            INSERT OR REPLACE INTO mail_mailboxes (id, account_id, name, path, role, message_count, unread_count, last_synced_at, raw_json)
            VALUES ('\(esc(mailbox.id.rawValue))', '\(esc(mailbox.accountID.rawValue))', '\(esc(mailbox.name))', '\(esc(mailbox.path))', '\(esc(mailbox.role.rawValue))', \(mailbox.status.messageCount), \(mailbox.status.unreadCount), \(mailbox.status.lastSyncedAt.map { "'\(esc(iso8601($0)))'" } ?? "NULL"), '\(esc(json))')
        """)
    }

    public func saveMessage(_ message: MailMessageDetail) async throws {
        try saveMessageInternal(message)
        try await searchService?.upsert([NativeSourceSearchAdapters.mailDocument(from: message)])
    }

    public func saveMessagesBatch(_ messages: [MailMessageDetail]) async throws {
        guard !messages.isEmpty else { return }
        try execute("BEGIN TRANSACTION;")
        do {
            for message in messages {
                try saveMessageInternal(message)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
        if let searchService {
            try await searchService.upsert(messages.map { NativeSourceSearchAdapters.mailDocument(from: $0) })
        }
    }

    public func searchMessages(query: String, accountID: MailAccountID?) async throws -> [MailMessageSummary] {
        try await searchMessages(query: query, accountID: accountID, temporalFilter: nil, temporalSort: .relevanceThenTimeDesc, limit: Int.max)
    }

    public func searchMessages(query: String, accountID: MailAccountID?, temporalFilter: NativeSearchTemporalFilter?, temporalSort: NativeSearchTemporalSort, limit: Int) async throws -> [MailMessageSummary] {
        let limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        if let searchService {
            let allIDs = try allStoredMessageIDs()
            let allDetails = try loadMessageByIDs(allIDs.map(MailMessageID.init(rawValue:)))
            try await primeSearchIndexIfNeeded(details: allDetails)
            let results = try await searchService.search(NativeSearchQuery(text: query, sourceKinds: [.mail], sourceInstanceIDs: accountID.map { Set([$0.rawValue]) }, temporalFilter: temporalFilter, temporalSort: temporalSort, limit: limit, rankingProfile: .recentFirst))
            let byID = Dictionary(uniqueKeysWithValues: allDetails.map { ($0.id.rawValue, $0.summary) })
            return results.compactMap { byID[$0.externalID] }
        }
        // Fallback: SQL query
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var sql = "SELECT raw_json FROM mail_messages WHERE 1=1"
        if let accountID { sql += " AND account_id = '\(esc(accountID.rawValue))'" }
        if !normalized.isEmpty {
            let escaped = normalized.replacingOccurrences(of: "'", with: "''")
            sql += " AND (LOWER(subject) LIKE '%\(escaped)%' OR LOWER(snippet) LIKE '%\(escaped)%' OR LOWER(from_email) LIKE '%\(escaped)%' OR LOWER(COALESCE(from_name,'')) LIKE '%\(escaped)%')"
        }
        let ascending = temporalSort == .timeAscThenRelevance || temporalSort == .relevanceThenTimeAsc
        sql += " ORDER BY date \(ascending ? "ASC" : "DESC") LIMIT \(limit)"
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

    public func updateFlags(messageIDs: [MailMessageID], transform: @Sendable (MailMessageFlags) -> MailMessageFlags) async throws {
        try execute("BEGIN TRANSACTION;")
        do {
            for messageID in messageIDs {
                guard let detail = try loadMessageByIDs([messageID]).first else { continue }
                var copy = detail
                copy.summary.flags = transform(copy.summary.flags)
                try saveMessageInternal(copy)
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
        let changed = try loadMessageByIDs(messageIDs)
        try await searchService?.upsert(changed.map(NativeSourceSearchAdapters.mailDocument(from:)))
    }

    public func presentation() async throws -> NativeMailBrowserPresentation {
        let accounts = try await listAccounts()
        let mailboxRows = try querySQL("SELECT raw_json FROM mail_mailboxes ORDER BY path COLLATE NOCASE")
        let mailboxes = try mailboxRows.map { try decoder.decode(MailMailbox.self, from: Data($0[0].utf8)) }
        let messageRows = try querySQL("SELECT raw_json FROM mail_messages ORDER BY date DESC")
        let messages = try messageRows.map { try decoder.decode(MailMessageDetail.self, from: Data($0[0].utf8)).summary }
        return NativeMailBrowserPresentation(accounts: accounts, mailboxes: mailboxes, messages: messages)
    }

    // MARK: - Private Helpers

    private func saveMessageInternal(_ message: MailMessageDetail) throws {
        let data = try encoder.encode(message)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let summary = message.summary
        let bodyPlain = message.body?.plainText?.text ?? ""
        try execute("""
            INSERT OR REPLACE INTO mail_messages (id, account_id, mailbox_id, uid, subject, from_email, from_name, date, snippet, is_read, is_flagged, is_answered, is_deleted, has_attachments, body_plain, raw_json)
            VALUES ('\(esc(summary.id.rawValue))', '\(esc(summary.accountID.rawValue))', '\(esc(summary.mailboxID.rawValue))', '\(esc(summary.threadID?.rawValue ?? ""))', '\(esc(summary.subject))', '\(esc(summary.from.email))', \(summary.from.name.map { "'\(esc($0))'" } ?? "NULL"), '\(esc(iso8601(summary.date)))', '\(esc(summary.snippet))', \(summary.flags.isRead ? 1 : 0), \(summary.flags.isFlagged ? 1 : 0), \(summary.flags.isAnswered ? 1 : 0), \(summary.flags.isDeleted ? 1 : 0), \(summary.hasAttachments ? 1 : 0), '\(esc(bodyPlain))', '\(esc(json))')
        """)
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

    private func primeSearchIndexIfNeeded(details: [MailMessageDetail]) async throws {
        guard let searchService, !hasPrimedSearchIndex else { return }
        try await searchService.rebuildSource(kind: .mail, sourceInstanceID: nil, documents: details.map(NativeSourceSearchAdapters.mailDocument(from:)))
        hasPrimedSearchIndex = true
    }

    // MARK: - SQLite Helpers

    private func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteMailSourceStoreError.executeFailed(lastError())
        }
    }



    private func querySQL(_ sql: String) throws -> [[String]] {
        lock.lock()
        defer { lock.unlock() }
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


