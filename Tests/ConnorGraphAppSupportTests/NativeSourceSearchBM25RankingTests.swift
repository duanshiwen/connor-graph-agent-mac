import Foundation
import Testing
@testable import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Native Source Search BM25 Ranking Tests")
struct NativeSourceSearchBM25RankingTests {
    @Test func rareTermOutranksCommonOnlyMatch() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "common", title: "Search update", body: "search search search search"),
            document(id: "rare", title: "Search update", body: "search tantivy")
        ])

        let results = try await service.search(NativeSearchQuery(text: "search tantivy", limit: 10))

        #expect(results.first?.id == "rare")
        #expect(results.first?.diagnostics?.rankReason.contains("idf=") == true)
    }

    @Test func fieldBoostsStillApplyWithBM25() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "title", title: "Graph search", body: "notes"),
            document(id: "body", title: "Notes", body: "graph search graph search graph search")
        ])

        let results = try await service.search(NativeSearchQuery(text: "graph search", limit: 10))

        #expect(results.first?.id == "title")
    }

    @Test func documentLengthNormalizationWorks() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "short", title: "Report", body: "needle"),
            document(id: "long", title: "Report", body: String(repeating: "filler ", count: 300) + " needle")
        ])

        let results = try await service.search(NativeSearchQuery(text: "needle", limit: 10))

        #expect(results.first?.id == "short")
    }

    @Test func sqliteAndJSONBackendsHaveAlignedTopResult() async throws {
        let json = NativeSourceSearchService()
        let sqlite = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        let docs = [
            document(id: "a", title: "Launch search", body: "sqlite bm25 ranking"),
            document(id: "b", title: "Notes", body: "sqlite sqlite sqlite")
        ]
        try await json.upsert(docs)
        try await sqlite.upsert(docs)

        let query = NativeSearchQuery(text: "launch bm25", limit: 10)
        let jsonResults = try await json.search(query)
        let sqliteResults = try await sqlite.search(query)

        #expect(jsonResults.first?.id == sqliteResults.first?.id)
    }

    @Test func diagnosticsExposeBM25IDFReason() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([document(id: "doc", title: "BM25", body: "idf explainability")])

        let result = try #require(try await service.search(NativeSearchQuery(text: "idf", limit: 10)).first)

        #expect(result.diagnostics?.rankReason.contains("bm25=") == true)
        #expect(result.diagnostics?.rankReason.contains("idf=") == true)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("native-search-bm25-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func document(id: String, title: String, body: String) -> NativeSearchDocument {
        let time = Date(timeIntervalSince1970: 1_720_000_000)
        return NativeSearchDocument(
            id: id,
            sourceKind: .rss,
            externalID: id,
            title: title,
            summary: body,
            body: body,
            temporal: NativeSearchTemporalMetadata(primaryTime: time, primaryTimeKind: .publishedAt, publishedAt: time, indexedAt: time),
            contentHash: "hash-\(id)"
        )
    }
}
