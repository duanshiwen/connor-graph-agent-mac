import Foundation
import Testing
@testable import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Native Source Search Pagination Tests")
struct NativeSourceSearchPaginationTests {
    @Test func firstPageReturnsNextCursorAndSecondPageContinuesWithoutDuplicates() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert((0..<5).map { index in
            document(id: "doc-\(index)", title: "Search item \(index)", time: Date(timeIntervalSince1970: 1_720_000_000 + Double(index)))
        })

        let query = NativeSearchQuery(text: "search", temporalSort: .timeAscThenRelevance, limit: 2)
        let first = try await service.searchPage(NativeSearchPageRequest(query: query, pageSize: 2))
        let second = try await service.searchPage(NativeSearchPageRequest(query: query, pageSize: 2, cursor: first.nextCursor))

        #expect(first.results.map(\.id) == ["doc-0", "doc-1"])
        #expect(second.results.map(\.id) == ["doc-2", "doc-3"])
        #expect(Set(first.results.map(\.id)).isDisjoint(with: Set(second.results.map(\.id))))
        #expect(first.nextCursor != nil)
        #expect(second.nextCursor != nil)
    }

    @Test func cursorIsStableAcrossBackendRestart() async throws {
        let url = temporaryIndexURL()
        let firstService = NativeSourceSearchService(indexURL: url)
        try await firstService.upsert((0..<4).map { index in
            document(id: "doc-\(index)", title: "Restart item \(index)", time: Date(timeIntervalSince1970: 1_720_000_000 + Double(index)))
        })
        let query = NativeSearchQuery(text: "restart", temporalSort: .timeAscThenRelevance, limit: 2)
        let first = try await firstService.searchPage(NativeSearchPageRequest(query: query, pageSize: 2))

        let restarted = NativeSourceSearchService(indexURL: url)
        let second = try await restarted.searchPage(NativeSearchPageRequest(query: query, pageSize: 2, cursor: first.nextCursor))

        #expect(second.results.map(\.id) == ["doc-2", "doc-3"])
        #expect(second.nextCursor == nil)
    }

    @Test func invalidCursorFailsClosed() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([document(id: "doc", title: "Invalid cursor", time: Date())])

        await #expect(throws: NativeSearchPaginationError.self) {
            _ = try await service.searchPage(NativeSearchPageRequest(query: NativeSearchQuery(text: "cursor"), pageSize: 1, cursor: "not-a-cursor"))
        }
    }

    @Test func changingQueryInvalidatesCursor() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert((0..<3).map { index in document(id: "doc-\(index)", title: "Alpha beta \(index)", time: Date(timeIntervalSince1970: Double(index))) })
        let first = try await service.searchPage(NativeSearchPageRequest(query: NativeSearchQuery(text: "alpha", limit: 1), pageSize: 1))

        await #expect(throws: NativeSearchPaginationError.self) {
            _ = try await service.searchPage(NativeSearchPageRequest(query: NativeSearchQuery(text: "beta", limit: 1), pageSize: 1, cursor: first.nextCursor))
        }
    }

    @Test func sqliteBackendSupportsCursorPagination() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        try await backend.upsert((0..<3).map { index in document(id: "sql-\(index)", title: "SQLite page \(index)", time: Date(timeIntervalSince1970: Double(index))) })
        let query = NativeSearchQuery(text: "sqlite", temporalSort: .timeAscThenRelevance, limit: 1)

        let first = try await backend.searchPage(NativeSearchPageRequest(query: query, pageSize: 1))
        let second = try await backend.searchPage(NativeSearchPageRequest(query: query, pageSize: 1, cursor: first.nextCursor))

        #expect(first.results.map(\.id) == ["sql-0"])
        #expect(second.results.map(\.id) == ["sql-1"])
    }

    private func temporaryIndexURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("native-search-page-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("native-search-page-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func document(id: String, title: String, time: Date) -> NativeSearchDocument {
        NativeSearchDocument(
            id: id,
            sourceKind: .rss,
            externalID: id,
            title: title,
            summary: title,
            body: title,
            temporal: NativeSearchTemporalMetadata(primaryTime: time, primaryTimeKind: .publishedAt, publishedAt: time, indexedAt: time),
            contentHash: "hash-\(id)"
        )
    }
}
