import Foundation
import Testing
@testable import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Native Source Search Browser History Quality Tests")
struct NativeSourceSearchBrowserHistoryQualityTests {
    @Test func browserHistoryGoldenQueriesReuseNativeEvaluationSuite() async throws {
        let backend = NativeSourceSearchService()
        let visitedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let records = [
            BrowserHistoryRecord(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                url: "https://sqlite.org/fts5.html",
                title: "SQLite FTS5 Extension",
                sessionID: "sqlite-session",
                sessionTitle: "Search Quality Research",
                visitedAt: visitedAt,
                contentMarkdown: "Official SQLite full text search documentation covering bm25 ranking and snippets."
            ),
            BrowserHistoryRecord(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                url: "https://developer.apple.com/design/human-interface-guidelines/searching",
                title: "Searching | Apple Human Interface Guidelines",
                sessionID: "design-session",
                sessionTitle: "Global Search UI",
                visitedAt: visitedAt.addingTimeInterval(60),
                contentMarkdown: "Guidance for search fields, result presentation, and user intent."
            ),
            BrowserHistoryRecord(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                url: "https://example.com/noisy-note",
                title: "Noisy scratch note",
                sessionID: "noise-session",
                sessionTitle: "Scratch",
                visitedAt: visitedAt.addingTimeInterval(120),
                contentMarkdown: String(repeating: "search ranking ", count: 60)
            )
        ]
        try await backend.upsert(records.map { NativeSourceSearchAdapters.browserHistoryDocument(from: $0) })

        let suite = NativeSearchEvaluationSuite(cases: [
            NativeSearchEvaluationCase(
                caseID: "browser-history-url-host",
                query: NativeSearchQuery(text: "sqlite fts5", sourceKinds: [.browserHistory], limit: 5, includeBodySnippets: true),
                expectedRelevantIDs: ["browser-history:22222222-2222-2222-2222-222222222222"],
                gradedRelevance: ["browser-history:22222222-2222-2222-2222-222222222222": 3]
            ),
            NativeSearchEvaluationCase(
                caseID: "browser-history-session-title",
                query: NativeSearchQuery(text: "Global Search UI", sourceKinds: [.browserHistory], limit: 5, includeBodySnippets: true),
                expectedRelevantIDs: ["browser-history:33333333-3333-3333-3333-333333333333"],
                gradedRelevance: ["browser-history:33333333-3333-3333-3333-333333333333": 3]
            ),
            NativeSearchEvaluationCase(
                caseID: "browser-history-title-beats-body-noise",
                query: NativeSearchQuery(text: "searching apple", sourceKinds: [.browserHistory], limit: 5, includeBodySnippets: true),
                expectedRelevantIDs: ["browser-history:33333333-3333-3333-3333-333333333333"],
                gradedRelevance: ["browser-history:33333333-3333-3333-3333-333333333333": 3]
            )
        ])

        let report = try await suite.evaluate(using: backend, k: 3)

        #expect(report.meanReciprocalRank >= 0.95)
        #expect(report.meanNDCGAtK >= 0.95)
    }
}
