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
        // The reranking pipeline intentionally uses a canonical execution order for deterministic
        // local-first behavior: topology boosts, episode mention boosts, MMR diversity, then
        // optional cross-encoder precision reranking.
        var rankedHits = hits
        if query.reranking.strategies.contains(.graphitiLocal) {
            rankedHits = try GraphitiLocalReranker(traversalStore: SQLiteGraphTraversalStore(store: store)).rerank(rankedHits, query: query)
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
            updated.metadata["graph_reranking_strategies"] = strategyList(canonicalRerankingStrategies(from: query.reranking.strategies))
            return updated
        }
        if query.reranking.strategies.contains(.episodeMentions) {
            rankedHits = try episodeMentionsRerankedHits(rankedHits, query: query)
        }
        if query.reranking.strategies.contains(.maximalMarginalRelevance) {
            rankedHits = try mmrRerankedHits(rankedHits, query: query)
        }
        if query.reranking.strategies.contains(.crossEncoder) {
            rankedHits = try await crossEncoderRerankedHits(rankedHits, query: query)
        }
        return rankedHits
    }

    private func episodeMentionsRerankedHits(_ hits: [GraphSearchHit], query: GraphSearchQuery) throws -> [GraphSearchHit] {
        guard !hits.isEmpty else { return hits }
        let mentionCounts = try store.mentionCounts(groupID: query.groupID, episodeIDs: query.reranking.episodeMentionEpisodeIDs)
        let scope = query.reranking.episodeMentionEpisodeIDs.isEmpty ? "group" : "selected_episodes"
        return hits.map { hit in
            var updated = hit
            let count = episodeMentionCount(for: hit, mentionCounts: mentionCounts)
            let boost = min(Double(count) * 0.0025, 0.0100)
            updated.metadata["episode_mentions_count"] = String(count)
            updated.metadata["episode_mentions_scope"] = scope
            updated.metadata["episode_mentions_boost"] = formattedScore(boost)
            guard boost > 0 else { return updated }
            updated.score += boost
            updated.metadata["graph_ranking"] = "boosted"
            appendMetadataToken("episode_mentions", key: "graph_boost_reason", hit: &updated)
            appendMetadataToken("episode_mentions", key: "graph_ranking_signals", hit: &updated)
            appendSignalScore("episode_mentions", score: boost, hit: &updated)
            let existingBoost = Double(updated.metadata["graph_boost"] ?? "0") ?? 0
            updated.metadata["graph_boost"] = formattedScore(existingBoost + boost)
            updated.metadata["final_score"] = formattedScore(updated.score)
            return updated
        }.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.ownerType.rawValue == rhs.ownerType.rawValue { return lhs.ownerID < rhs.ownerID }
                return lhs.ownerType.rawValue < rhs.ownerType.rawValue
            }
            return lhs.score > rhs.score
        }
    }

    private func episodeMentionCount(for hit: GraphSearchHit, mentionCounts: [String: Int]) -> Int {
        switch hit.ownerType {
        case .node:
            return mentionCounts[hit.ownerID] ?? 0
        case .fact:
            let source = hit.metadata["source_node_id"].flatMap { mentionCounts[$0] } ?? 0
            let target = hit.metadata["target_node_id"].flatMap { mentionCounts[$0] } ?? 0
            return source + target
        case .episode:
            return hit.sourceEpisodeIDs.reduce(0) { $0 + (mentionCounts[$1] ?? 0) }
        }
    }

    private func appendMetadataToken(_ token: String, key: String, hit: inout GraphSearchHit) {
        var tokens = hit.metadata[key]?.split(separator: ",").map(String.init) ?? []
        if !tokens.contains(token) { tokens.append(token) }
        hit.metadata[key] = tokens.joined(separator: ",")
    }

    private func appendSignalScore(_ reason: String, score: Double, hit: inout GraphSearchHit) {
        let token = "\(reason):\(formattedScore(score))"
        var tokens = hit.metadata["graph_ranking_signal_scores"]?.split(separator: ",").map(String.init) ?? []
        tokens.removeAll { $0.hasPrefix("\(reason):") }
        tokens.append(token)
        hit.metadata["graph_ranking_signal_scores"] = tokens.joined(separator: ",")
    }

    private func mmrRerankedHits(_ hits: [GraphSearchHit], query: GraphSearchQuery) throws -> [GraphSearchHit] {
        guard !hits.isEmpty else { return hits }
        guard let embeddingModel = query.embeddingModel, let queryEmbedding = query.queryEmbedding, GraphEmbedding.norm(queryEmbedding) > 0 else {
            return hits.map { hit in
                var updated = hit
                updated.metadata["mmr_status"] = "unavailable"
                updated.metadata["mmr_embedding_status"] = "missing"
                return updated
            }
        }
        var embeddingsByID: [String: GraphEmbedding] = [:]
        for hit in hits {
            if let embedding = try store.graphEmbedding(ownerType: hit.ownerType, ownerID: hit.ownerID, embeddingModel: embeddingModel) {
                embeddingsByID[hit.id] = embedding
            }
        }
        guard !embeddingsByID.isEmpty else {
            return hits.map { hit in
                var updated = hit
                updated.metadata["mmr_status"] = "unavailable"
                updated.metadata["mmr_embedding_status"] = "missing"
                return updated
            }
        }

        let lambda = min(1.0, max(0.0, query.reranking.mmrLambda))
        let queryNorm = GraphEmbedding.norm(queryEmbedding)
        var remaining = hits
        var selected: [GraphSearchHit] = []

        while !remaining.isEmpty {
            let best = remaining.enumerated().map { index, hit -> (index: Int, hit: GraphSearchHit, score: Double) in
                let relevance = embeddingsByID[hit.id].map { cosine(queryEmbedding, queryNorm: queryNorm, embedding: $0) } ?? normalizedScore(hit.score, among: hits)
                let diversityPenalty = selected.compactMap { selectedHit -> Double? in
                    guard let candidateEmbedding = embeddingsByID[hit.id], let selectedEmbedding = embeddingsByID[selectedHit.id] else { return nil }
                    return cosine(candidateEmbedding.vector, queryNorm: candidateEmbedding.vectorNorm, embedding: selectedEmbedding)
                }.max() ?? 0
                return (index, hit, (lambda * relevance) - ((1 - lambda) * diversityPenalty))
            }.sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.hit.ownerID < rhs.hit.ownerID }
                return lhs.score > rhs.score
            }.first!
            var updated = best.hit
            let rank = selected.count + 1
            updated.metadata["mmr_score"] = formattedScore(best.score)
            updated.metadata["mmr_lambda"] = formattedScore(lambda)
            updated.metadata["mmr_rank"] = String(rank)
            updated.metadata["mmr_status"] = "reranked"
            if embeddingsByID[updated.id] == nil {
                updated.metadata["mmr_embedding_status"] = "missing"
            } else {
                updated.metadata["mmr_embedding_status"] = "available"
            }
            selected.append(updated)
            remaining.remove(at: best.index)
        }
        return selected
    }

    private func normalizedScore(_ score: Double, among hits: [GraphSearchHit]) -> Double {
        let maxScore = hits.map(\.score).max() ?? 0
        guard maxScore > 0 else { return 0 }
        return score / maxScore
    }

    private func cosine(_ vector: [Double], queryNorm: Double, embedding: GraphEmbedding) -> Double {
        guard queryNorm > 0, embedding.vectorNorm > 0, vector.count == embedding.vector.count else { return 0 }
        let dotProduct = zip(vector, embedding.vector).reduce(0.0) { $0 + $1.0 * $1.1 }
        return dotProduct / (queryNorm * embedding.vectorNorm)
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

    private func canonicalRerankingStrategies(from requestedStrategies: [GraphRerankerStrategy]) -> [GraphRerankerStrategy] {
        let requested = Set(requestedStrategies)
        return GraphRerankerStrategy.canonicalExecutionOrder.filter { requested.contains($0) }
    }

    private struct GraphRankingSignal: Sendable, Equatable {
        var reason: String
        var boost: Double
    }

    private struct GraphitiLocalReranker: Sendable {
        var traversalStore: SQLiteGraphTraversalStore

        func rerank(_ hits: [GraphSearchHit], query: GraphSearchQuery) throws -> [GraphSearchHit] {
            try hits.map { hit in
                var rerankedHit = hit
                let baseScore = hit.score
                let signals = try signals(for: hit, query: query)
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

        private func signals(for hit: GraphSearchHit, query: GraphSearchQuery) throws -> [GraphRankingSignal] {
            var signals: [GraphRankingSignal] = []

            if hit.ownerType == .node, query.centerNodeIDs.contains(hit.ownerID) {
                signals.append(GraphRankingSignal(reason: "center_node_exact_match", boost: 0.004))
            }
            let distances = try centerDistances(for: hit, query: query)
            if distances.contains(1) {
                signals.append(GraphRankingSignal(reason: "center_node_1_hop_match", boost: 0.003))
            }
            if distances.contains(2) {
                signals.append(GraphRankingSignal(reason: "center_node_2_hop_match", boost: 0.0015))
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

        private func centerDistances(for hit: GraphSearchHit, query: GraphSearchQuery) throws -> Set<Int> {
            guard !query.centerNodeIDs.isEmpty else { return [] }
            let candidateNodeIDs: [String]
            switch hit.ownerType {
            case .fact:
                candidateNodeIDs = [hit.metadata["source_node_id"], hit.metadata["target_node_id"]].compactMap { $0 }
                if candidateNodeIDs.contains(where: { query.centerNodeIDs.contains($0) }) {
                    return [1]
                }
            case .node:
                candidateNodeIDs = [hit.ownerID] + nodeIDs(from: hit.metadata["adjacent_node_ids"])
            case .episode:
                candidateNodeIDs = []
            }
            guard !candidateNodeIDs.isEmpty else { return [] }
            let distances = try traversalStore.shortestHopDistances(
                from: query.centerNodeIDs,
                to: candidateNodeIDs,
                groupID: query.groupID,
                maxDepth: 2
            )
            let positiveDistances = Set(distances.values.filter { $0 > 0 })
            if hit.ownerType == .fact {
                return Set(positiveDistances.filter { $0 == 2 })
            }
            return positiveDistances
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
