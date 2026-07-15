import Foundation
import SQLite3
import ConnorGraphCore

public struct SessionSearchResult: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var snippet: String
    public var updatedAt: Date
    public var messageCount: Int

    public init(id: String, title: String, snippet: String, updatedAt: Date, messageCount: Int) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.updatedAt = updatedAt
        self.messageCount = messageCount
    }
}

public struct SessionSearchIndexSynchronizationResult: Sendable, Equatable {
    public var upsertedCount: Int
    public var removedCount: Int
    public var unchangedCount: Int

    public init(upsertedCount: Int, removedCount: Int, unchangedCount: Int) {
        self.upsertedCount = upsertedCount
        self.removedCount = removedCount
        self.unchangedCount = unchangedCount
    }
}

public actor SessionSearchIndexService {
    private let databaseURL: URL
    private nonisolated(unsafe) var db: OpaquePointer?

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open session search database"
            if let handle { sqlite3_close(handle) }
            throw SessionSearchIndexError.openFailed(message)
        }
        try Self.migrate(handle)
        self.db = handle
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    public func bootstrapIfEmpty(sessions: [AgentSession]) async throws -> SessionSearchIndexSynchronizationResult {
        try Task.checkCancellation()
        guard try !hasIndexedSessions() else {
            return SessionSearchIndexSynchronizationResult(
                upsertedCount: 0,
                removedCount: 0,
                unchangedCount: sessions.count
            )
        }

        try execute("BEGIN IMMEDIATE")
        do {
            for session in sessions {
                try Task.checkCancellation()
                try upsertOne(session)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        return SessionSearchIndexSynchronizationResult(
            upsertedCount: sessions.count,
            removedCount: 0,
            unchangedCount: 0
        )
    }

    public func upsert(session: AgentSession) async throws {
        try Task.checkCancellation()
        try execute("BEGIN IMMEDIATE")
        do {
            try upsertOne(session)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func remove(sessionID: String) async throws {
        try Task.checkCancellation()
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM session_search_fts WHERE session_id = ?", bindings: [.text(sessionID)])
            try execute("DELETE FROM session_search_docs WHERE session_id = ?", bindings: [.text(sessionID)])
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func search(query: String, limit: Int) async throws -> [SessionSearchResult] {
        let normalized = NativeSearchQueryNormalizer.normalize(query)
        let match = NativeSourceSearchFTSQueryBuilder.query(for: normalized)
        guard !match.isEmpty else { return [] }
        let rows = try queryRows(
            """
            SELECT d.session_id, d.title, d.recent_messages, d.updated_at, d.message_count
            FROM session_search_fts f
            JOIN session_search_docs d ON d.session_id = f.session_id
            WHERE session_search_fts MATCH ?
            ORDER BY bm25(session_search_fts) ASC, d.updated_at DESC
            LIMIT ?
            """,
            bindings: [.text(match), .int(max(limit, 1))]
        )
        return rows.compactMap { row in
            guard let id = row[0].text, let title = row[1].text else { return nil }
            let recent = row[2].text ?? title
            let updatedAt = Date(timeIntervalSince1970: row[3].double ?? 0)
            let messageCount = Int(row[4].int64 ?? 0)
            return SessionSearchResult(id: id, title: title.isEmpty ? "新对话" : title, snippet: Self.snippet(from: recent, normalized: normalized), updatedAt: updatedAt, messageCount: messageCount)
        }
    }

    private func upsertOne(_ session: AgentSession) throws {
        let recentMessages = Self.recentMessagesText(for: session)
        let indexedText = NativeSourceSearchIndexedTextBuilder.searchableText(for: NativeSearchDocument(
            id: "session:\(session.id)",
            sourceKind: .browserHistory,
            externalID: session.id,
            title: session.title,
            summary: recentMessages,
            body: recentMessages,
            temporal: NativeSearchTemporalMetadata(primaryTime: session.updatedAt, primaryTimeKind: .updatedAt, updatedAt: session.updatedAt),
            contentHash: session.id
        ))
        try execute(
            """
            INSERT INTO session_search_docs(session_id, title, recent_messages, updated_at, message_count)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
              title=excluded.title,
              recent_messages=excluded.recent_messages,
              updated_at=excluded.updated_at,
              message_count=excluded.message_count
            """,
            bindings: [.text(session.id), .text(session.title), .text(recentMessages), .double(session.updatedAt.timeIntervalSince1970), .int(session.messages.count)]
        )
        try execute("DELETE FROM session_search_fts WHERE session_id = ?", bindings: [.text(session.id)])
        try execute("INSERT INTO session_search_fts(session_id, title, recent_messages, indexed_text) VALUES (?, ?, ?, ?)", bindings: [.text(session.id), .text(session.title), .text(recentMessages), .text(indexedText)])
    }

    private func hasIndexedSessions() throws -> Bool {
        try !queryRows("SELECT 1 FROM session_search_docs LIMIT 1").isEmpty
    }

    private static func recentMessagesText(for session: AgentSession) -> String {
        session.messages.suffix(12).map { message in
            "\(message.role.rawValue): \(message.content)"
        }.joined(separator: "\n")
    }

    private static func snippet(from text: String, normalized: NativeSearchNormalizedQuery) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = normalized.displayTokenValues.first(where: { !$0.isEmpty }) else { return String(trimmed.prefix(120)) }
        let lower = trimmed.lowercased()
        guard let range = lower.range(of: token.lowercased()) else { return String(trimmed.prefix(120)) }
        let start = max(0, lower.distance(from: lower.startIndex, to: range.lowerBound) - 36)
        let end = min(trimmed.count, start + 120)
        return String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: start)..<trimmed.index(trimmed.startIndex, offsetBy: end)])
    }

    private static func migrate(_ db: OpaquePointer?) throws {
        try execute("PRAGMA journal_mode=WAL", db: db)
        try execute("PRAGMA synchronous=NORMAL", db: db)
        try execute("""
        CREATE TABLE IF NOT EXISTS session_search_docs (
            session_id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            recent_messages TEXT NOT NULL,
            updated_at REAL NOT NULL,
            message_count INTEGER NOT NULL
        )
        """, db: db)
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS session_search_fts USING fts5(
            session_id UNINDEXED,
            title,
            recent_messages,
            indexed_text,
            tokenize = 'unicode61'
        )
        """, db: db)
    }

    private static func execute(_ sql: String, db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw SessionSearchIndexError.sqlite(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return }
            guard step == SQLITE_ROW else { throw SessionSearchIndexError.sqlite(String(cString: sqlite3_errmsg(db))) }
        }
    }

    private enum Binding { case text(String), int(Int), double(Double) }
    private struct Value { var text: String?; var int64: Int64?; var double: Double? }

    private func execute(_ sql: String, bindings: [Binding] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func queryRows(_ sql: String, bindings: [Binding] = []) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [[Value]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw lastError() }
            rows.append((0..<sqlite3_column_count(statement)).map { index in
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    let value = sqlite3_column_int64(statement, index)
                    return Value(text: nil, int64: value, double: Double(value))
                case SQLITE_FLOAT:
                    let value = sqlite3_column_double(statement, index)
                    return Value(text: nil, int64: Int64(value), double: value)
                case SQLITE_TEXT:
                    return Value(text: sqlite3_column_text(statement, index).map { String(cString: $0) }, int64: nil, double: nil)
                default:
                    return Value(text: nil, int64: nil, double: nil)
                }
            })
        }
        return rows
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer?) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value): result = sqlite3_bind_text(statement, index, value, -1, SESSION_SEARCH_SQLITE_TRANSIENT)
            case .int(let value): result = sqlite3_bind_int(statement, index, Int32(value))
            case .double(let value): result = sqlite3_bind_double(statement, index, value)
            }
            guard result == SQLITE_OK else { throw lastError() }
        }
    }

    private func lastError() -> SessionSearchIndexError {
        SessionSearchIndexError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
}

private let SESSION_SEARCH_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SessionSearchIndexError: Error, Sendable, Equatable, CustomStringConvertible {
    case openFailed(String)
    case sqlite(String)

    public var description: String {
        switch self {
        case .openFailed(let message): "openFailed(\(message))"
        case .sqlite(let message): "sqlite(\(message))"
        }
    }
}
