import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Native Source Search Ranking Tests")
struct NativeSourceSearchRankingTests {
    @Test func titleMatchOutranksBodyOnlyMatch() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "body", title: "Weekly note", summary: "Update", body: "project phoenix appears in body only"),
            document(id: "title", title: "Project Phoenix", summary: "Update", body: "plain body")
        ])

        let results = try await service.search(NativeSearchQuery(text: "project phoenix"))

        #expect(results.map(\.id).prefix(2) == ["title", "body"])
    }

    @Test func multipleTermCoverageOutranksSingleTermMatch() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "single", title: "Project", summary: "Only project appears many times project project", body: nil),
            document(id: "coverage", title: "Project launch", summary: "Phoenix launch planning", body: nil)
        ])

        let results = try await service.search(NativeSearchQuery(text: "project phoenix launch"))

        #expect(results.first?.id == "coverage")
    }

    @Test func exactPhraseReceivesBoost() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "separate", title: "Phoenix project", summary: "The launch plan mentions project and phoenix separately", body: nil),
            document(id: "phrase", title: "Project Phoenix launch", summary: "Exact named initiative", body: nil)
        ])

        let results = try await service.search(NativeSearchQuery(text: "project phoenix"))

        #expect(results.first?.id == "phrase")
    }

    @Test func recentFirstProfileBoostsRecentDocumentsWithoutDestroyingRelevance() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "old-strong", title: "Project Phoenix launch plan", summary: "complete match", sentAt: Date(timeIntervalSince1970: 1_000)),
            document(id: "recent-weak", title: "Project", summary: "partial match", sentAt: Date())
        ])

        let results = try await service.search(NativeSearchQuery(text: "project phoenix launch", rankingProfile: .recentFirst))

        #expect(results.first?.id == "old-strong")
    }

    private func document(id: String, title: String, summary: String, body: String? = nil, sentAt: Date = Date(timeIntervalSince1970: 10_000)) -> NativeSearchDocument {
        NativeSearchDocument(
            id: id,
            sourceKind: .mail,
            externalID: id,
            title: title,
            summary: summary,
            body: body,
            temporal: NativeSearchTemporalMetadata(sentAt: sentAt),
            contentHash: id
        )
    }
}
