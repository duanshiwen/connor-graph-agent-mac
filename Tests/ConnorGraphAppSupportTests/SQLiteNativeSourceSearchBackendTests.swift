import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("SQLite Native Source Search Backend Tests")
struct SQLiteNativeSourceSearchBackendTests {
    @Test func ftsSearchUsesMatchAndRanksByBM25() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        var documents: [NativeSearchDocument] = []
        for index in 0..<500 {
            documents.append(NativeSearchDocument(
                id: "noise-\(index)",
                sourceKind: .rss,
                externalID: "noise-\(index)",
                title: "普通旅行记录 \(index)",
                summary: "没有目标关键词的普通内容",
                body: "咖啡 城市 交通 天气",
                temporal: NativeSearchTemporalMetadata(primaryTime: Date(timeIntervalSince1970: Double(index)), primaryTimeKind: .publishedAt, publishedAt: Date(timeIntervalSince1970: Double(index))),
                contentHash: "noise-\(index)"
            ))
        }
        documents.append(NativeSearchDocument(
            id: "jakarta-luxury",
            sourceKind: .rss,
            externalID: "jakarta-luxury",
            title: "雅加达豪华酒店推荐",
            summary: "雅加达商务出差可选的豪华酒店。",
            body: "雅加达 豪华 酒店 推荐 套房 早餐 机场接送",
            temporal: NativeSearchTemporalMetadata(primaryTime: Date(timeIntervalSince1970: 10_000), primaryTimeKind: .publishedAt, publishedAt: Date(timeIntervalSince1970: 10_000)),
            contentHash: "jakarta-luxury"
        ))
        try await backend.upsert(documents)

        let results = try await backend.search(NativeSearchQuery(text: "雅加达 豪华酒店", sourceKinds: [.rss], limit: 3, includeBodySnippets: true))

        #expect(results.first?.id == "jakarta-luxury")
        #expect(results.first?.diagnostics?.rankReason.contains("backend=sqlite-fts5") == true)
        #expect(results.first?.diagnostics?.rankReason.contains("match=true") == true)
    }

    @Test func groupedSearchReturnsBucketsFromSingleQuery() async throws {
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: temporaryDatabaseURL())
        try await backend.upsert([
            NativeSearchDocument(id: "mail-1", sourceKind: .mail, externalID: "mail-1", title: "Project launch mail", summary: "Launch", contentHash: "m1"),
            NativeSearchDocument(id: "rss-1", sourceKind: .rss, externalID: "rss-1", title: "Project launch RSS", summary: "Launch", contentHash: "r1"),
            NativeSearchDocument(id: "browser-1", sourceKind: .browserHistory, externalID: "browser-1", title: "Project launch browser", summary: "Launch", contentHash: "b1")
        ])

        let grouped = try await backend.searchGrouped(
            NativeSearchQuery(text: "project launch", sourceKinds: [.mail, .rss, .browserHistory], limit: 20),
            limitsBySource: [.mail: 1, .rss: 1, .browserHistory: 1]
        )

        #expect(grouped[.mail]?.map(\.id) == ["mail-1"])
        #expect(grouped[.rss]?.map(\.id) == ["rss-1"])
        #expect(grouped[.browserHistory]?.map(\.id) == ["browser-1"])
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteNativeSourceSearchBackendTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("search.sqlite")
    }
}
