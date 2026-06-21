import Foundation
import SQLite3
import ConnorGraphCore

public actor SQLiteNativeSourceSearchBackend: NativeSourceSearchBackend {
    public static let schemaVersion = 1

    private let databaseURL: URL
    private nonisolated(unsafe) var db: OpaquePointer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastError: String?

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database"
            if let handle { sqlite3_close(handle) }
            throw SQLiteNativeSourceSearchError.openFailed(message)
        }
        try Self.migrate(handle)
        self.db = handle
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    public func upsert(_ documents: [NativeSearchDocument]) async throws {
        guard !documents.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            for document in documents { try upsertOne(prepared(document)) }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            lastError = String(describing: error)
            throw error
        }
    }

    public func delete(documentIDs: [String]) async throws {
        guard !documentIDs.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            for id in documentIDs {
                try execute("DELETE FROM native_search_fts WHERE id = ?", bindings: [.text(id)])
                try execute("DELETE FROM native_search_docs WHERE id = ?", bindings: [.text(id)])
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            lastError = String(describing: error)
            throw error
        }
    }

    public func deleteBySource(kind: NativeSearchSourceKind, sourceInstanceID: String? = nil) async throws {
        let ids = try idsForSource(kind: kind, sourceInstanceID: sourceInstanceID)
        try await delete(documentIDs: ids)
    }

    public func rebuildSource(kind: NativeSearchSourceKind, sourceInstanceID: String? = nil, documents: [NativeSearchDocument]) async throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let ids = try idsForSource(kind: kind, sourceInstanceID: sourceInstanceID)
            for id in ids {
                try execute("DELETE FROM native_search_fts WHERE id = ?", bindings: [.text(id)])
                try execute("DELETE FROM native_search_docs WHERE id = ?", bindings: [.text(id)])
            }
            for document in documents { try upsertOne(prepared(document)) }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            lastError = String(describing: error)
            throw error
        }
    }

    public func search(_ query: NativeSearchQuery) async throws -> [NativeSearchResult] {
        let normalizedQuery = NativeSearchQueryNormalizer.normalize(query.text)
        let tokens = normalizedQuery.scoringTokens.map(\.value)
        let allQueryTokens = normalizedQuery.tokens.map(\.value)
        let softStopWords = normalizedQuery.softStopTokenValues
        let candidateDocuments = try loadCandidates(query: query, tokens: tokens)
        let now = Date()
        let results = candidateDocuments.compactMap { document -> NativeSearchResult? in
            if let kinds = query.sourceKinds, !kinds.contains(document.sourceKind) { return nil }
            if let ids = query.sourceInstanceIDs, !(document.sourceInstanceID.map { ids.contains($0) } ?? false) { return nil }
            if !query.includeHidden, document.state["isHidden"] == "true" { return nil }
            if !query.includeArchived, document.state["isArchived"] == "true" { return nil }
            if let temporalFilter = query.temporalFilter, !temporalFilter.contains(document.temporal, sourceKind: document.sourceKind) { return nil }
            if !NativeSourceSearchService.matchesFieldConstraints(query.fieldConstraints, document: document) { return nil }
            let scored = NativeSourceSearchService.score(document: document, tokens: tokens, phrase: normalizedQuery.normalizedText, now: now, rankingProfile: query.rankingProfile)
            if !tokens.isEmpty, scored.lexicalScore <= 0 { return nil }
            let matchedTerms = NativeSourceSearchService.matchedTerms(for: document, tokens: tokens)
            let snippet = query.includeBodySnippets ? NativeSourceSearchService.bestSnippet(for: document, tokens: matchedTerms.isEmpty ? tokens : matchedTerms) : document.summary
            let rankReason = "backend=sqlite-fts5; lexical=\(NativeSourceSearchService.rounded(scored.lexicalScore)); freshness=\(NativeSourceSearchService.rounded(scored.freshnessScore)); fields=\(scored.matchedFields.joined(separator: ","))"
            let timeReason = NativeSourceSearchService.timeReason(for: document, temporalFilter: query.temporalFilter)
            return NativeSearchResult(
                id: document.id,
                sourceKind: document.sourceKind,
                externalID: document.externalID,
                sourceInstanceID: document.sourceInstanceID,
                title: document.title,
                snippet: snippet,
                highlights: matchedTerms,
                score: scored.total,
                lexicalScore: scored.lexicalScore,
                freshnessScore: scored.freshnessScore,
                fieldScore: scored.fieldScore,
                temporal: document.temporal,
                resultTimeLabel: NativeSourceSearchService.resultTimeLabel(for: document.temporal.primaryTimeKind, sourceKind: document.sourceKind),
                diagnostics: NativeSearchResultDiagnostics(
                    matchedFields: scored.matchedFields,
                    indexedAt: document.temporal.indexedAt,
                    queryTokens: allQueryTokens,
                    softStopWords: softStopWords,
                    matchedTerms: matchedTerms,
                    matchedFieldScores: scored.matchedFieldScores,
                    fieldConstraints: query.fieldConstraints.mapKeys(\.rawValue),
                    rankReason: rankReason,
                    timeReason: timeReason
                )
            )
        }
        return Array(results.sorted { lhs, rhs in
            NativeSourceSearchService.compare(lhs, rhs, sort: query.temporalSort)
        }.prefix(query.limit))
    }

    public func health() async -> NativeSourceSearchHealthSnapshot {
        do {
            let rows = try queryRows("SELECT source_kind, COUNT(*), MAX(indexed_at) FROM native_search_docs GROUP BY source_kind")
            var counts: [NativeSearchSourceKind: Int] = [:]
            var indexed: [NativeSearchSourceKind: Date] = [:]
            for row in rows {
                guard let kindValue = row[0].text, let kind = NativeSearchSourceKind(rawValue: kindValue) else { continue }
                counts[kind] = Int(row[1].int64 ?? 0)
                if let timestamp = row[2].double { indexed[kind] = Date(timeIntervalSince1970: timestamp) }
            }
            return NativeSourceSearchHealthSnapshot(
                backendStatus: "ready:sqlite-fts5",
                schemaVersion: Self.schemaVersion,
                documentCountBySource: counts,
                lastIndexedAtBySource: indexed,
                lastError: lastError
            )
        } catch {
            return NativeSourceSearchHealthSnapshot(
                backendStatus: "error:sqlite-fts5",
                schemaVersion: Self.schemaVersion,
                lastError: String(describing: error)
            )
        }
    }

    private static func migrate(_ db: OpaquePointer?) throws {
        try execute("PRAGMA journal_mode=WAL", db: db)
        try execute("PRAGMA synchronous=NORMAL", db: db)
        try execute("""
        CREATE TABLE IF NOT EXISTS native_search_docs (
            id TEXT PRIMARY KEY,
            source_kind TEXT NOT NULL,
            source_instance_id TEXT,
            external_id TEXT NOT NULL,
            title TEXT NOT NULL,
            search_text TEXT NOT NULL,
            primary_time REAL,
            indexed_at REAL,
            is_hidden INTEGER NOT NULL DEFAULT 0,
            is_archived INTEGER NOT NULL DEFAULT 0,
            content_hash TEXT NOT NULL,
            document_json BLOB NOT NULL
        )
        """, db: db)
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS native_search_fts USING fts5(
            id UNINDEXED,
            title,
            summary,
            participants,
            location,
            body,
            search_text,
            tokenize = 'unicode61'
        )
        """, db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_native_search_docs_source ON native_search_docs(source_kind, source_instance_id)", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_native_search_docs_time ON native_search_docs(primary_time)", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_native_search_docs_state ON native_search_docs(is_hidden, is_archived)", db: db)
    }

    private static func execute(_ sql: String, db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteNativeSourceSearchError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return }
            guard step == SQLITE_ROW else {
                throw SQLiteNativeSourceSearchError.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func prepared(_ document: NativeSearchDocument) -> NativeSearchDocument {
        var indexed = document
        var temporal = indexed.temporal
        if temporal.indexedAt == nil { temporal.indexedAt = Date() }
        if temporal.primaryTime == nil {
            temporal.primaryTime = NativeSourceSearchService.defaultPrimaryTime(for: indexed.sourceKind, temporal: temporal)
            temporal.primaryTimeKind = NativeSourceSearchService.defaultPrimaryTimeKind(for: indexed.sourceKind, temporal: temporal)
        }
        indexed.temporal = temporal
        return indexed
    }

    private func upsertOne(_ document: NativeSearchDocument) throws {
        let data = try encoder.encode(document)
        let searchText = searchableText(for: document)
        try execute(
            """
            INSERT INTO native_search_docs(id, source_kind, source_instance_id, external_id, title, search_text, primary_time, indexed_at, is_hidden, is_archived, content_hash, document_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                source_kind=excluded.source_kind,
                source_instance_id=excluded.source_instance_id,
                external_id=excluded.external_id,
                title=excluded.title,
                search_text=excluded.search_text,
                primary_time=excluded.primary_time,
                indexed_at=excluded.indexed_at,
                is_hidden=excluded.is_hidden,
                is_archived=excluded.is_archived,
                content_hash=excluded.content_hash,
                document_json=excluded.document_json
            """,
            bindings: [
                .text(document.id),
                .text(document.sourceKind.rawValue),
                .nullableText(document.sourceInstanceID),
                .text(document.externalID),
                .text(document.title),
                .text(searchText),
                .nullableDouble(document.temporal.primaryTime?.timeIntervalSince1970),
                .nullableDouble(document.temporal.indexedAt?.timeIntervalSince1970),
                .int(document.state["isHidden"] == "true" ? 1 : 0),
                .int(document.state["isArchived"] == "true" ? 1 : 0),
                .text(document.contentHash),
                .blob(data)
            ]
        )
        try execute("DELETE FROM native_search_fts WHERE id = ?", bindings: [.text(document.id)])
        try execute(
            "INSERT INTO native_search_fts(id, title, summary, participants, location, body, search_text) VALUES (?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(document.id),
                .text(document.title),
                .text(document.summary),
                .text(document.participants.joined(separator: " ")),
                .text(document.location ?? ""),
                .text(document.body ?? ""),
                .text(searchText)
            ]
        )
    }

    private func idsForSource(kind: NativeSearchSourceKind, sourceInstanceID: String?) throws -> [String] {
        if let sourceInstanceID {
            return try queryRows("SELECT id FROM native_search_docs WHERE source_kind = ? AND source_instance_id = ?", bindings: [.text(kind.rawValue), .text(sourceInstanceID)]).compactMap { $0[0].text }
        }
        return try queryRows("SELECT id FROM native_search_docs WHERE source_kind = ?", bindings: [.text(kind.rawValue)]).compactMap { $0[0].text }
    }

    private func loadCandidates(query: NativeSearchQuery, tokens: [String]) throws -> [NativeSearchDocument] {
        var sql = "SELECT document_json FROM native_search_docs"
        var clauses: [String] = []
        var bindings: [SQLiteBinding] = []
        if let kinds = query.sourceKinds, !kinds.isEmpty {
            clauses.append("source_kind IN (\(Array(repeating: "?", count: kinds.count).joined(separator: ",")))")
            bindings.append(contentsOf: kinds.map { .text($0.rawValue) })
        }
        if let ids = query.sourceInstanceIDs, !ids.isEmpty {
            clauses.append("source_instance_id IN (\(Array(repeating: "?", count: ids.count).joined(separator: ",")))")
            bindings.append(contentsOf: ids.map { .text($0) })
        }
        if !query.includeHidden { clauses.append("is_hidden = 0") }
        if !query.includeArchived { clauses.append("is_archived = 0") }
        if let temporalFilter = query.temporalFilter {
            if let start = temporalFilter.start {
                clauses.append("primary_time >= ?")
                bindings.append(.double(start.timeIntervalSince1970))
            }
            if let end = temporalFilter.end {
                clauses.append("primary_time < ?")
                bindings.append(.double(end.timeIntervalSince1970))
            }
        }
        if !tokens.isEmpty {
            let tokenClauses = tokens.map { _ in "search_text LIKE ?" }.joined(separator: " OR ")
            clauses.append("(\(tokenClauses))")
            bindings.append(contentsOf: tokens.map { .text("%\($0)%") })
        }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " LIMIT 1000"
        return try queryRows(sql, bindings: bindings).compactMap { row in
            guard let data = row[0].blob else { return nil }
            return try decoder.decode(NativeSearchDocument.self, from: data)
        }
    }

    private func searchableText(for document: NativeSearchDocument) -> String {
        [
            document.title,
            document.summary,
            document.participants.joined(separator: " "),
            document.location ?? "",
            document.body ?? "",
            document.metadata.values.joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private enum SQLiteBinding {
        case text(String)
        case nullableText(String?)
        case int(Int)
        case int64(Int64)
        case double(Double)
        case nullableDouble(Double?)
        case blob(Data)
    }

    private struct SQLiteValue {
        var text: String?
        var int64: Int64?
        var double: Double?
        var blob: Data?
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw lastSQLiteError() }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastSQLiteError() }
    }

    private func queryRows(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [[SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw lastSQLiteError() }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [[SQLiteValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw lastSQLiteError() }
            let count = sqlite3_column_count(statement)
            var row: [SQLiteValue] = []
            for index in 0..<count {
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    let value = sqlite3_column_int64(statement, index)
                    row.append(SQLiteValue(text: nil, int64: value, double: Double(value), blob: nil))
                case SQLITE_FLOAT:
                    let value = sqlite3_column_double(statement, index)
                    row.append(SQLiteValue(text: nil, int64: Int64(value), double: value, blob: nil))
                case SQLITE_TEXT:
                    let value = sqlite3_column_text(statement, index).map { String(cString: $0) }
                    row.append(SQLiteValue(text: value, int64: nil, double: nil, blob: nil))
                case SQLITE_BLOB:
                    let bytes = sqlite3_column_blob(statement, index)
                    let length = Int(sqlite3_column_bytes(statement, index))
                    let data = bytes.map { Data(bytes: $0, count: length) }
                    row.append(SQLiteValue(text: nil, int64: nil, double: nil, blob: data))
                default:
                    row.append(SQLiteValue(text: nil, int64: nil, double: nil, blob: nil))
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer?) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case .nullableText(let value):
                if let value { result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) }
                else { result = sqlite3_bind_null(statement, index) }
            case .int(let value):
                result = sqlite3_bind_int(statement, index, Int32(value))
            case .int64(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .nullableDouble(let value):
                if let value { result = sqlite3_bind_double(statement, index, value) }
                else { result = sqlite3_bind_null(statement, index) }
            case .blob(let data):
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            }
            guard result == SQLITE_OK else { throw lastSQLiteError() }
        }
    }

    private func lastSQLiteError() -> SQLiteNativeSourceSearchError {
        SQLiteNativeSourceSearchError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
}

public enum SQLiteNativeSourceSearchError: Error, Sendable, Equatable, CustomStringConvertible {
    case openFailed(String)
    case sqlite(String)

    public var description: String {
        switch self {
        case .openFailed(let message): "openFailed(\(message))"
        case .sqlite(let message): "sqlite(\(message))"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
