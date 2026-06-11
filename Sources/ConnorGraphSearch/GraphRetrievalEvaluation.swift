import Foundation
import ConnorGraphCore

public struct GraphRetrievalJudgment: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(ownerType.rawValue):\(ownerID)" }
    public var ownerType: GraphIndexOwnerType
    public var ownerID: String
    public var relevance: Int
    public var isRequired: Bool
    public var note: String?

    public init(
        ownerType: GraphIndexOwnerType,
        ownerID: String,
        relevance: Int = 1,
        isRequired: Bool = false,
        note: String? = nil
    ) {
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.relevance = max(0, relevance)
        self.isRequired = isRequired
        self.note = note
    }
}

public struct GraphRetrievalEvaluationCase: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var queryText: String
    public var graphID: String
    public var limit: Int
    public var includeEntities: Bool
    public var includeStatements: Bool
    public var includeEpisodes: Bool
    public var centerEntityIDs: [String]
    public var reranking: GraphRerankingConfig
    public var judgments: [GraphRetrievalJudgment]
    public var tags: [String]
    public var notes: String?

    public init(
        id: String,
        queryText: String,
        graphID: String,
        limit: Int = 10,
        includeEntities: Bool = true,
        includeStatements: Bool = true,
        includeEpisodes: Bool = true,
        centerEntityIDs: [String] = [],
        reranking: GraphRerankingConfig = GraphRerankingConfig(strategies: [.graphitiLocal, .episodeMentions]),
        judgments: [GraphRetrievalJudgment],
        tags: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.queryText = queryText
        self.graphID = graphID
        self.limit = max(1, limit)
        self.includeEntities = includeEntities
        self.includeStatements = includeStatements
        self.includeEpisodes = includeEpisodes
        self.centerEntityIDs = centerEntityIDs
        self.reranking = reranking
        self.judgments = judgments
        self.tags = tags
        self.notes = notes
    }

    public func searchQuery(referenceTime: Date? = nil) -> GraphSearchQuery {
        GraphSearchQuery(
            text: queryText,
            graphID: graphID,
            referenceTime: referenceTime,
            includeEntities: includeEntities,
            includeStatements: includeStatements,
            includeEpisodes: includeEpisodes,
            limit: limit,
            centerEntityIDs: centerEntityIDs,
            reranking: reranking
        )
    }
}

public struct GraphRetrievalEvaluationHit: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(ownerType.rawValue):\(ownerID)" }
    public var rank: Int
    public var ownerType: GraphIndexOwnerType
    public var ownerID: String
    public var title: String
    public var score: Double
    public var retrievalMethod: String
    public var sourceEpisodeIDs: [String]
    public var matchedTerms: String?
    public var rerankReasons: String?
    public var graphHop: String?

    public init(rank: Int, hit: GraphSearchHit) {
        self.rank = rank
        self.ownerType = hit.ownerType
        self.ownerID = hit.ownerID
        self.title = hit.title
        self.score = hit.score
        self.retrievalMethod = hit.retrievalMethod
        self.sourceEpisodeIDs = hit.sourceEpisodeIDs
        self.matchedTerms = hit.metadata["matched_terms"]
        self.rerankReasons = hit.metadata["rerank_reasons"]
        self.graphHop = hit.metadata["graph_hop"]
    }
}

public struct GraphRetrievalEvaluationMetrics: Sendable, Codable, Equatable {
    public var precisionAtK: Double
    public var recallAtK: Double
    public var hitRateAtK: Double
    public var meanReciprocalRank: Double
    public var averagePrecision: Double
    public var normalizedDiscountedCumulativeGainAtK: Double
    public var requiredHitRateAtK: Double

    public init(
        precisionAtK: Double = 0,
        recallAtK: Double = 0,
        hitRateAtK: Double = 0,
        meanReciprocalRank: Double = 0,
        averagePrecision: Double = 0,
        normalizedDiscountedCumulativeGainAtK: Double = 0,
        requiredHitRateAtK: Double = 0
    ) {
        self.precisionAtK = precisionAtK
        self.recallAtK = recallAtK
        self.hitRateAtK = hitRateAtK
        self.meanReciprocalRank = meanReciprocalRank
        self.averagePrecision = averagePrecision
        self.normalizedDiscountedCumulativeGainAtK = normalizedDiscountedCumulativeGainAtK
        self.requiredHitRateAtK = requiredHitRateAtK
    }
}

public struct GraphRetrievalEvaluationCaseResult: Sendable, Codable, Equatable, Identifiable {
    public var id: String { evaluationCase.id }
    public var evaluationCase: GraphRetrievalEvaluationCase
    public var k: Int
    public var metrics: GraphRetrievalEvaluationMetrics
    public var hits: [GraphRetrievalEvaluationHit]
    public var missingRequiredJudgmentIDs: [String]

    public init(
        evaluationCase: GraphRetrievalEvaluationCase,
        k: Int,
        metrics: GraphRetrievalEvaluationMetrics,
        hits: [GraphRetrievalEvaluationHit],
        missingRequiredJudgmentIDs: [String]
    ) {
        self.evaluationCase = evaluationCase
        self.k = k
        self.metrics = metrics
        self.hits = hits
        self.missingRequiredJudgmentIDs = missingRequiredJudgmentIDs
    }
}

public struct GraphRetrievalEvaluationReport: Sendable, Codable, Equatable {
    public var generatedAt: Date
    public var k: Int
    public var caseResults: [GraphRetrievalEvaluationCaseResult]
    public var summary: GraphRetrievalEvaluationMetrics

    public init(generatedAt: Date = Date(), k: Int, caseResults: [GraphRetrievalEvaluationCaseResult]) {
        self.generatedAt = generatedAt
        self.k = k
        self.caseResults = caseResults
        self.summary = GraphRetrievalEvaluationReport.averageMetrics(caseResults.map(\.metrics))
    }

    private static func averageMetrics(_ metrics: [GraphRetrievalEvaluationMetrics]) -> GraphRetrievalEvaluationMetrics {
        guard !metrics.isEmpty else { return GraphRetrievalEvaluationMetrics() }
        let count = Double(metrics.count)
        return GraphRetrievalEvaluationMetrics(
            precisionAtK: metrics.reduce(0) { $0 + $1.precisionAtK } / count,
            recallAtK: metrics.reduce(0) { $0 + $1.recallAtK } / count,
            hitRateAtK: metrics.reduce(0) { $0 + $1.hitRateAtK } / count,
            meanReciprocalRank: metrics.reduce(0) { $0 + $1.meanReciprocalRank } / count,
            averagePrecision: metrics.reduce(0) { $0 + $1.averagePrecision } / count,
            normalizedDiscountedCumulativeGainAtK: metrics.reduce(0) { $0 + $1.normalizedDiscountedCumulativeGainAtK } / count,
            requiredHitRateAtK: metrics.reduce(0) { $0 + $1.requiredHitRateAtK } / count
        )
    }
}

public enum GraphRetrievalEvaluator {
    public static func evaluate(
        evaluationCase: GraphRetrievalEvaluationCase,
        response: GraphSearchResponse,
        k requestedK: Int? = nil
    ) -> GraphRetrievalEvaluationCaseResult {
        let k = max(1, requestedK ?? evaluationCase.limit)
        let topHits = Array(response.hits.prefix(k))
        let rankedHits = topHits.enumerated().map { GraphRetrievalEvaluationHit(rank: $0.offset + 1, hit: $0.element) }
        let relevanceByID = Dictionary(uniqueKeysWithValues: evaluationCase.judgments.map { ($0.id, $0.relevance) })
        let requiredIDs = Set(evaluationCase.judgments.filter(\.isRequired).map(\.id))
        let retrievedIDs = rankedHits.map(\.id)
        let retrievedIDSet = Set(retrievedIDs)
        let relevantIDs = Set(relevanceByID.filter { $0.value > 0 }.map(\.key))
        let relevantHitCount = retrievedIDs.filter { relevantIDs.contains($0) }.count
        let relevantCount = max(1, relevantIDs.count)

        let precisionAtK = Double(relevantHitCount) / Double(k)
        let recallAtK = Double(relevantHitCount) / Double(relevantCount)
        let hitRateAtK = relevantHitCount > 0 ? 1.0 : 0.0
        let firstRelevantRank = retrievedIDs.firstIndex { relevantIDs.contains($0) }.map { $0 + 1 }
        let reciprocalRank = firstRelevantRank.map { 1.0 / Double($0) } ?? 0.0
        let averagePrecision = averagePrecision(retrievedIDs: retrievedIDs, relevantIDs: relevantIDs, relevantCount: relevantCount)
        let ndcg = normalizedDiscountedCumulativeGain(retrievedIDs: retrievedIDs, relevanceByID: relevanceByID, k: k)
        let missingRequiredIDs = requiredIDs.subtracting(retrievedIDSet).sorted()
        let requiredHitRate = requiredIDs.isEmpty ? 1.0 : Double(requiredIDs.count - missingRequiredIDs.count) / Double(requiredIDs.count)

        return GraphRetrievalEvaluationCaseResult(
            evaluationCase: evaluationCase,
            k: k,
            metrics: GraphRetrievalEvaluationMetrics(
                precisionAtK: precisionAtK,
                recallAtK: recallAtK,
                hitRateAtK: hitRateAtK,
                meanReciprocalRank: reciprocalRank,
                averagePrecision: averagePrecision,
                normalizedDiscountedCumulativeGainAtK: ndcg,
                requiredHitRateAtK: requiredHitRate
            ),
            hits: rankedHits,
            missingRequiredJudgmentIDs: missingRequiredIDs
        )
    }

    private static func averagePrecision(retrievedIDs: [String], relevantIDs: Set<String>, relevantCount: Int) -> Double {
        var relevantSeen = 0
        var precisionSum = 0.0
        for (index, id) in retrievedIDs.enumerated() where relevantIDs.contains(id) {
            relevantSeen += 1
            precisionSum += Double(relevantSeen) / Double(index + 1)
        }
        return precisionSum / Double(relevantCount)
    }

    private static func normalizedDiscountedCumulativeGain(retrievedIDs: [String], relevanceByID: [String: Int], k: Int) -> Double {
        let gains = retrievedIDs.prefix(k).enumerated().map { index, id in
            discountedGain(relevance: relevanceByID[id] ?? 0, rank: index + 1)
        }
        let dcg = gains.reduce(0, +)
        let idealRelevances = relevanceByID.values.sorted(by: >).prefix(k)
        let idcg = idealRelevances.enumerated().map { index, relevance in
            discountedGain(relevance: relevance, rank: index + 1)
        }.reduce(0, +)
        guard idcg > 0 else { return 0 }
        return dcg / idcg
    }

    private static func discountedGain(relevance: Int, rank: Int) -> Double {
        guard relevance > 0 else { return 0 }
        return (pow(2.0, Double(relevance)) - 1.0) / log2(Double(rank + 1))
    }
}

public struct GraphRetrievalEvaluationHarness: Sendable {
    public var searchService: any GraphHybridSearchService
    public var now: @Sendable () -> Date

    public init(searchService: any GraphHybridSearchService, now: @escaping @Sendable () -> Date = Date.init) {
        self.searchService = searchService
        self.now = now
    }

    public func run(cases: [GraphRetrievalEvaluationCase], k: Int? = nil) async throws -> GraphRetrievalEvaluationReport {
        var results: [GraphRetrievalEvaluationCaseResult] = []
        for evaluationCase in cases {
            let response = try await searchService.search(query: evaluationCase.searchQuery(referenceTime: now()))
            results.append(GraphRetrievalEvaluator.evaluate(evaluationCase: evaluationCase, response: response, k: k))
        }
        return GraphRetrievalEvaluationReport(generatedAt: now(), k: max(1, k ?? cases.first?.limit ?? 1), caseResults: results)
    }
}
