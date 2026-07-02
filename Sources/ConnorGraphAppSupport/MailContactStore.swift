import Foundation
import SQLite3
import ConnorGraphCore

// MARK: - MailContact Data Model

/// 从邮件中提取的联系人
public struct MailContact: Codable, Sendable, Identifiable {
    public let id: MailContactID
    public var email: String
    public var displayName: String?
    public var frequency: Int  // 联系频率
    public var lastContactedAt: Date?
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var sources: Set<ContactSource>  // 来源集合

    public init(
        id: MailContactID,
        email: String,
        displayName: String? = nil,
        frequency: Int = 1,
        lastContactedAt: Date? = nil,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        sources: Set<ContactSource> = []
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.frequency = frequency
        self.lastContactedAt = lastContactedAt
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.sources = sources
    }
}

/// 联系人来源
public enum ContactSource: String, Codable, Sendable, CaseIterable {
    case from   // 发件人
    case to     // 收件人
    case cc     // 抄送
    case bcc    // 密送
}

// MailContactID is defined in ConnorGraphCore

// MARK: - MailContactStore Protocol

/// 联系人存储协议
public protocol MailContactStore: Sendable {
    /// 保存联系人列表（合并重复）
    func saveContacts(_ contacts: [MailContact]) async throws
    /// 加载所有联系人
    func loadContacts() async throws -> [MailContact]
    /// 搜索联系人
    func searchContacts(query: String) async throws -> [MailContact]
    /// 删除联系人
    func deleteContact(id: MailContactID) async throws
    /// 清空所有联系人
    func clearContacts() async throws
}

// MARK: - SQLiteMailContactStore

/// SQLite 实现的联系人存储
public final class SQLiteMailContactStore: MailContactStore, @unchecked Sendable {
    private let db: OpaquePointer
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(databaseURL: URL) throws {
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
            CREATE TABLE IF NOT EXISTS mail_contacts (
                id TEXT PRIMARY KEY,
                email TEXT NOT NULL,
                display_name TEXT,
                frequency INTEGER NOT NULL DEFAULT 1,
                last_contacted_at TEXT,
                first_seen_at TEXT NOT NULL,
                last_seen_at TEXT NOT NULL,
                sources TEXT NOT NULL,
                raw_json TEXT NOT NULL
            );
        """)

        try execute("CREATE INDEX IF NOT EXISTS idx_contact_email ON mail_contacts(email);")
        try execute("CREATE INDEX IF NOT EXISTS idx_contact_frequency ON mail_contacts(frequency DESC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_contact_last_seen ON mail_contacts(last_seen_at DESC);")
    }

    // MARK: - MailContactStore Implementation

    public func saveContacts(_ contacts: [MailContact]) async throws {
        // 加载现有联系人用于合并
        var existingMap: [String: MailContact] = [:]
        let existing = try await loadContacts()
        for contact in existing {
            existingMap[contact.email] = contact
        }

        // 合并新联系人
        for contact in contacts {
            if let existingContact = existingMap[contact.email] {
                existingMap[contact.email] = mergeContacts(existingContact, with: contact)
            } else {
                existingMap[contact.email] = contact
            }
        }

        // 保存所有联系人
        try execute("BEGIN TRANSACTION;")
        do {
            for contact in existingMap.values {
                try saveContactInternal(contact)
            }
            try execute("COMMIT;")
        } catch {
            try execute("ROLLBACK;")
            throw error
        }
    }

    public func loadContacts() async throws -> [MailContact] {
        return try loadContactsInternal()
    }

    public func searchContacts(query: String) async throws -> [MailContact] {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return try loadContactsInternal() }

        let escaped = normalized.replacingOccurrences(of: "'", with: "''")
        let sql = """
            SELECT raw_json FROM mail_contacts 
            WHERE LOWER(email) LIKE '%\(escaped)%' 
               OR LOWER(COALESCE(display_name, '')) LIKE '%\(escaped)%'
            ORDER BY frequency DESC, last_seen_at DESC
        """

        let rows = try querySQL(sql)
        return try rows.map { try decoder.decode(MailContact.self, from: Data($0[0].utf8)) }
    }

    public func deleteContact(id: MailContactID) async throws {
        let escaped = id.rawValue.replacingOccurrences(of: "'", with: "''")
        try execute("DELETE FROM mail_contacts WHERE id = '\(escaped)';")
    }

    public func clearContacts() async throws {
        try execute("DELETE FROM mail_contacts;")
    }

    // MARK: - Internal Methods

    private func loadContactsInternal() throws -> [MailContact] {
        let rows = try querySQL("SELECT raw_json FROM mail_contacts ORDER BY frequency DESC, last_seen_at DESC")
        return try rows.map { try decoder.decode(MailContact.self, from: Data($0[0].utf8)) }
    }

    private func saveContactInternal(_ contact: MailContact) throws {
        let data = try encoder.encode(contact)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let sourcesJSON = try String(data: encoder.encode(contact.sources.map(\.rawValue)), encoding: .utf8) ?? "[]"

        let sql = """
            INSERT OR REPLACE INTO mail_contacts 
            (id, email, display_name, frequency, last_contacted_at, first_seen_at, last_seen_at, sources, raw_json)
            VALUES (
                '\(esc(contact.id.rawValue))',
                '\(esc(contact.email))',
                \(contact.displayName.map { "'\(esc($0))'" } ?? "NULL"),
                \(contact.frequency),
                \(contact.lastContactedAt.map { "'\(esc(iso8601($0)))'" } ?? "NULL"),
                '\(esc(iso8601(contact.firstSeenAt)))',
                '\(esc(iso8601(contact.lastSeenAt)))',
                '\(esc(sourcesJSON))',
                '\(esc(json))'
            );
        """
        try execute(sql)
    }

    /// 合并两个联系人
    private func mergeContacts(_ existing: MailContact, with new: MailContact) -> MailContact {
        var merged = existing
        merged.frequency += new.frequency
        merged.sources.formUnion(new.sources)

        // 更新时间
        if let newLast = new.lastContactedAt {
            if let existingLast = existing.lastContactedAt {
                if newLast > existingLast {
                    merged.lastContactedAt = newLast
                }
            } else {
                merged.lastContactedAt = newLast
            }
        }

        if new.lastSeenAt > existing.lastSeenAt {
            merged.lastSeenAt = new.lastSeenAt
        }

        if new.firstSeenAt < existing.firstSeenAt {
            merged.firstSeenAt = new.firstSeenAt
        }

        // 保留更完整的显示名
        if merged.displayName == nil || merged.displayName?.isEmpty == true {
            merged.displayName = new.displayName
        }

        return merged
    }

    // MARK: - SQLite Helpers

    private func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let msg = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw SQLiteMailSourceStoreError.executeFailed("\(msg) [SQL: \(sql.prefix(100))]")
        }
    }

    private func querySQL(_ sql: String) throws -> [[String]] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteMailSourceStoreError.prepareFailed("Cannot prepare: \(sql.prefix(100))")
        }
        defer { sqlite3_finalize(statement) }

        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String] = []
            for i in 0..<sqlite3_column_count(statement) {
                if let cString = sqlite3_column_text(statement, i) {
                    row.append(String(cString: cString))
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func esc(_ string: String) -> String {
        string.replacingOccurrences(of: "'", with: "''")
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
