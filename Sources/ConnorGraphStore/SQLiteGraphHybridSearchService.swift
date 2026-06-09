import Foundation
import ConnorGraphCore
import ConnorGraphSearch

public struct SQLiteGraphHybridSearchService: GraphHybridSearchService, Sendable {
    public var store: SQLiteGraphStore

    public init(store: SQLiteGraphStore) {
        self.store = store
    }

    public func search(query: GraphSearchQuery) async throws -> GraphSearchResponse {
        let perScopeLimit = max(query.limit, 1)
        var hits: [GraphSearchHit] = []

        if query.includeFacts {
            let facts = try store.searchFactFTS(query: query.text, groupID: query.groupID, limit: perScopeLimit)
            for (index, fact) in facts.enumerated() where includes(fact.status, in: query.statusFilter) && isTemporallyValid(fact, at: query.referenceTime) {
                hits.append(try factHit(fact, rank: index))
            }
        }

        if query.includeNodes {
            let nodes = try store.searchNodeFTS(query: query.text, groupID: query.groupID, limit: perScopeLimit)
            for (index, node) in nodes.enumerated() where includes(node.status, in: query.statusFilter) && isTemporallyValid(node, at: query.referenceTime) {
                hits.append(nodeHit(node, rank: index))
            }
        }

        if query.includeEpisodes {
            let episodes = try store.searchEpisodeFTS(query: query.text, groupID: query.groupID, limit: perScopeLimit)
            for (index, episode) in episodes.enumerated() where includes(episode.status, in: query.statusFilter) {
                hits.append(episodeHit(episode, rank: index))
            }
        }

        let ranked = hits.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.ownerType.rawValue == rhs.ownerType.rawValue { return lhs.ownerID < rhs.ownerID }
                return lhs.ownerType.rawValue < rhs.ownerType.rawValue
            }
            return lhs.score > rhs.score
        }
        return GraphSearchResponse(hits: Array(ranked.prefix(query.limit)))
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

    private func factHit(_ fact: GraphFact, rank: Int) throws -> GraphSearchHit {
        GraphSearchHit(
            ownerType: .fact,
            ownerID: fact.id,
            title: fact.relation.rawValue,
            text: fact.fact,
            score: score(forRank: rank),
            retrievalMethod: "fts",
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

    private func nodeHit(_ node: GraphNodeV2, rank: Int) -> GraphSearchHit {
        GraphSearchHit(
            ownerType: .node,
            ownerID: node.id,
            title: node.title,
            text: node.summary.isEmpty ? node.canonicalName : node.summary,
            score: score(forRank: rank),
            retrievalMethod: "fts",
            metadata: [
                "group_id": node.groupID,
                "type": node.type.rawValue,
                "status": node.status.rawValue,
                "canonical_name": node.canonicalName
            ]
        )
    }

    private func episodeHit(_ episode: GraphEpisode, rank: Int) -> GraphSearchHit {
        GraphSearchHit(
            ownerType: .episode,
            ownerID: episode.id,
            title: episode.name,
            text: episode.content,
            score: score(forRank: rank),
            retrievalMethod: "fts",
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
