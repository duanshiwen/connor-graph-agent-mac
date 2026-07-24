import Foundation
import SQLite3
import ConnorGraphCore

public actor FileBackedRSSSourceRepository: RSSSourceRepository {
    private let storageURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageDirectory: URL, fileManager: FileManager = .default) {
        self.storageURL = storageDirectory.appendingPathComponent("sources.json")
        self.fileManager = fileManager
        self.encoder = rssStorageJSONEncoder()
        self.decoder = rssStorageJSONDecoder()
    }

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storageURL = storagePaths.sourcesDirectory.appendingPathComponent("rss", isDirectory: true).appendingPathComponent("sources.json")
        self.fileManager = fileManager
        self.encoder = rssStorageJSONEncoder()
        self.decoder = rssStorageJSONDecoder()
    }

    public func listSources() async throws -> [RSSSource] {
        try loadSources().sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func source(id: RSSSourceID) async throws -> RSSSource? {
        try loadSources().first { $0.id == id }
    }

    public func saveSource(_ source: RSSSource) async throws {
        var sources = try loadSources()
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = source
        } else {
            sources.append(source)
        }
        try saveSources(sources)
    }

    public func deleteSource(id: RSSSourceID) async throws {
        let sources = try loadSources().filter { $0.id != id }
        try saveSources(sources)
    }

    private func loadSources() throws -> [RSSSource] {
        guard fileManager.fileExists(atPath: storageURL.path) else { return [] }
        let data = try Data(contentsOf: storageURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([RSSSource].self, from: data)
    }

    private func saveSources(_ sources: [RSSSource]) throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(sources)
        try writeAtomically(data, to: storageURL, fileManager: fileManager)
    }
}

public actor FileBackedRSSSourceCache: TimeAwareRSSSourceCache {
    private nonisolated(unsafe) let db: OpaquePointer
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let searchService: (any NativeSourceSearchBackend)?

    public init(storageDirectory: URL, fileManager: FileManager = .default, searchService: (any NativeSourceSearchBackend)? = nil) {
        let legacyURL = storageDirectory.appendingPathComponent("items.json")
        let databaseURL = storageDirectory.appendingPathComponent("items.sqlite")
        let encoder = rssStorageJSONEncoder()
        let decoder = rssStorageJSONDecoder()
        self.db = rssOpenDatabase(databaseURL: databaseURL, fileManager: fileManager)
        self.encoder = encoder
        self.decoder = decoder
        self.searchService = searchService
        rssMigrateLegacyItemsIfNeeded(db: db, legacyURL: legacyURL, fileManager: fileManager, encoder: encoder, decoder: decoder)
    }

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default, searchService: (any NativeSourceSearchBackend)? = nil) {
        let directory = storagePaths.sourcesDirectory.appendingPathComponent("rss", isDirectory: true)
        let legacyURL = directory.appendingPathComponent("items.json")
        let databaseURL = directory.appendingPathComponent("items.sqlite")
        let encoder = rssStorageJSONEncoder()
        let decoder = rssStorageJSONDecoder()
        self.db = rssOpenDatabase(databaseURL: databaseURL, fileManager: fileManager)
        self.encoder = encoder
        self.decoder = decoder
        self.searchService = searchService
        rssMigrateLegacyItemsIfNeeded(db: db, legacyURL: legacyURL, fileManager: fileManager, encoder: encoder, decoder: decoder)
    }

    deinit {
        sqlite3_close(db)
    }

    public func listItems(sourceID: RSSSourceID? = nil, includeHidden: Bool = false) async throws -> [RSSItemSummary] {
        try loadAllPages(query: "", sourceID: sourceID, includeHidden: includeHidden)
    }

    public func searchItems(query: String, sourceID: RSSSourceID? = nil, includeHidden: Bool = false) async throws -> [RSSItemSummary] {
        try loadAllPages(query: query, sourceID: sourceID, includeHidden: includeHidden)
    }

    public func searchItems(query: String, sourceID: RSSSourceID? = nil, includeHidden: Bool = false, temporalFilter: NativeSearchTemporalFilter?, temporalSort: NativeSearchTemporalSort, limit: Int) async throws -> [RSSItemSummary] {
        let limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        if let searchService {
            let results = try await searchService.search(NativeSearchQuery(
                text: query,
                sourceKinds: [.rss],
                sourceInstanceIDs: sourceID.map { Set([$0.rawValue]) },
                temporalFilter: temporalFilter,
                temporalSort: temporalSort,
                limit: limit,
                includeHidden: includeHidden,
                rankingProfile: .recentFirst
            ))
            var summaries: [RSSItemSummary] = []
            summaries.reserveCapacity(results.count)
            for result in results {
                if let detail = try await item(id: RSSItemID(rawValue: result.externalID)) {
                    summaries.append(detail.summary)
                }
            }
            return summaries
        }
        let all = try loadAllPages(query: query, sourceID: sourceID, includeHidden: includeHidden)
        let filtered = temporalFilter.map { filter in all.filter { item in
            filter.contains(NativeSearchTemporalMetadata(primaryTime: item.publishedAt, primaryTimeKind: .publishedAt, publishedAt: item.publishedAt, fetchedAt: item.fetchedAt), sourceKind: .rss)
        } } ?? all
        let sorted = filtered.sorted { lhs, rhs in temporalSort == .timeAscThenRelevance || temporalSort == .relevanceThenTimeAsc ? lhs.publishedAt < rhs.publishedAt : lhs.publishedAt > rhs.publishedAt }
        return Array(sorted.prefix(limit))
    }

    public func itemPage(_ request: RSSItemPageRequest) async throws -> RSSItemPage {
        let cursor = try request.cursor.map(RSSSQLiteCursor.decode)
        var conditions: [String] = []
        if let sourceID = request.sourceID { conditions.append("source_id = '\(rssEscape(sourceID.rawValue))'") }
        if !request.includeHidden { conditions.append("is_hidden = 0") }
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let term = rssEscapeLike(query)
            conditions.append("(title LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR snippet LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR author LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR search_text LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE)")
        }
        if let cursor {
            let date = rssISO8601(cursor.publishedAt)
            conditions.append("(published_at < '\(rssEscape(date))' OR (published_at = '\(rssEscape(date))' AND id > '\(rssEscape(cursor.id))'))")
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
        let rows = try rssQuery(db: db, sql: "SELECT raw_json FROM rss_items \(whereClause) ORDER BY published_at DESC, id ASC LIMIT \(request.pageSize + 1)")
        let details = try rows.map { try decoder.decode(RSSItemDetail.self, from: Data($0[0].utf8)) }
        let pageDetails = Array(details.prefix(request.pageSize))
        let hasNext = details.count > request.pageSize
        let nextCursor = hasNext ? try pageDetails.last.map { try RSSSQLiteCursor(publishedAt: $0.summary.publishedAt, id: $0.id.rawValue).encode() } : nil
        return RSSItemPage(items: pageDetails.map(\.summary), nextCursor: nextCursor)
    }

    public func item(id: RSSItemID) async throws -> RSSItemDetail? {
        let rows = try rssQuery(db: db, sql: "SELECT raw_json FROM rss_items WHERE id = '\(rssEscape(id.rawValue))' LIMIT 1")
        return try rows.first.map { try decoder.decode(RSSItemDetail.self, from: Data($0[0].utf8)) }
    }

    public func upsertItems(_ newItems: [RSSItemDetail]) async throws -> (inserted: Int, duplicates: Int) {
        guard !newItems.isEmpty else { return (inserted: 0, duplicates: 0) }
        var inserted = 0
        var duplicates = 0
        try rssExecute(db: db, sql: "BEGIN IMMEDIATE")
        var insertedItems: [RSSItemDetail] = []
        defer { if sqlite3_get_autocommit(db) == 0 { try? rssExecute(db: db, sql: "ROLLBACK") } }
        for newItem in newItems {
            if try itemExists(id: newItem.id) {
                duplicates += 1
            } else {
                try saveItem(newItem)
                insertedItems.append(newItem)
                inserted += 1
            }
        }
        try rssExecute(db: db, sql: "COMMIT")
        try await searchService?.upsert(insertedItems.map(NativeSourceSearchAdapters.rssDocument(from:)))
        return (inserted, duplicates)
    }

    public func updateState(itemIDs: [RSSItemID], transform: @Sendable (RSSItemState) -> RSSItemState) async throws {
        guard !itemIDs.isEmpty else { return }
        var changed: [RSSItemDetail] = []
        for id in itemIDs {
            guard var detail = try await item(id: id) else { continue }
            detail.summary.state = transform(detail.summary.state)
            try saveItem(detail)
            changed.append(detail)
        }
        if !changed.isEmpty {
            try await searchService?.upsert(changed.map(NativeSourceSearchAdapters.rssDocument(from:)))
        }
    }

    public func deleteItems(sourceID: RSSSourceID) async throws {
        try rssExecute(db: db, sql: "DELETE FROM rss_items WHERE source_id = '\(rssEscape(sourceID.rawValue))'")
        try await searchService?.deleteBySource(kind: .rss, sourceInstanceID: sourceID.rawValue)
    }

    private func loadAllPages(query: String, sourceID: RSSSourceID?, includeHidden: Bool) throws -> [RSSItemSummary] {
        var cursor: String?
        var result: [RSSItemSummary] = []
        repeat {
            let page = try synchronousPage(.init(query: query, sourceID: sourceID, includeHidden: includeHidden, pageSize: 100, cursor: cursor))
            result.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return result
    }

    private func synchronousPage(_ request: RSSItemPageRequest) throws -> RSSItemPage {
        let cursor = try request.cursor.map(RSSSQLiteCursor.decode)
        var conditions: [String] = []
        if let sourceID = request.sourceID { conditions.append("source_id = '\(rssEscape(sourceID.rawValue))'") }
        if !request.includeHidden { conditions.append("is_hidden = 0") }
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let term = rssEscapeLike(query)
            conditions.append("(title LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR snippet LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR author LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE OR search_text LIKE '%\(term)%' ESCAPE '\\' COLLATE NOCASE)")
        }
        if let cursor {
            let date = rssISO8601(cursor.publishedAt)
            conditions.append("(published_at < '\(rssEscape(date))' OR (published_at = '\(rssEscape(date))' AND id > '\(rssEscape(cursor.id))'))")
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
        let rows = try rssQuery(db: db, sql: "SELECT raw_json FROM rss_items \(whereClause) ORDER BY published_at DESC, id ASC LIMIT \(request.pageSize + 1)")
        let details = try rows.map { try decoder.decode(RSSItemDetail.self, from: Data($0[0].utf8)) }
        let pageDetails = Array(details.prefix(request.pageSize))
        return RSSItemPage(items: pageDetails.map(\.summary), nextCursor: details.count > request.pageSize ? try pageDetails.last.map { try RSSSQLiteCursor(publishedAt: $0.summary.publishedAt, id: $0.id.rawValue).encode() } : nil)
    }

    private func itemExists(id: RSSItemID) throws -> Bool {
        !(try rssQuery(db: db, sql: "SELECT 1 FROM rss_items WHERE id = '\(rssEscape(id.rawValue))' LIMIT 1")).isEmpty
    }

    private func saveItem(_ item: RSSItemDetail) throws {
        let json = String(decoding: try encoder.encode(item), as: UTF8.self)
        try rssExecute(db: db, sql: """
        INSERT OR REPLACE INTO rss_items(id, source_id, published_at, fetched_at, title, snippet, author, search_text, is_hidden, raw_json)
        VALUES ('\(rssEscape(item.id.rawValue))', '\(rssEscape(item.summary.sourceID.rawValue))', '\(rssEscape(rssISO8601(item.summary.publishedAt)))', '\(rssEscape(rssISO8601(item.summary.fetchedAt)))', '\(rssEscape(item.summary.title))', '\(rssEscape(item.summary.snippet))', '\(rssEscape(item.summary.author ?? ""))', '\(rssEscape(item.content?.plainText ?? item.content?.safeMarkdown ?? ""))', \(item.summary.state.isHidden ? 1 : 0), '\(rssEscape(json))')
        """)
    }
}

private struct RSSSQLiteCursor: Codable {
    var publishedAt: Date
    var id: String

    func encode() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self).base64EncodedString()
    }

    static func decode(_ raw: String) throws -> Self {
        guard let data = Data(base64Encoded: raw) else { throw RSSRuntimeError.invalidCursor }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(Self.self, from: data) else { throw RSSRuntimeError.invalidCursor }
        return value
    }
}

private func rssOpenDatabase(databaseURL: URL, fileManager: FileManager) -> OpaquePointer {
    do {
        try fileManager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
        preconditionFailure("Unable to create RSS database directory: \(error)")
    }
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
        preconditionFailure("Unable to open RSS database at \(databaseURL.path)")
    }
    do {
        try rssExecute(db: database, sql: "PRAGMA journal_mode = WAL")
        try rssExecute(db: database, sql: "PRAGMA synchronous = NORMAL")
        try rssExecute(db: database, sql: "PRAGMA busy_timeout = 5000")
        try rssExecute(db: database, sql: """
        CREATE TABLE IF NOT EXISTS rss_items(
            id TEXT PRIMARY KEY,
            source_id TEXT NOT NULL,
            published_at TEXT NOT NULL,
            fetched_at TEXT NOT NULL,
            title TEXT NOT NULL,
            snippet TEXT NOT NULL,
            author TEXT NOT NULL,
            search_text TEXT NOT NULL DEFAULT '',
            is_hidden INTEGER NOT NULL DEFAULT 0,
            raw_json TEXT NOT NULL
        )
        """)
        try? rssExecute(db: database, sql: "ALTER TABLE rss_items ADD COLUMN search_text TEXT NOT NULL DEFAULT ''")
        try rssExecute(db: database, sql: "CREATE INDEX IF NOT EXISTS idx_rss_items_page ON rss_items(published_at DESC, id ASC)")
        try rssExecute(db: database, sql: "CREATE INDEX IF NOT EXISTS idx_rss_items_source_page ON rss_items(source_id, published_at DESC, id ASC)")
    } catch {
        sqlite3_close(database)
        preconditionFailure("Unable to initialize RSS database: \(error)")
    }
    return database
}

private func rssMigrateLegacyItemsIfNeeded(db: OpaquePointer, legacyURL: URL, fileManager: FileManager, encoder: JSONEncoder, decoder: JSONDecoder) {
    guard (try? rssQuery(db: db, sql: "SELECT 1 FROM rss_items LIMIT 1").isEmpty) == true,
          fileManager.fileExists(atPath: legacyURL.path),
          let data = try? Data(contentsOf: legacyURL),
          let items = try? decoder.decode([RSSItemDetail].self, from: data),
          !items.isEmpty else { return }
    do {
        try rssExecute(db: db, sql: "BEGIN IMMEDIATE")
        for item in items {
            let json = String(decoding: try encoder.encode(item), as: UTF8.self)
            try rssExecute(db: db, sql: """
            INSERT OR IGNORE INTO rss_items(id, source_id, published_at, fetched_at, title, snippet, author, search_text, is_hidden, raw_json)
            VALUES ('\(rssEscape(item.id.rawValue))', '\(rssEscape(item.summary.sourceID.rawValue))', '\(rssEscape(rssISO8601(item.summary.publishedAt)))', '\(rssEscape(rssISO8601(item.summary.fetchedAt)))', '\(rssEscape(item.summary.title))', '\(rssEscape(item.summary.snippet))', '\(rssEscape(item.summary.author ?? ""))', '\(rssEscape(item.content?.plainText ?? item.content?.safeMarkdown ?? ""))', \(item.summary.state.isHidden ? 1 : 0), '\(rssEscape(json))')
            """)
        }
        try rssExecute(db: db, sql: "COMMIT")
    } catch {
        try? rssExecute(db: db, sql: "ROLLBACK")
    }
}

private func rssExecute(db: OpaquePointer, sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
        throw RSSRuntimeError.parseFailed(String(cString: sqlite3_errmsg(db)))
    }
}

private func rssQuery(db: OpaquePointer, sql: String) throws -> [[String]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw RSSRuntimeError.parseFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(statement) }
    var rows: [[String]] = []
    while true {
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            rows.append((0..<sqlite3_column_count(statement)).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
            })
        case SQLITE_DONE:
            return rows
        default:
            throw RSSRuntimeError.parseFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}

private func rssEscape(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "''")
}

private func rssEscapeLike(_ value: String) -> String {
    rssEscape(value)
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%")
        .replacingOccurrences(of: "_", with: "\\_")
}

private func rssISO8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func rssStorageJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func rssStorageJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func writeAtomically(_ data: Data, to url: URL, fileManager: FileManager) throws {
    let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
    try data.write(to: temporaryURL, options: [.atomic])
    if fileManager.fileExists(atPath: url.path) {
        _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
    } else {
        try fileManager.moveItem(at: temporaryURL, to: url)
    }
}
