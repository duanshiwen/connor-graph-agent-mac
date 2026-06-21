import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Native Source Search Snippet Tests")
struct NativeSourceSearchSnippetTests {
    @Test func snippetPrefersBestMatchedField() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(
                id: "summary-match",
                title: "Weekly note",
                summary: "Project Phoenix launch decision is in the summary.",
                body: "Long unrelated body text."
            )
        ])

        let results = try await service.search(NativeSearchQuery(text: "phoenix launch", includeBodySnippets: true))

        #expect(results.first?.snippet.contains("Project Phoenix launch") == true)
    }

    @Test func snippetFallsBackToSummaryWhenBodyMissing() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "summary-only", title: "Note", summary: "Important search update", body: nil)
        ])

        let results = try await service.search(NativeSearchQuery(text: "search", includeBodySnippets: true))

        #expect(results.first?.snippet == "Important search update")
    }

    @Test func highlightsOnlyContainMatchedTerms() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "one", title: "Project Phoenix", summary: "No launch word here", body: nil)
        ])

        let results = try await service.search(NativeSearchQuery(text: "project phoenix missing"))

        #expect(results.first?.highlights == ["project", "phoenix"])
    }

    @Test func snippetHandlesChineseMatchBoundaries() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "cn", title: "中文", summary: "摘要", body: "这是一封讨论搜索性能优化边界处理的长邮件。")
        ])

        let results = try await service.search(NativeSearchQuery(text: "性能优化", includeBodySnippets: true))

        #expect(results.first?.snippet.contains("搜索性能优化") == true)
    }

    private func document(id: String, title: String, summary: String, body: String?) -> NativeSearchDocument {
        NativeSearchDocument(
            id: id,
            sourceKind: .mail,
            externalID: id,
            title: title,
            summary: summary,
            body: body,
            temporal: NativeSearchTemporalMetadata(sentAt: Date(timeIntervalSince1970: 10_000)),
            contentHash: id
        )
    }
}
