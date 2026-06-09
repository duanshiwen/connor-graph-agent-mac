import Foundation
import ConnorGraphCore
import ConnorGraphSearch

public struct SQLiteGraphHybridSearchService: GraphHybridSearchService, Sendable {
    public var store: SQLiteGraphStore
    public var embeddingProvider: (any EmbeddingProvider)?

    public init(store: SQLiteGraphStore, embeddingProvider: (any EmbeddingProvider)? = nil) {
        self.store = store
        self.embeddingProvider = embeddingProvider
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
                fusion.add(nodeHit(node, rank: index), method: "fts", rank: index + 1)
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
                    fusion.add(nodeHit(node, rank: index, retrievalMethod: "semantic", explicitScore: result.score), method: "semantic", rank: index + 1)
                case .episode:
                    guard query.includeEpisodes, let episode = try store.graphEpisode(id: result.embedding.ownerID), includes(episode.status, in: query.statusFilter) else { continue }
                    fusion.add(episodeHit(episode, rank: index, retrievalMethod: "semantic", explicitScore: result.score), method: "semantic", rank: index + 1)
                }
            }
        }

        return GraphSearchResponse(hits: Array(fusion.rankedHits().prefix(query.limit)))
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
        GraphSearchHit(
            ownerType: .fact,
            ownerID: fact.id,
            title: fact.relation.rawValue,
            text: fact.fact,
            score: explicitScore ?? score(forRank: rank),
            retrievalMethod: retrievalMethod,
            sourceEpisodeIDs: try store.sourceEpisodeIDs(factID: fact.id),
            metadata: [
                "group_id": fact.groupID,
                "relation": fact.relation.rawValue,
                "status": fact.status.rawValue,
                "source_node_id": fact.sourceNodeID,
                "target_node_id": fact.targetNodeID
            ]
        )
    }

    private func nodeHit(_ node: GraphNodeV2, rank: Int, retrievalMethod: String = "fts", explicitScore: Double? = nil) -> GraphSearchHit {
        GraphSearchHit(
            ownerType: .node,
            ownerID: node.id,
            title: node.title,
            text: node.summary.isEmpty ? node.canonicalName : node.summary,
            score: explicitScore ?? score(forRank: rank),
            retrievalMethod: retrievalMethod,
            metadata: [
                "group_id": node.groupID,
                "type": node.type.rawValue,
                "status": node.status.rawValue,
                "canonical_name": node.canonicalName
            ]
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
