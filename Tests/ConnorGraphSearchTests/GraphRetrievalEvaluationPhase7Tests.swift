import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch

private struct FixedGraphHybridSearchService: GraphHybridSearchService {
    var responses: [String: GraphSearchResponse]

    func search(query: GraphSearchQuery) async throws -> GraphSearchResponse {
        responses[query.text] ?? GraphSearchResponse(hits: [])
    }
}

@Test func graphRetrievalEvaluatorComputesRankingMetricsAndRequiredCoverage() throws {
    let evaluationCase = GraphRetrievalEvaluationCase(
        id: "retrieval-preference",
        queryText: "retrieval preference",
        graphID: "default",
        limit: 3,
        judgments: [
            GraphRetrievalJudgment(ownerType: .statement, ownerID: "statement-retrieval", relevance: 3, isRequired: true),
            GraphRetrievalJudgment(ownerType: .episode, ownerID: "episode-source", relevance: 1)
        ],
        tags: ["phase-7", "ranking"]
    )
    let response = GraphSearchResponse(hits: [
        GraphSearchHit(ownerType: .entity, ownerID: "entity-noise", title: "Noise", text: "Not relevant", score: 0.9, retrievalMethod: "entity_fts_v3"),
        GraphSearchHit(ownerType: .statement, ownerID: "statement-retrieval", title: "Retrieval", text: "Relevant retrieval fact", score: 0.8, retrievalMethod: "statement_fts_v3", metadata: ["matched_terms": "retrieval", "rerank_reasons": "lexical_overlap"]),
        GraphSearchHit(ownerType: .episode, ownerID: "episode-source", title: "Source", text: "Supporting source", score: 0.7, retrievalMethod: "source_episode_v1")
    ])

    let result = GraphRetrievalEvaluator.evaluate(evaluationCase: evaluationCase, response: response)

    #expect(result.hits.map(\.id) == ["entity:entity-noise", "statement:statement-retrieval", "episode:episode-source"])
    #expect(result.metrics.precisionAtK.isApproximatelyEqual(to: 2.0 / 3.0))
    #expect(result.metrics.recallAtK == 1.0)
    #expect(result.metrics.hitRateAtK == 1.0)
    #expect(result.metrics.meanReciprocalRank == 0.5)
    #expect(result.metrics.averagePrecision.isApproximatelyEqual(to: (0.5 + 2.0 / 3.0) / 2.0))
    #expect(result.metrics.normalizedDiscountedCumulativeGainAtK > 0.6)
    #expect(result.metrics.requiredHitRateAtK == 1.0)
    #expect(result.missingRequiredJudgmentIDs.isEmpty)
    #expect(result.hits[1].matchedTerms == "retrieval")
    #expect(result.hits[1].rerankReasons == "lexical_overlap")
}

@Test func graphRetrievalEvaluationHarnessRunsCasesAndAggregatesSummary() async throws {
    let relevantCase = GraphRetrievalEvaluationCase(
        id: "hit-case",
        queryText: "hit query",
        graphID: "default",
        limit: 2,
        judgments: [GraphRetrievalJudgment(ownerType: .statement, ownerID: "statement-hit", relevance: 1, isRequired: true)]
    )
    let missCase = GraphRetrievalEvaluationCase(
        id: "miss-case",
        queryText: "miss query",
        graphID: "default",
        limit: 2,
        judgments: [GraphRetrievalJudgment(ownerType: .statement, ownerID: "statement-missing", relevance: 1, isRequired: true)]
    )
    let service = FixedGraphHybridSearchService(responses: [
        "hit query": GraphSearchResponse(hits: [
            GraphSearchHit(ownerType: .statement, ownerID: "statement-hit", title: "Hit", text: "Relevant", score: 1, retrievalMethod: "statement_fts_v3")
        ]),
        "miss query": GraphSearchResponse(hits: [
            GraphSearchHit(ownerType: .entity, ownerID: "entity-noise", title: "Noise", text: "Noise", score: 1, retrievalMethod: "entity_fts_v3")
        ])
    ])
    let generatedAt = Date(timeIntervalSince1970: 1_782_000_000)
    let harness = GraphRetrievalEvaluationHarness(searchService: service, now: { generatedAt })

    let report = try await harness.run(cases: [relevantCase, missCase], k: 2)

    #expect(report.generatedAt == generatedAt)
    #expect(report.k == 2)
    #expect(report.caseResults.count == 2)
    #expect(report.caseResults[0].metrics.hitRateAtK == 1.0)
    #expect(report.caseResults[1].metrics.hitRateAtK == 0.0)
    #expect(report.caseResults[1].missingRequiredJudgmentIDs == ["statement:statement-missing"])
    #expect(report.summary.hitRateAtK == 0.5)
    #expect(report.summary.requiredHitRateAtK == 0.5)
}

@Test func graphRetrievalEvaluationCaseRoundTripsAsJSONManifest() throws {
    let evaluationCase = GraphRetrievalEvaluationCase(
        id: "multi-hop-case",
        queryText: "who connects alice to carol",
        graphID: "default",
        limit: 5,
        includeEntities: false,
        centerEntityIDs: ["entity-alice"],
        reranking: GraphRerankingConfig(strategies: [.graphitiLocal, .maximalMarginalRelevance], graphExpansionDepth: 2, candidatePoolMultiplier: 4),
        judgments: [
            GraphRetrievalJudgment(ownerType: .statement, ownerID: "statement-bob-carol", relevance: 2, isRequired: true, note: "Second-hop bridge")
        ],
        tags: ["multi-hop", "graph-memory"],
        notes: "Phase 7 golden case"
    )

    let data = try JSONEncoder().encode(evaluationCase)
    let decoded = try JSONDecoder().decode(GraphRetrievalEvaluationCase.self, from: data)
    let query = decoded.searchQuery()

    #expect(decoded == evaluationCase)
    #expect(query.text == "who connects alice to carol")
    #expect(query.includeEntities == false)
    #expect(query.centerEntityIDs == ["entity-alice"])
    #expect(query.reranking.graphExpansionDepth == 2)
    #expect(query.reranking.candidatePoolMultiplier == 4)
}

private extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double = 0.000_001) -> Bool {
        abs(self - other) <= tolerance
    }
}
