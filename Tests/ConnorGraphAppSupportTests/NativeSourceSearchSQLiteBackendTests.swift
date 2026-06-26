import Foundation
import Testing
@testable import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Native Source Search SQLite Backend Tests")
struct NativeSourceSearchSQLiteBackendTests {
    @Test func sqliteBackendUpsertsAndSearchesFTSContent() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        try await backend.upsert([
            document(id: "mail-1", kind: .mail, title: "Q2 planning", summary: "roadmap", body: "Native search backend with SQLite FTS5")
        ])

        let results = try await backend.search(NativeSearchQuery(text: "SQLite FTS5", limit: 10))

        #expect(results.map(\.id) == ["mail-1"])
        #expect(results[0].diagnostics?.matchedTerms.contains("sqlite") == true)
    }

    @Test func sqliteBackendDeleteRemovesDocuments() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        try await backend.upsert([
            document(id: "rss-1", kind: .rss, title: "Search item", summary: "delete me", body: "backend deletion target")
        ])
        try await backend.delete(documentIDs: ["rss-1"])

        let results = try await backend.search(NativeSearchQuery(text: "deletion", limit: 10))

        #expect(results.isEmpty)
    }

    @Test func sqliteBackendRebuildSourceReplacesSourceDocuments() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        try await backend.upsert([
            document(id: "old", kind: .rss, sourceInstanceID: "feed-a", title: "Old item", summary: "legacy", body: "obsolete")
        ])
        try await backend.rebuildSource(kind: .rss, sourceInstanceID: "feed-a", documents: [
            document(id: "new", kind: .rss, sourceInstanceID: "feed-a", title: "New item", summary: "fresh", body: "replacement")
        ])

        let oldResults = try await backend.search(NativeSearchQuery(text: "obsolete", limit: 10))
        let newResults = try await backend.search(NativeSearchQuery(text: "replacement", limit: 10))

        #expect(oldResults.isEmpty)
        #expect(newResults.map(\.id) == ["new"])
    }

    @Test func sqliteBackendTemporalFilterUsesMetadata() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = Date(timeIntervalSince1970: 1_720_000_000)
        try await backend.upsert([
            document(id: "old", kind: .mail, title: "receipt", summary: "invoice", body: "travel receipt", time: old),
            document(id: "recent", kind: .mail, title: "receipt", summary: "invoice", body: "travel receipt", time: recent)
        ])

        let results = try await backend.search(NativeSearchQuery(
            text: "receipt",
            temporalFilter: NativeSearchTemporalFilter(start: Date(timeIntervalSince1970: 1_710_000_000), end: nil, mode: .pointWithinRange, timeFieldPreference: [.sentAt]),
            limit: 10
        ))

        #expect(results.map(\.id) == ["recent"])
        #expect(results[0].resultTimeLabel == "Sent")
    }

    @Test func sqliteBackendMatchesChineseQuery() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        try await backend.upsert([
            document(id: "cn", kind: .mail, title: "项目更新", summary: "", body: "我们需要优化搜索性能和索引质量")
        ])

        let results = try await backend.search(NativeSearchQuery(text: "搜索性能", limit: 10))

        #expect(results.map(\.id) == ["cn"])
        #expect(results[0].highlights.contains("搜索性能") || results[0].highlights.contains("搜索"))
    }

    @Test func sqliteBackendRanksSemanticChinesePhraseAboveBoundaryGramNoise() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        try await backend.upsert([
            document(id: "movie-real", kind: .rss, title: "西雅图不相信眼泪影评", summary: "完整影评", body: "这是一篇讨论西雅图不相信眼泪的电影评论。"),
            document(id: "movie-noise", kind: .rss, title: "咖啡地图", summary: "雅图 图不 不相 信眼", body: "雅图 图不 不相 信眼")
        ])

        let results = try await backend.search(NativeSearchQuery(text: "西雅图眼泪", sourceKinds: [.rss], limit: 10, includeBodySnippets: true))

        #expect(results.first?.id == "movie-real")
        #expect(results.map(\.id).contains("movie-real"))
    }

    @Test func sqliteBackendSearchesBrowserHistoryDocuments() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        let record = BrowserHistoryRecord(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            url: "https://developer.apple.com/documentation/swift",
            title: "Swift Documentation",
            sessionID: "session-history",
            sessionTitle: "Apple Docs",
            visitedAt: Date(timeIntervalSince1970: 1_780_000_000),
            contentMarkdown: "Language reference and API documentation."
        )
        try await backend.upsert([NativeSourceSearchAdapters.browserHistoryDocument(from: record)])

        let results = try await backend.search(NativeSearchQuery(text: "apple swift", sourceKinds: [.browserHistory], limit: 10, includeBodySnippets: true))

        #expect(results.map(\.id) == ["browser-history:55555555-5555-5555-5555-555555555555"])
        #expect(results.first?.sourceKind == .browserHistory)
        #expect(results.first?.diagnostics?.rankReason.contains("backend=sqlite-fts5") == true)
    }

    @Test func sqliteBackendHealthReportsCounts() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        try await backend.upsert([
            document(id: "mail", kind: .mail, title: "Mail", summary: "", body: "alpha"),
            document(id: "rss", kind: .rss, title: "RSS", summary: "", body: "alpha")
        ])

        let health = await backend.health()

        #expect(health.backendStatus == "ready:sqlite-fts5")
        #expect(health.documentCountBySource[.mail] == 1)
        #expect(health.documentCountBySource[.rss] == 1)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("native-search-sqlite-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func document(
        id: String,
        kind: NativeSearchSourceKind,
        sourceInstanceID: String? = nil,
        title: String,
        summary: String,
        body: String?,
        time: Date = Date(timeIntervalSince1970: 1_720_000_000)
    ) -> NativeSearchDocument {
        var temporal = NativeSearchTemporalMetadata(indexedAt: time)
        switch kind {
        case .mail:
            temporal.sentAt = time
            temporal.primaryTime = time
            temporal.primaryTimeKind = .sentAt
        case .rss:
            temporal.publishedAt = time
            temporal.primaryTime = time
            temporal.primaryTimeKind = .publishedAt
        case .calendar:
            temporal.eventStartAt = time
            temporal.eventEndAt = time.addingTimeInterval(3600)
            temporal.primaryTime = time
            temporal.primaryTimeKind = .eventStartAt
        case .browserHistory:
            temporal.updatedAt = time
            temporal.primaryTime = time
            temporal.primaryTimeKind = .updatedAt
        }
        return NativeSearchDocument(
            id: id,
            sourceKind: kind,
            sourceInstanceID: sourceInstanceID,
            externalID: id,
            title: title,
            summary: summary,
            body: body,
            temporal: temporal,
            contentHash: "hash-\(id)"
        )
    }
}
