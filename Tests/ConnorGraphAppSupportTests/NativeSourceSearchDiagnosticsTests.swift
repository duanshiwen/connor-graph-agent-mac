import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Native Source Search Diagnostics Tests")
struct NativeSourceSearchDiagnosticsTests {
    @Test func diagnosticsIncludeMatchedTermsAndFields() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "one", title: "Project Phoenix", summary: "Launch plan", body: "body")
        ])

        let results = try await service.search(NativeSearchQuery(text: "project phoenix"))
        let diagnostics = try #require(results.first?.diagnostics)

        #expect(diagnostics.matchedTerms == ["project", "phoenix"])
        #expect(diagnostics.matchedFields.contains("title"))
        #expect(diagnostics.matchedFieldScores["title"] != nil)
    }

    @Test func diagnosticsIncludeSoftStopWords() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "one", title: "Project update", summary: "summary", body: nil)
        ])

        let results = try await service.search(NativeSearchQuery(text: "the project"))
        let diagnostics = try #require(results.first?.diagnostics)

        #expect(diagnostics.queryTokens == ["the", "project"])
        #expect(diagnostics.softStopWords == ["the"])
        #expect(diagnostics.matchedTerms == ["project"])
    }

    @Test func diagnosticsIncludeRankReason() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "one", title: "Project Phoenix", summary: "summary", body: nil)
        ])

        let results = try await service.search(NativeSearchQuery(text: "project phoenix"))
        let diagnostics = try #require(results.first?.diagnostics)

        #expect(diagnostics.rankReason.contains("lexical"))
        #expect(diagnostics.rankReason.contains("freshness"))
    }

    @Test func diagnosticsExposeTimeReasonWhenTemporalFilterApplies() async throws {
        let service = NativeSourceSearchService()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 3_000)
        try await service.upsert([
            document(id: "one", title: "Project", summary: "summary", body: nil, sentAt: Date(timeIntervalSince1970: 2_000))
        ])

        let results = try await service.search(NativeSearchQuery(text: "project", temporalFilter: NativeSearchTemporalFilter(start: start, end: end)))
        let diagnostics = try #require(results.first?.diagnostics)

        #expect(diagnostics.timeReason.contains("pointWithinRange"))
        #expect(diagnostics.timeReason.contains("sentAt"))
    }

    private func document(id: String, title: String, summary: String, body: String?, sentAt: Date = Date(timeIntervalSince1970: 10_000)) -> NativeSearchDocument {
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
