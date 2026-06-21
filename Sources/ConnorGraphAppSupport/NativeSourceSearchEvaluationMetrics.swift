import Foundation
import ConnorGraphCore

public struct NativeSearchEvaluationCase: Sendable, Equatable {
    public var caseID: String
    public var query: NativeSearchQuery
    public var expectedRelevantIDs: [String]
    public var gradedRelevance: [String: Double]

    public init(caseID: String, query: NativeSearchQuery, expectedRelevantIDs: [String], gradedRelevance: [String: Double] = [:]) {
        self.caseID = caseID
        self.query = query
        self.expectedRelevantIDs = expectedRelevantIDs
        self.gradedRelevance = gradedRelevance
    }
}

public struct NativeSearchEvaluationMetrics: Sendable, Equatable {
    public var precisionAtK: Double
    public var recallAtK: Double
    public var mrr: Double
    public var ndcgAtK: Double

    public init(precisionAtK: Double, recallAtK: Double, mrr: Double, ndcgAtK: Double) {
        self.precisionAtK = precisionAtK
        self.recallAtK = recallAtK
        self.mrr = mrr
        self.ndcgAtK = ndcgAtK
    }
}

public struct NativeSearchEvaluationCaseResult: Sendable, Equatable {
    public var caseID: String
    public var query: String
    public var expectedRelevantIDs: [String]
    public var gradedRelevance: [String: Double]
    public var actualRankedIDs: [String]
    public var diagnosticsByID: [String: NativeSearchResultDiagnostics]

    public init(
        caseID: String,
        query: String,
        expectedRelevantIDs: [String],
        gradedRelevance: [String: Double] = [:],
        actualRankedIDs: [String],
        diagnosticsByID: [String: NativeSearchResultDiagnostics] = [:]
    ) {
        self.caseID = caseID
        self.query = query
        self.expectedRelevantIDs = expectedRelevantIDs
        self.gradedRelevance = gradedRelevance
        self.actualRankedIDs = actualRankedIDs
        self.diagnosticsByID = diagnosticsByID
    }

    public func metrics(k: Int) -> NativeSearchEvaluationMetrics {
        let topK = Array(actualRankedIDs.prefix(k))
        let relevant = Set(expectedRelevantIDs)
        let hits = topK.filter { relevant.contains($0) }
        let precision = topK.isEmpty ? 0 : Double(hits.count) / Double(topK.count)
        let recall = relevant.isEmpty ? 1 : Double(hits.count) / Double(relevant.count)
        let reciprocalRank: Double
        if let index = actualRankedIDs.firstIndex(where: { relevant.contains($0) }) {
            reciprocalRank = 1.0 / Double(index + 1)
        } else {
            reciprocalRank = 0
        }
        let ndcg = ndcgAtK(topK: topK, k: k)
        return NativeSearchEvaluationMetrics(precisionAtK: precision, recallAtK: recall, mrr: reciprocalRank, ndcgAtK: ndcg)
    }

    private func ndcgAtK(topK: [String], k: Int) -> Double {
        let relevance = relevanceMap()
        func gain(_ id: String, rank: Int) -> Double {
            let rel = relevance[id] ?? 0
            guard rel > 0 else { return 0 }
            return (pow(2.0, rel) - 1.0) / log2(Double(rank + 2))
        }
        let dcg = topK.enumerated().reduce(0) { $0 + gain($1.element, rank: $1.offset) }
        let ideal = relevance.values.sorted(by: >).prefix(k).enumerated().reduce(0) { partial, pair in
            let rel = pair.element
            return partial + (pow(2.0, rel) - 1.0) / log2(Double(pair.offset + 2))
        }
        guard ideal > 0 else { return expectedRelevantIDs.isEmpty ? 1 : 0 }
        return dcg / ideal
    }

    private func relevanceMap() -> [String: Double] {
        if !gradedRelevance.isEmpty { return gradedRelevance }
        return Dictionary(uniqueKeysWithValues: expectedRelevantIDs.map { ($0, 1.0) })
    }
}

public struct NativeSearchEvaluationReport: Sendable, Equatable {
    public var results: [NativeSearchEvaluationCaseResult]
    public var k: Int

    public init(results: [NativeSearchEvaluationCaseResult], k: Int) {
        self.results = results
        self.k = k
    }

    public var averagePrecisionAtK: Double { average(\.precisionAtK) }
    public var averageRecallAtK: Double { average(\.recallAtK) }
    public var meanReciprocalRank: Double { average(\.mrr) }
    public var meanNDCGAtK: Double { average(\.ndcgAtK) }

    public func passed(minimumPrecisionAtK: Double, minimumRecallAtK: Double, minimumMRR: Double, minimumNDCG: Double) -> Bool {
        averagePrecisionAtK >= minimumPrecisionAtK &&
        averageRecallAtK >= minimumRecallAtK &&
        meanReciprocalRank >= minimumMRR &&
        meanNDCGAtK >= minimumNDCG
    }

    public func failureReportMarkdown() -> String {
        var lines: [String] = [
            "# Native Source Search Evaluation Report",
            "",
            "- precision@\(k): \(format(averagePrecisionAtK))",
            "- recall@\(k): \(format(averageRecallAtK))",
            "- MRR: \(format(meanReciprocalRank))",
            "- NDCG@\(k): \(format(meanNDCGAtK))",
            ""
        ]
        for result in results {
            let metrics = result.metrics(k: k)
            guard metrics.recallAtK < 1 || metrics.mrr < 1 else { continue }
            lines.append("## \(result.caseID)")
            lines.append("")
            lines.append("- query: \(result.query)")
            lines.append("- expected: \(result.expectedRelevantIDs.joined(separator: ", "))")
            lines.append("- actual: \(result.actualRankedIDs.joined(separator: ", "))")
            lines.append("- precision@\(k): \(format(metrics.precisionAtK)); recall@\(k): \(format(metrics.recallAtK)); MRR: \(format(metrics.mrr)); NDCG@\(k): \(format(metrics.ndcgAtK))")
            for id in result.actualRankedIDs.prefix(k) {
                if let diagnostics = result.diagnosticsByID[id] {
                    lines.append("  - \(id) rankReason: \(diagnostics.rankReason)")
                    lines.append("  - \(id) matchedTerms: \(diagnostics.matchedTerms.joined(separator: ", "))")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func average(_ keyPath: KeyPath<NativeSearchEvaluationMetrics, Double>) -> Double {
        guard !results.isEmpty else { return 0 }
        let values = results.map { $0.metrics(k: k)[keyPath: keyPath] }
        return values.reduce(0, +) / Double(values.count)
    }

    private func format(_ value: Double) -> String { String(format: "%.3f", value) }
}

public struct NativeSearchEvaluationSuite: Sendable, Equatable {
    public var cases: [NativeSearchEvaluationCase]

    public init(cases: [NativeSearchEvaluationCase]) {
        self.cases = cases
    }

    public func evaluate(using backend: any NativeSourceSearchBackend, k: Int = 10) async throws -> NativeSearchEvaluationReport {
        var results: [NativeSearchEvaluationCaseResult] = []
        for evaluationCase in cases {
            var query = evaluationCase.query
            query.limit = NativeSearchLimitPolicy.clampSearchLimit(max(query.limit, k))
            let searchResults = try await backend.search(query)
            let diagnostics = Dictionary(uniqueKeysWithValues: searchResults.compactMap { result -> (String, NativeSearchResultDiagnostics)? in
                guard let diagnostics = result.diagnostics else { return nil }
                return (result.id, diagnostics)
            })
            results.append(NativeSearchEvaluationCaseResult(
                caseID: evaluationCase.caseID,
                query: evaluationCase.query.text,
                expectedRelevantIDs: evaluationCase.expectedRelevantIDs,
                gradedRelevance: evaluationCase.gradedRelevance,
                actualRankedIDs: searchResults.map(\.id),
                diagnosticsByID: diagnostics
            ))
        }
        return NativeSearchEvaluationReport(results: results, k: k)
    }
}
