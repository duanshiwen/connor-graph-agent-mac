import Foundation
import ConnorGraphCore
import ConnorGraphSearch

public protocol EmbeddingProvider: Sendable {
    var model: String { get }
    var dimensions: Int { get }
    func embedding(for text: String) async throws -> [Double]
}

public struct SQLiteGraphHybridSearchService: GraphHybridSearchService, Sendable {
    public var store: SQLiteGraphKernelStore
    public var embeddingProvider: (any EmbeddingProvider)?

    public init(store: SQLiteGraphKernelStore, embeddingProvider: (any EmbeddingProvider)? = nil) {
        self.store = store
        self.embeddingProvider = embeddingProvider
    }

    public func search(query: GraphSearchQuery) async throws -> GraphSearchResponse {
        let perScopeLimit = max(query.limit * 2, query.limit)
        var hits: [GraphSearchHit] = []
        var matchedEntityIDs = Set(query.centerEntityIDs)

        if query.includeStatements {
            let statements = try store.searchStatementsFTS(query: query.text, graphID: query.graphID, limit: perScopeLimit)
                .filter { includes($0.beliefStatus, in: query.beliefStatusFilter) && isTemporallyValid($0, at: query.referenceTime) }
            hits += try statements.enumerated().map { index, statement in
                try statementHit(statement, rank: index + 1, method: "statement_fts_v3", weight: 1.0)
            }
            for statement in statements {
                matchedEntityIDs.insert(statement.subjectEntityID)
                matchedEntityIDs.insert(statement.objectEntityID)
            }
        }

        if query.includeEntities {
            let entities = try store.searchEntitiesFTS(query: query.text, graphID: query.graphID, limit: perScopeLimit)
                .filter { isTemporallyValid($0, at: query.referenceTime) }
            hits += entities.enumerated().map { index, entity in
                entityHit(entity, rank: index + 1, method: "entity_fts_v3", weight: 0.9)
            }
            matchedEntityIDs.formUnion(entities.map(\.id))
        }

        if query.includeEpisodes {
            let episodes = try store.searchEpisodesFTS(query: query.text, graphID: query.graphID, limit: perScopeLimit)
                .filter { includes($0.status, in: query.beliefStatusFilter) }
            hits += episodes.enumerated().map { index, episode in
                episodeHit(episode, rank: index + 1, method: "episode_fts_v3", weight: 0.75)
            }
        }

        hits += try graphNeighborhoodHits(
            graphID: query.graphID,
            entityIDs: matchedEntityIDs,
            referenceTime: query.referenceTime,
            beliefStatusFilter: query.beliefStatusFilter,
            limit: perScopeLimit
        )

        if query.includeEpisodes {
            hits += try sourceEpisodeExpansionHits(from: hits, graphID: query.graphID, limit: perScopeLimit)
        }

        let fused = fuse(hits)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.id < rhs.id }
                return lhs.score > rhs.score
            }
        return GraphSearchResponse(hits: Array(fused.prefix(max(0, query.limit))))
    }

    private func includes(_ status: GraphBeliefStatus, in filter: Set<GraphBeliefStatus>) -> Bool {
        filter.isEmpty || filter.contains(status)
    }

    private func includes(_ status: GraphEntityStatus, in filter: Set<GraphBeliefStatus>) -> Bool {
        filter.isEmpty || (filter.contains(.active) && status == .active)
    }

    private func isTemporallyValid(_ statement: GraphStatement, at referenceTime: Date?) -> Bool {
        guard let referenceTime else { return true }
        if statement.validAt > referenceTime { return false }
        if let invalidAt = statement.invalidAt, invalidAt <= referenceTime { return false }
        return true
    }

    private func isTemporallyValid(_ entity: GraphEntity, at referenceTime: Date?) -> Bool {
        guard let referenceTime else { return true }
        if let validFrom = entity.validFrom, validFrom > referenceTime { return false }
        if let validUntil = entity.validUntil, validUntil <= referenceTime { return false }
        return true
    }

    private func statementHit(_ statement: GraphStatement, rank: Int, method: String, weight: Double) throws -> GraphSearchHit {
        var metadata = [
            "graph_id": statement.graphID,
            "predicate": statement.predicate.rawValue,
            "edge_kind": statement.edgeKind.rawValue,
            "belief_status": statement.beliefStatus.rawValue,
            "subject_entity_id": statement.subjectEntityID,
            "object_entity_id": statement.objectEntityID
        ]
        if let subject = try store.entity(id: statement.subjectEntityID), let object = try store.entity(id: statement.objectEntityID) {
            metadata["graph_context"] = "statement_endpoints"
            metadata["subject_entity_name"] = subject.name
            metadata["subject_entity_kind"] = subject.entityKind.rawValue
            metadata["object_entity_name"] = object.name
            metadata["object_entity_kind"] = object.entityKind.rawValue
            metadata["graph_context_entity_ids"] = [subject.id, object.id].joined(separator: ",")
        }
        return GraphSearchHit(
            ownerType: .statement,
            ownerID: statement.id,
            title: statement.predicate.rawValue,
            text: statement.statementText,
            score: score(forRank: rank, weight: weight),
            retrievalMethod: method,
            sourceEpisodeIDs: statement.sourceEpisodeIDs,
            metadata: metadata
        )
    }

    private func episodeHit(_ episode: GraphEpisodeV3, rank: Int, method: String, weight: Double) -> GraphSearchHit {
        GraphSearchHit(
            ownerType: .episode,
            ownerID: episode.id,
            title: episode.title,
            text: episode.content.isEmpty ? episode.sourceDescription : episode.content,
            score: score(forRank: rank, weight: weight),
            retrievalMethod: method,
            sourceEpisodeIDs: [episode.id],
            metadata: [
                "graph_id": episode.graphID,
                "source_type": episode.sourceType.rawValue,
                "source_id": episode.sourceID ?? "",
                "source_description": episode.sourceDescription,
                "status": episode.status.rawValue
            ]
        )
    }

    private func entityHit(_ entity: GraphEntity, rank: Int, method: String, weight: Double) -> GraphSearchHit {
        GraphSearchHit(
            ownerType: .entity,
            ownerID: entity.id,
            title: entity.name,
            text: entity.summary.isEmpty ? entity.name : entity.summary,
            score: score(forRank: rank, weight: weight),
            retrievalMethod: method,
            metadata: [
                "graph_id": entity.graphID,
                "entity_kind": entity.entityKind.rawValue,
                "scope": entity.scope.rawValue,
                "status": entity.status.rawValue,
                "stable_key": entity.stableKey
            ]
        )
    }

    private func graphNeighborhoodHits(
        graphID: String,
        entityIDs: Set<String>,
        referenceTime: Date?,
        beliefStatusFilter: Set<GraphBeliefStatus>,
        limit: Int
    ) throws -> [GraphSearchHit] {
        guard !entityIDs.isEmpty else { return [] }
        let statements = try store.statements(graphID: graphID)
            .filter { entityIDs.contains($0.subjectEntityID) || entityIDs.contains($0.objectEntityID) }
            .filter { includes($0.beliefStatus, in: beliefStatusFilter) && isTemporallyValid($0, at: referenceTime) }
            .prefix(limit)
        return try statements.enumerated().map { index, statement in
            var hit = try statementHit(statement, rank: index + 1, method: "graph_neighborhood_v1", weight: 0.55)
            hit.metadata["graph_context"] = "neighborhood_expansion"
            hit.metadata["graph_context_entity_ids"] = [statement.subjectEntityID, statement.objectEntityID].joined(separator: ",")
            return hit
        }
    }

    private func sourceEpisodeExpansionHits(from hits: [GraphSearchHit], graphID: String, limit: Int) throws -> [GraphSearchHit] {
        var episodeIDs: [String] = []
        var seen = Set<String>()
        for hit in hits {
            for episodeID in hit.sourceEpisodeIDs where !seen.contains(episodeID) {
                seen.insert(episodeID)
                episodeIDs.append(episodeID)
            }
        }
        return try episodeIDs.prefix(limit).enumerated().compactMap { index, episodeID in
            guard let episode = try store.episode(id: episodeID), episode.graphID == graphID else { return nil }
            var hit = episodeHit(episode, rank: index + 1, method: "source_episode_expansion_v1", weight: 0.35)
            hit.metadata["graph_context"] = "source_episode_expansion"
            return hit
        }
    }

    private func fuse(_ hits: [GraphSearchHit]) -> [GraphSearchHit] {
        var best: [String: GraphSearchHit] = [:]
        for hit in hits {
            if var existing = best[hit.id] {
                existing.score += hit.score
                existing.retrievalMethod = fusedMethods(existing.retrievalMethod, hit.retrievalMethod)
                existing.metadata["fusion_methods"] = existing.retrievalMethod
                existing.sourceEpisodeIDs = Array(Set(existing.sourceEpisodeIDs + hit.sourceEpisodeIDs)).sorted()
                for (key, value) in hit.metadata where existing.metadata[key] == nil {
                    existing.metadata[key] = value
                }
                best[hit.id] = existing
            } else {
                var newHit = hit
                newHit.metadata["fusion_methods"] = hit.retrievalMethod
                best[hit.id] = newHit
            }
        }
        return Array(best.values)
    }

    private func fusedMethods(_ lhs: String, _ rhs: String) -> String {
        Array(Set((lhs + "+" + rhs).split(separator: "+").map(String.init))).sorted().joined(separator: "+")
    }

    private func score(forRank rank: Int, weight: Double = 1.0) -> Double {
        weight / Double(60 + max(rank, 1))
    }
}
