import Foundation
import Testing
@testable import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Native Source Search Evaluation Metrics Tests")
struct NativeSourceSearchEvaluationMetricsTests {
    @Test func computesPrecisionRecallMRRAndNDCG() {
        let caseResult = NativeSearchEvaluationCaseResult(
            caseID: "metric",
            query: "alpha",
            expectedRelevantIDs: ["a", "c"],
            gradedRelevance: ["a": 3, "c": 1],
            actualRankedIDs: ["a", "b", "c"],
            diagnosticsByID: [:]
        )

        let metrics = caseResult.metrics(k: 3)

        #expect(metrics.precisionAtK == 2.0 / 3.0)
        #expect(metrics.recallAtK == 1.0)
        #expect(metrics.mrr == 1.0)
        #expect(metrics.ndcgAtK > 0.9)
    }

    @Test func evaluationSuitePassesMinimumThresholds() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "mail-urgent", kind: .mail, title: "Urgent launch mail", body: "project launch decision"),
            document(id: "rss-search", kind: .rss, title: "Search ranking notes", body: "bm25 idf search quality"),
            document(id: "calendar-review", kind: .calendar, title: "Launch review", body: "calendar launch review", location: "杭州")
        ])
        let suite = NativeSearchEvaluationSuite(cases: [
            NativeSearchEvaluationCase(caseID: "mail", query: NativeSearchQuery(text: "urgent launch", sourceKinds: [.mail], limit: 5), expectedRelevantIDs: ["mail-urgent"]),
            NativeSearchEvaluationCase(caseID: "rss", query: NativeSearchQuery(text: "bm25 search", sourceKinds: [.rss], limit: 5), expectedRelevantIDs: ["rss-search"]),
            NativeSearchEvaluationCase(caseID: "calendar", query: NativeSearchQuery(text: "launch review", sourceKinds: [.calendar], limit: 5), expectedRelevantIDs: ["calendar-review"])
        ])

        let report = try await suite.evaluate(using: service, k: 5)

        #expect(report.averagePrecisionAtK >= 0.6)
        #expect(report.averageRecallAtK == 1.0)
        #expect(report.meanReciprocalRank == 1.0)
        #expect(report.meanNDCGAtK == 1.0)
        #expect(report.passed(minimumPrecisionAtK: 0.6, minimumRecallAtK: 1.0, minimumMRR: 1.0, minimumNDCG: 1.0))
    }

    @Test func failureReportIncludesDiagnostics() async throws {
        let service = NativeSourceSearchService()
        try await service.upsert([
            document(id: "actual", kind: .rss, title: "Actual result", body: "visible token")
        ])
        let suite = NativeSearchEvaluationSuite(cases: [
            NativeSearchEvaluationCase(caseID: "failure", query: NativeSearchQuery(text: "visible", limit: 5), expectedRelevantIDs: ["expected"])
        ])

        let report = try await suite.evaluate(using: service, k: 5)
        let markdown = report.failureReportMarkdown()

        #expect(markdown.contains("failure"))
        #expect(markdown.contains("expected"))
        #expect(markdown.contains("actual"))
        #expect(markdown.contains("rankReason"))
    }

    private func document(id: String, kind: NativeSearchSourceKind, title: String, body: String, location: String? = nil) -> NativeSearchDocument {
        let time = Date(timeIntervalSince1970: 1_720_000_000)
        var temporal = NativeSearchTemporalMetadata(primaryTime: time, primaryTimeKind: .indexedAt, indexedAt: time)
        if kind == .mail { temporal.sentAt = time; temporal.primaryTimeKind = .sentAt }
        if kind == .rss { temporal.publishedAt = time; temporal.primaryTimeKind = .publishedAt }
        if kind == .calendar { temporal.eventStartAt = time; temporal.eventEndAt = time.addingTimeInterval(3600); temporal.primaryTimeKind = .eventStartAt }
        return NativeSearchDocument(
            id: id,
            sourceKind: kind,
            externalID: id,
            title: title,
            summary: body,
            body: body,
            location: location,
            temporal: temporal,
            contentHash: "hash-\(id)"
        )
    }
}
