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
        var hitsByID: [String: GraphSearchHit] = [:]

        func merge(_ hit: GraphSearchHit) {
            if var existing = hitsByID[hit.id] {
                existing.score = max(existing.score, hit.score)
                existing.retrievalMethod = existing.retrievalMethod == hit.retrievalMethod ? existing.retrievalMethod : "hybrid"
                existing.sourceEpisodeIDs = Array(Set(existing.sourceEpisodeIDs + hit.sourceEpisodeIDs)).sorted()
                hitsByID[hit.id] = existing
            } else {
                hitsByID[hit.id] = hit
            }
        }

        if query.includeFacts {
            let facts = try store.searchFactFTS(query: query.text, groupID: query.groupID, limit: perScopeLimit)
            for (index, fact) in facts.enumerated() where includes(fact.status, in: query.statusFilter) && isTemporallyValid(fact, at: query.referenceTime) {
                merge(try factHit(fact, rank: index, retrievalMethod: "fts", explicitScore: score(forRank: index)))
            }
        }

        if query.includeNodes {
            let nodes = try store.searchNodeFTS(query: query.text, groupID: query.groupID, limit: perScopeLimit)
            for (index, node) in nodes.enumerated() where includes(node.status, in: query.statusFilter) && isTemporallyValid(node, at: query.referenceTime) {
                merge(nodeHit(node, rank: index, retrievalMethod: "fts", explicitScore: score(forRank: index)))
            }
        }

        if query.includeEpisodes {
            let episodes = try store.searchEpisodeFTS(query: query.text, groupID: query.groupID, limit: perScopeLimit)
            for (index, episode) in episodes.enumerated() where includes(episode.status, in: query.statusFilter) {
                merge(episodeHit(episode, rank: index, retrievalMethod: "fts", explicitScore: score(forRank: index)))
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
            for result in semanticResults where result.score > 0 {
                switch result.embedding.ownerType {
                case .fact:
                    guard query.includeFacts, let fact = try store.graphFact(id: result.embedding.ownerID), includes(fact.status, in: query.statusFilter), isTemporallyValid(fact, at: query.referenceTime) else { continue }
                    merge(try factHit(fact, rank: 0, retrievalMethod: "semantic", explicitScore: result.score))
                case .node:
                    guard query.includeNodes, let node = try store.graphNodeV2(id: result.embedding.ownerID), includes(node.status, in: query.statusFilter), isTemporallyValid(node, at: query.referenceTime) else { continue }
                    merge(nodeHit(node, rank: 0, retrievalMethod: "semantic", explicitScore: result.score))
                case .episode:
                    guard query.includeEpisodes, let episode = try store.graphEpisode(id: result.embedding.ownerID), includes(episode.status, in: query.statusFilter) else { continue }
                    merge(episodeHit(episode, rank: 0, retrievalMethod: "semantic", explicitScore: result.score))
                }
            }
        }

        let ranked = hitsByID.values.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.ownerType.rawValue == rhs.ownerType.rawValue { return lhs.ownerID < rhs.ownerID }
                return lhs.ownerType.rawValue < rhs.ownerType.rawValue
            }
            return lhs.score > rhs.score
        }
        return GraphSearchResponse(hits: Array(ranked.prefix(query.limit)))
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
