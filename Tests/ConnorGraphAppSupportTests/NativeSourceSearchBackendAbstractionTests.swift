import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Native Source Search Backend Abstraction Tests")
struct NativeSourceSearchBackendAbstractionTests {
    @Test func nativeSourceSearchServiceConformsToBackendProtocol() async throws {
        let backend: any NativeSourceSearchBackend = NativeSourceSearchService()
        let document = NativeSearchDocument(
            id: "mail-1",
            sourceKind: .mail,
            externalID: "mail-1",
            title: "Project Phoenix",
            summary: "Search backend abstraction",
            temporal: NativeSearchTemporalMetadata(sentAt: Date(timeIntervalSince1970: 1_000)),
            contentHash: "hash-1"
        )

        try await backend.upsert([document])
        let results = try await backend.search(NativeSearchQuery(text: "phoenix"))
        let health = await backend.health()

        #expect(results.map(\.id) == ["mail-1"])
        #expect(health.documentCountBySource[.mail] == 1)
    }

    @Test func backendProtocolSupportsRebuildAndDeleteSource() async throws {
        let backend: any NativeSourceSearchBackend = NativeSourceSearchService()
        let old = NativeSearchDocument(
            id: "rss-old",
            sourceKind: .rss,
            sourceInstanceID: "feed-1",
            externalID: "rss-old",
            title: "Old item",
            summary: "old",
            temporal: NativeSearchTemporalMetadata(publishedAt: Date(timeIntervalSince1970: 1_000)),
            contentHash: "old"
        )
        let replacement = NativeSearchDocument(
            id: "rss-new",
            sourceKind: .rss,
            sourceInstanceID: "feed-1",
            externalID: "rss-new",
            title: "New item",
            summary: "new",
            temporal: NativeSearchTemporalMetadata(publishedAt: Date(timeIntervalSince1970: 2_000)),
            contentHash: "new"
        )

        try await backend.upsert([old])
        try await backend.rebuildSource(kind: .rss, sourceInstanceID: "feed-1", documents: [replacement])
        #expect(try await backend.search(NativeSearchQuery(text: "old", sourceKinds: [.rss])).isEmpty)
        #expect(try await backend.search(NativeSearchQuery(text: "new", sourceKinds: [.rss])).map(\.id) == ["rss-new"])

        try await backend.deleteBySource(kind: .rss, sourceInstanceID: "feed-1")
        #expect(try await backend.search(NativeSearchQuery(text: "new", sourceKinds: [.rss])).isEmpty)
    }
}
