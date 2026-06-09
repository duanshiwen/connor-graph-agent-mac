import Foundation
import ConnorGraphCore
import ConnorGraphSearch

public struct SQLiteGraphHybridSearchService: GraphHybridSearchService, Sendable {
    public var store: SQLiteGraphStore
    public var embeddingProvider: (any EmbeddingProvider)?
    public var crossEncoderReranker: (any GraphCrossEncoderReranker)?

    public init(
        store: SQLiteGraphStore,
        embeddingProvider: (any EmbeddingProvider)? = nil,
        crossEncoderReranker: (any GraphCrossEncoderReranker)? = nil
    ) {
        self.store = store
        self.embeddingProvider = embeddingProvider
        self.crossEncoderReranker = crossEncoderReranker
    }

    public func search(query: GraphSearchQuery) async throws -> GraphSearchResponse {
        let perScopeLimit = max(query.limit, 1)
        var fusion = RRFFusion(k: 60.0)

        if query.includeFacts {
            let facts = try store.searchFactFTS(query: query.text, groupID: query.groupID, limit: perScopeLimit)
            for (index, fact) in facts.enumerated() where includes(fact.status, in: query.statusFilter) && isTemporallyValid(fact, at: query.referenceTime) {
                fusion.add(try factHit(fact, rank: index), method: "fts", rank: index + 1)
            }
        }

        if query.includeNodes {
            let nodes = try store.searchNodeFTS(query: query.text, groupID: query.groupID, limit: perScopeLimit)
            for (index, node) in nodes.enumerated() where includes(node.status, in: query.statusFilter) && isTemporallyValid(node, at: query.referenceTime) {
                fusion.add(try nodeHit(node, rank: index), method: "fts", rank: index + 1)
            }
        }

        if query.includeEpisodes {
            let episodes = try store.searchEpisodeFTS(query: query.text, groupID: query.groupID, limit: perScopeLimit)
            for (index, episode) in episodes.enumerated() where includes(episode.status, in: query.statusFilter) {
                fusion.add(episodeHit(episode, rank: index), method: "fts", rank: index + 1)
            }
        }

        if let semanticQuery = try await semanticQuery(for: query) {
            let ownerTypes = includedOwnerTypes(query)
            let semanticResults = try store.searchEmbeddings(
                queryVector: semanticQuery.vector,
                groupID: query.groupID,
                embeddingModel: semanticQuery.model,
                ownerTypes: ownerTypes,
                limit: perScopeLimit
            )
            for (index, result) in semanticResults.enumerated() where result.score > 0 {
                switch result.embedding.ownerType {
                case .fact:
                    guard query.includeFacts, let fact = try store.graphFact(id: result.embedding.ownerID), includes(fact.status, in: query.statusFilter), isTemporallyValid(fact, at: query.referenceTime) else { continue }
                    fusion.add(try factHit(fact, rank: index, retrievalMethod: "semantic", explicitScore: result.score), method: "semantic", rank: index + 1)
                case .node:
                    guard query.includeNodes, let node = try store.graphNodeV2(id: result.embedding.ownerID), includes(node.status, in: query.statusFilter), isTemporallyValid(node, at: query.referenceTime) else { continue }
                    fusion.add(try nodeHit(node, rank: index, retrievalMethod: "semantic", explicitScore: result.score), method: "semantic", rank: index + 1)
                case .episode:
                    guard query.includeEpisodes, let episode = try store.graphEpisode(id: result.embedding.ownerID), includes(episode.status, in: query.statusFilter) else { continue }
                    fusion.add(episodeHit(episode, rank: index, retrievalMethod: "semantic", explicitScore: result.score), method: "semantic", rank: index + 1)
                }
            }
        }

        let rankedHits = try await graphRerankedHits(fusion.rankedHits(), query: query)
        return GraphSearchResponse(hits: Array(rankedHits.prefix(query.limit)))
    }

    private func graphRerankedHits(_ hits: [GraphSearchHit], query: GraphSearchQuery) async throws -> [GraphSearchHit] {
        var rankedHits = hits
        if query.reranking.strategies.contains(.graphitiLocal) {
            rankedHits = GraphitiLocalReranker().rerank(rankedHits, query: query)
        } else {
            rankedHits = rankedHits.map { hit in
                var updated = hit
                updated.metadata["graph_ranking"] = "rrf_only"
                updated.metadata["base_rrf_score"] = formattedScore(hit.score)
                updated.metadata["graph_boost"] = "0.000000"
                updated.metadata["final_score"] = formattedScore(hit.score)
                return updated
            }
        }
        rankedHits = rankedHits.map { hit in
            var updated = hit
            updated.metadata["graph_reranking_strategies"] = strategyList(query.reranking.strategies)
            return updated
        }
        if query.reranking.strategies.contains(.crossEncoder) {
            rankedHits = try await crossEncoderRerankedHits(rankedHits, query: query)
        }
        return rankedHits
    }

    private func crossEncoderRerankedHits(_ hits: [GraphSearchHit], query: GraphSearchQuery) async throws -> [GraphSearchHit] {
        guard let crossEncoderReranker else {
            return hits.map { hit in
                var updated = hit
                updated.metadata["cross_encoder_status"] = "unavailable"
                return updated
            }
        }
        let topK = max(0, min(query.reranking.crossEncoderTopK ?? query.limit, hits.count))
        guard topK > 0 else { return hits }
        let scoringHits = Array(hits.prefix(topK))
        let candidates = scoringHits.map { hit in
            GraphCrossEncoderCandidate(ownerType: hit.ownerType, ownerID: hit.ownerID, title: hit.title, text: hit.text, metadata: hit.metadata)
        }
        let scores = try await crossEncoderReranker.scores(query: query.text, candidates: candidates)
        let scoresByID = Dictionary(uniqueKeysWithValues: scores.map { ("\($0.ownerType.rawValue):\($0.ownerID)", $0.score) })
        let rerankedTop = scoringHits.map { hit in
            var updated = hit
            let score = scoresByID[hit.id] ?? 0
            updated.score = score
            updated.metadata["cross_encoder_score"] = formattedScore(score)
            updated.metadata["cross_encoder_reranked"] = "true"
            updated.metadata["final_score"] = formattedScore(score)
            return updated
        }.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.ownerType.rawValue == rhs.ownerType.rawValue { return lhs.ownerID < rhs.ownerID }
                return lhs.ownerType.rawValue < rhs.ownerType.rawValue
            }
            return lhs.score > rhs.score
        }
        return rerankedTop + Array(hits.dropFirst(topK))
    }

    private func strategyList(_ strategies: [GraphRerankerStrategy]) -> String {
        strategies.map(\.rawValue).joined(separator: ",")
    }

    private struct GraphRankingSignal: Sendable, Equatable {
        var reason: String
        var boost: Double
    }

    private struct GraphitiLocalReranker: Sendable {
        func rerank(_ hits: [GraphSearchHit], query: GraphSearchQuery) -> [GraphSearchHit] {
            hits.map { hit in
                var rerankedHit = hit
                let baseScore = hit.score
                let signals = signals(for: hit, query: query)
                let boost = signals.reduce(0.0) { $0 + $1.boost }
                let signalReasons = signals.map(\.reason)
                rerankedHit.score = baseScore + boost
                rerankedHit.metadata["graph_reranker"] = "graphiti_local"
                rerankedHit.metadata["base_rrf_score"] = formattedScore(baseScore)
                rerankedHit.metadata["graph_boost"] = formattedScore(boost)
                rerankedHit.metadata["final_score"] = formattedScore(rerankedHit.score)
                if boost > 0 {
                    rerankedHit.metadata["graph_ranking"] = "boosted"
                    rerankedHit.metadata["graph_boost_reason"] = signalReasons.joined(separator: ",")
                    rerankedHit.metadata["graph_ranking_signals"] = signalReasons.joined(separator: ",")
                    rerankedHit.metadata["graph_ranking_signal_scores"] = formattedSignalScores(signals)
                } else {
                    rerankedHit.metadata["graph_ranking"] = "rrf_only"
                    rerankedHit.metadata.removeValue(forKey: "graph_boost_reason")
                    rerankedHit.metadata.removeValue(forKey: "graph_ranking_signals")
                    rerankedHit.metadata.removeValue(forKey: "graph_ranking_signal_scores")
                }
                return rerankedHit
            }.sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    if lhs.ownerType.rawValue == rhs.ownerType.rawValue { return lhs.ownerID < rhs.ownerID }
                    return lhs.ownerType.rawValue < rhs.ownerType.rawValue
                }
                return lhs.score > rhs.score
            }
        }

        private func signals(for hit: GraphSearchHit, query: GraphSearchQuery) -> [GraphRankingSignal] {
            var signals: [GraphRankingSignal] = []

            if hit.ownerType == .node, query.centerNodeIDs.contains(hit.ownerID) {
                signals.append(GraphRankingSignal(reason: "center_node_exact_match", boost: 0.004))
            } else if isOneHopFromCenter(hit, centerNodeIDs: query.centerNodeIDs) {
                signals.append(GraphRankingSignal(reason: "center_node_1_hop_match", boost: 0.003))
            }

            if hit.metadata["graph_context"] == "fact_endpoints" {
                let endpointTitles = [hit.metadata["source_node_title"], hit.metadata["target_node_title"]].compactMap { $0 }
                if endpointTitles.contains(where: { query.text.localizedCaseInsensitiveContains($0) }) {
                    signals.append(GraphRankingSignal(reason: "endpoint_title_query_match", boost: 0.002))
                }
            }

            if hit.metadata["graph_context"] == "adjacent_facts",
               adjacentRelations(in: hit).contains(where: { queryContainsRelation($0, queryText: query.text) }) {
                signals.append(GraphRankingSignal(reason: "adjacent_relation_query_match", boost: 0.001))
            }

            return signals
        }

        private func isOneHopFromCenter(_ hit: GraphSearchHit, centerNodeIDs: [String]) -> Bool {
            guard !centerNodeIDs.isEmpty else { return false }
            switch hit.ownerType {
            case .fact:
                return [hit.metadata["source_node_id"], hit.metadata["target_node_id"]]
                    .compactMap { $0 }
                    .contains { centerNodeIDs.contains($0) }
            case .node:
                return nodeIDs(from: hit.metadata["adjacent_node_ids"]).contains { centerNodeIDs.contains($0) }
            case .episode:
                return false
            }
        }

        private func adjacentRelations(in hit: GraphSearchHit) -> [String] {
            nodeIDs(from: hit.metadata["adjacent_fact_relations"])
        }

        private func nodeIDs(from value: String?) -> [String] {
            value?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
        }

        private func queryContainsRelation(_ relation: String, queryText: String) -> Bool {
            queryText.localizedCaseInsensitiveContains(relation)
        }

        private func formattedSignalScores(_ signals: [GraphRankingSignal]) -> String {
            signals.map { "\($0.reason):\(formattedScore($0.boost))" }.joined(separator: ",")
        }

        private func formattedScore(_ score: Double) -> String {
            String(format: "%.6f", score)
        }
    }

    private func formattedScore(_ score: Double) -> String {
        String(format: "%.6f", score)
    }

    private struct RRFFusion {
        struct Accumulator {
            var hit: GraphSearchHit
            var methods: Set<String>
            var ranks: [String: Int]
            var score: Double
        }

        var k: Double
        var hitsByID: [String: Accumulator] = [:]

        mutating func add(_ hit: GraphSearchHit, method: String, rank: Int) {
            let contribution = 1.0 / (k + Double(rank))
            if var existing = hitsByID[hit.id] {
                existing.methods.insert(method)
                existing.ranks[method] = min(existing.ranks[method] ?? rank, rank)
                existing.score += contribution
                existing.hit.sourceEpisodeIDs = Array(Set(existing.hit.sourceEpisodeIDs + hit.sourceEpisodeIDs)).sorted()
                existing.hit.metadata.merge(hit.metadata) { current, _ in current }
                hitsByID[hit.id] = existing
            } else {
                hitsByID[hit.id] = Accumulator(hit: hit, methods: [method], ranks: [method: rank], score: contribution)
            }
        }

        func rankedHits() -> [GraphSearchHit] {
            hitsByID.values.map { accumulator in
                var hit = accumulator.hit
                let orderedMethods = ["fts", "semantic"].filter { accumulator.methods.contains($0) }
                hit.retrievalMethod = orderedMethods.count > 1 ? "hybrid" : (orderedMethods.first ?? hit.retrievalMethod)
                hit.score = accumulator.score
                hit.metadata["fusion"] = "rrf"
                hit.metadata["retrieval_methods"] = orderedMethods.joined(separator: ",")
                if let ftsRank = accumulator.ranks["fts"] { hit.metadata["rrf_fts_rank"] = String(ftsRank) }
                if let semanticRank = accumulator.ranks["semantic"] { hit.metadata["rrf_semantic_rank"] = String(semanticRank) }
                return hit
            }.sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    if lhs.ownerType.rawValue == rhs.ownerType.rawValue { return lhs.ownerID < rhs.ownerID }
                    return lhs.ownerType.rawValue < rhs.ownerType.rawValue
                }
                return lhs.score > rhs.score
            }
        }
    }

    private struct SemanticQuery: Sendable {
        var model: String
        var vector: [Double]
    }

    private func semanticQuery(for query: GraphSearchQuery) async throws -> SemanticQuery? {
        if let embeddingModel = query.embeddingModel, let queryEmbedding = query.queryEmbedding {
            return SemanticQuery(model: embeddingModel, vector: queryEmbedding)
        }
        guard let embeddingProvider else { return nil }
        if let requestedModel = query.embeddingModel, requestedModel != embeddingProvider.model {
            return nil
        }
        let vector = try await embeddingProvider.embedding(for: query.text)
        guard vector.count == embeddingProvider.dimensions else {
            throw SQLiteGraphStoreError.decodeFailed("query embedding dimensions mismatch for \(embeddingProvider.model)")
        }
        return SemanticQuery(model: embeddingProvider.model, vector: vector)
    }

    private func includedOwnerTypes(_ query: GraphSearchQuery) -> Set<GraphIndexOwnerType> {
        var ownerTypes: Set<GraphIndexOwnerType> = []
        if query.includeFacts { ownerTypes.insert(.fact) }
        if query.includeNodes { ownerTypes.insert(.node) }
        if query.includeEpisodes { ownerTypes.insert(.episode) }
        return ownerTypes
    }

    private func includes(_ status: GraphTemporalStatus, in filter: Set<GraphTemporalStatus>) -> Bool {
        filter.isEmpty || filter.contains(status)
    }

    private func isTemporallyValid(_ fact: GraphFact, at referenceTime: Date?) -> Bool {
        guard let referenceTime else { return true }
        if let validAt = fact.validAt, validAt > referenceTime { return false }
        if let invalidAt = fact.invalidAt, invalidAt <= referenceTime { return false }
        if let expiredAt = fact.expiredAt, expiredAt <= referenceTime { return false }
        return true
    }

    private func isTemporallyValid(_ node: GraphNodeV2, at referenceTime: Date?) -> Bool {
        guard let referenceTime else { return true }
        if let validFrom = node.validFrom, validFrom > referenceTime { return false }
        if let validUntil = node.validUntil, validUntil <= referenceTime { return false }
        return true
    }

    private func factHit(_ fact: GraphFact, rank: Int, retrievalMethod: String = "fts", explicitScore: Double? = nil) throws -> GraphSearchHit {
        var metadata = [
            "group_id": fact.groupID,
            "relation": fact.relation.rawValue,
            "status": fact.status.rawValue,
            "source_node_id": fact.sourceNodeID,
            "target_node_id": fact.targetNodeID
        ]
        if let sourceNode = try store.graphNodeV2(id: fact.sourceNodeID), let targetNode = try store.graphNodeV2(id: fact.targetNodeID) {
            metadata["graph_context"] = "fact_endpoints"
            metadata["source_node_title"] = sourceNode.title
            metadata["source_node_type"] = sourceNode.type.rawValue
            metadata["target_node_title"] = targetNode.title
            metadata["target_node_type"] = targetNode.type.rawValue
            metadata["graph_context_node_ids"] = [sourceNode.id, targetNode.id].joined(separator: ",")
        }
        return GraphSearchHit(
            ownerType: .fact,
            ownerID: fact.id,
            title: fact.relation.rawValue,
            text: fact.fact,
            score: explicitScore ?? score(forRank: rank),
            retrievalMethod: retrievalMethod,
            sourceEpisodeIDs: try store.sourceEpisodeIDs(factID: fact.id),
            metadata: metadata
        )
    }

    private func nodeHit(_ node: GraphNodeV2, rank: Int, retrievalMethod: String = "fts", explicitScore: Double? = nil) throws -> GraphSearchHit {
        var metadata = [
            "group_id": node.groupID,
            "type": node.type.rawValue,
            "status": node.status.rawValue,
            "canonical_name": node.canonicalName
        ]
        let adjacentFacts = try store.adjacentFacts(nodeID: node.id, groupID: node.groupID)
        if !adjacentFacts.isEmpty {
            metadata["graph_context"] = "adjacent_facts"
            metadata["adjacent_fact_ids"] = adjacentFacts.map(\.id).joined(separator: ",")
            metadata["adjacent_fact_relations"] = adjacentFacts.map { $0.relation.rawValue }.joined(separator: ",")
            let adjacentNodeIDs = adjacentFacts.map { fact in
                fact.sourceNodeID == node.id ? fact.targetNodeID : fact.sourceNodeID
            }
            metadata["adjacent_node_ids"] = Array(Set(adjacentNodeIDs)).sorted().joined(separator: ",")
        }
        return GraphSearchHit(
            ownerType: .node,
            ownerID: node.id,
            title: node.title,
            text: node.summary.isEmpty ? node.canonicalName : node.summary,
            score: explicitScore ?? score(forRank: rank),
            retrievalMethod: retrievalMethod,
            metadata: metadata
        )
    }

    private func episodeHit(_ episode: GraphEpisode, rank: Int, retrievalMethod: String = "fts", explicitScore: Double? = nil) -> GraphSearchHit {
        GraphSearchHit(
            ownerType: .episode,
            ownerID: episode.id,
            title: episode.name,
            text: episode.content,
            score: explicitScore ?? score(forRank: rank),
            retrievalMethod: retrievalMethod,
            sourceEpisodeIDs: [episode.id],
            metadata: [
                "group_id": episode.groupID,
                "source_type": episode.sourceType.rawValue,
                "status": episode.status.rawValue
            ]
        )
    }

    private func score(forRank rank: Int) -> Double {
        1.0 / Double(rank + 1)
    }
}
