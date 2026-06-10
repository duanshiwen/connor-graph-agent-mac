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

        if query.includeStatements {
            let statements = try store.searchStatementsFTS(query: query.text, graphID: query.graphID, limit: perScopeLimit)
                .filter { includes($0.beliefStatus, in: query.beliefStatusFilter) && isTemporallyValid($0, at: query.referenceTime) }
            hits += try statements.enumerated().map { index, statement in try statementHit(statement, rank: index + 1) }
        }

        if query.includeEntities {
            let entities = try store.searchEntitiesFTS(query: query.text, graphID: query.graphID, limit: perScopeLimit)
                .filter { isTemporallyValid($0, at: query.referenceTime) }
            hits += entities.enumerated().map { index, entity in entityHit(entity, rank: index + 1) }
        }

        if query.includeEpisodes {
            let episodes = try store.searchEpisodesFTS(query: query.text, graphID: query.graphID, limit: perScopeLimit)
                .filter { includes($0.status, in: query.beliefStatusFilter) }
            hits += episodes.enumerated().map { index, episode in episodeHit(episode, rank: index + 1) }
        }

        let deduped = dedupe(hits)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.id < rhs.id }
                return lhs.score > rhs.score
            }
        return GraphSearchResponse(hits: Array(deduped.prefix(max(0, query.limit))))
    }

    private func includes(_ status: GraphBeliefStatus, in filter: Set<GraphBeliefStatus>) -> Bool {
        filter.isEmpty || filter.contains(status)
    }

    private func includes(_ status: GraphEntityStatus, in filter: Set<GraphBeliefStatus>) -> Bool {
        filter.isEmpty || filter.contains(.active) && status == .active
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

    private func statementHit(_ statement: GraphStatement, rank: Int) throws -> GraphSearchHit {
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
            score: score(forRank: rank),
            retrievalMethod: "fts_v3",
            sourceEpisodeIDs: statement.sourceEpisodeIDs,
            metadata: metadata
        )
    }

    private func episodeHit(_ episode: GraphEpisodeV3, rank: Int) -> GraphSearchHit {
        GraphSearchHit(
            ownerType: .episode,
            ownerID: episode.id,
            title: episode.title,
            text: episode.content.isEmpty ? episode.sourceDescription : episode.content,
            score: score(forRank: rank),
            retrievalMethod: "episode_fts_v3",
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

    private func entityHit(_ entity: GraphEntity, rank: Int) -> GraphSearchHit {
        GraphSearchHit(
            ownerType: .entity,
            ownerID: entity.id,
            title: entity.name,
            text: entity.summary.isEmpty ? entity.name : entity.summary,
            score: score(forRank: rank),
            retrievalMethod: "fts_v3",
            metadata: [
                "graph_id": entity.graphID,
                "entity_kind": entity.entityKind.rawValue,
                "scope": entity.scope.rawValue,
                "status": entity.status.rawValue,
                "stable_key": entity.stableKey
            ]
        )
    }

    private func dedupe(_ hits: [GraphSearchHit]) -> [GraphSearchHit] {
        var best: [String: GraphSearchHit] = [:]
        for hit in hits {
            if let existing = best[hit.id] {
                if hit.score > existing.score { best[hit.id] = hit }
            } else {
                best[hit.id] = hit
            }
        }
        return Array(best.values)
    }

    private func score(forRank rank: Int) -> Double {
        1.0 / Double(max(rank, 1))
    }
}
