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
        let perScopeLimit = max(query.limit * query.reranking.candidatePoolMultiplier, query.limit)
        var hits: [GraphSearchHit] = []
        var matchedEntityIDs = Set(query.centerEntityIDs)
        let queryTerms = normalizedTerms(query.text)

        if query.includeStatements {
            let statements = try store.searchStatementsFTS(query: query.text, graphID: query.graphID, limit: perScopeLimit)
                .filter { includes($0.beliefStatus, in: query.beliefStatusFilter) && isTemporallyValid($0, at: query.referenceTime) }
            hits += try statements.enumerated().map { index, statement in
                var hit = try statementHit(statement, rank: index + 1, method: "statement_fts_v3", weight: 1.0)
                annotateLexicalEvidence(&hit, queryTerms: queryTerms)
                return hit
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
                var hit = entityHit(entity, rank: index + 1, method: "entity_fts_v3", weight: 0.9)
                annotateLexicalEvidence(&hit, queryTerms: queryTerms)
                return hit
            }
            matchedEntityIDs.formUnion(entities.map(\.id))
        }

        if query.includeEpisodes {
            let episodes = try store.searchEpisodesFTS(query: query.text, graphID: query.graphID, limit: perScopeLimit)
                .filter { includes($0.status, in: query.beliefStatusFilter) }
            hits += episodes.enumerated().map { index, episode in
                var hit = episodeHit(episode, rank: index + 1, method: "episode_fts_v3", weight: 0.75)
                annotateLexicalEvidence(&hit, queryTerms: queryTerms)
                return hit
            }
        }

        hits += try graphNeighborhoodHits(
            graphID: query.graphID,
            entityIDs: matchedEntityIDs,
            referenceTime: query.referenceTime,
            beliefStatusFilter: query.beliefStatusFilter,
            queryTerms: queryTerms,
            depth: query.reranking.graphExpansionDepth,
            limit: perScopeLimit
        )

        if query.includeEpisodes {
            hits += try sourceEpisodeExpansionHits(from: hits, graphID: query.graphID, limit: perScopeLimit)
        }

        let fused = fuse(hits)
        let reranked = rerank(fused, query: query, queryTerms: queryTerms)
        return GraphSearchResponse(hits: Array(reranked.prefix(max(0, query.limit))))
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
            "confidence": "\(statement.confidence)",
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
        queryTerms: Set<String>,
        depth: Int,
        limit: Int
    ) throws -> [GraphSearchHit] {
        guard !entityIDs.isEmpty, depth > 0 else { return [] }
        let allStatements = try store.statements(graphID: graphID)
            .filter { includes($0.beliefStatus, in: beliefStatusFilter) && isTemporallyValid($0, at: referenceTime) }
        var frontier = entityIDs
        var visitedEntities = entityIDs
        var hits: [GraphSearchHit] = []
        var seenStatements = Set<String>()

        for hop in 1...depth {
            guard !frontier.isEmpty, hits.count < limit else { break }
            var nextFrontier = Set<String>()
            var rank = 1
            for statement in allStatements {
                guard hits.count < limit else { break }
                guard !seenStatements.contains(statement.id) else { continue }
                guard frontier.contains(statement.subjectEntityID) || frontier.contains(statement.objectEntityID) else { continue }
                seenStatements.insert(statement.id)
                nextFrontier.insert(statement.subjectEntityID)
                nextFrontier.insert(statement.objectEntityID)
                var hit = try statementHit(statement, rank: rank, method: "graph_neighborhood_hop\(hop)_v2", weight: max(0.18, 0.62 / Double(hop)))
                hit.metadata["graph_context"] = "neighborhood_expansion"
                hit.metadata["graph_hop"] = "\(hop)"
                hit.metadata["graph_expansion_depth"] = "\(depth)"
                hit.metadata["graph_context_entity_ids"] = [statement.subjectEntityID, statement.objectEntityID].joined(separator: ",")
                annotateLexicalEvidence(&hit, queryTerms: queryTerms)
                hits.append(hit)
                rank += 1
            }
            nextFrontier.subtract(visitedEntities)
            visitedEntities.formUnion(nextFrontier)
            frontier = nextFrontier
        }
        return hits
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

    private func rerank(_ hits: [GraphSearchHit], query: GraphSearchQuery, queryTerms: Set<String>) -> [GraphSearchHit] {
        var reranked = hits.map { hit in
            var mutable = hit
            var score = hit.score
            var reasons: [String] = []

            if query.reranking.strategies.contains(.graphitiLocal) {
                let lexical = lexicalOverlapScore(hit: hit, queryTerms: queryTerms)
                if lexical > 0 {
                    score += lexical * 0.08
                    reasons.append("lexical_overlap")
                }
                if hit.ownerType == .statement, hit.metadata["graph_context"] == "statement_endpoints" {
                    score += 0.025
                    reasons.append("endpoint_context")
                }
                if let confidence = Double(hit.metadata["confidence"] ?? ""), confidence > 0 {
                    score += min(confidence, 1.0) * 0.02
                    reasons.append("confidence")
                }
            }

            if query.reranking.strategies.contains(.episodeMentions) {
                let overlap = Set(hit.sourceEpisodeIDs).intersection(query.reranking.episodeMentionEpisodeIDs)
                if !overlap.isEmpty {
                    score += 0.12
                    reasons.append("episode_mentions:\(overlap.sorted().joined(separator: ","))")
                }
            }

            mutable.score = score
            if !reasons.isEmpty {
                mutable.metadata["rerank_reasons"] = reasons.joined(separator: ";")
            }
            mutable.metadata["retrieval_pipeline"] = "fts+graph_expansion+rrf+local_rerank"
            return mutable
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.id < rhs.id }
            return lhs.score > rhs.score
        }

        if query.reranking.strategies.contains(.maximalMarginalRelevance) {
            reranked = maximalMarginalRelevance(reranked, lambda: query.reranking.mmrLambda)
        }
        return reranked
    }

    private func maximalMarginalRelevance(_ hits: [GraphSearchHit], lambda: Double) -> [GraphSearchHit] {
        guard hits.count > 2 else { return hits }
        let lambda = max(0.0, min(lambda, 1.0))
        var remaining = hits
        var selected: [GraphSearchHit] = []
        while !remaining.isEmpty {
            var bestIndex = 0
            var bestScore = mmrScore(remaining[0], selected: selected, lambda: lambda)
            if remaining.count > 1 {
                for index in 1..<remaining.count {
                    let score = mmrScore(remaining[index], selected: selected, lambda: lambda)
                    if score > bestScore || (score == bestScore && remaining[index].id < remaining[bestIndex].id) {
                        bestIndex = index
                        bestScore = score
                    }
                }
            }
            var chosen = remaining.remove(at: bestIndex)
            chosen.metadata["mmr_selected_rank"] = "\(selected.count + 1)"
            selected.append(chosen)
        }
        return selected
    }

    private func mmrScore(_ hit: GraphSearchHit, selected: [GraphSearchHit], lambda: Double) -> Double {
        guard !selected.isEmpty else { return hit.score }
        let maxSimilarity = selected.map { similarity(lhs: hit, rhs: $0) }.max() ?? 0
        return lambda * hit.score - (1 - lambda) * maxSimilarity
    }

    private func similarity(lhs: GraphSearchHit, rhs: GraphSearchHit) -> Double {
        if lhs.ownerType == rhs.ownerType { return 0.12 }
        let lhsEntities = Set((lhs.metadata["graph_context_entity_ids"] ?? "").split(separator: ",").map(String.init))
        let rhsEntities = Set((rhs.metadata["graph_context_entity_ids"] ?? "").split(separator: ",").map(String.init))
        guard !lhsEntities.isEmpty || !rhsEntities.isEmpty else { return 0 }
        let intersection = lhsEntities.intersection(rhsEntities).count
        let union = lhsEntities.union(rhsEntities).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func annotateLexicalEvidence(_ hit: inout GraphSearchHit, queryTerms: Set<String>) {
        let overlap = lexicalOverlaps(hit: hit, queryTerms: queryTerms)
        if !overlap.isEmpty {
            hit.metadata["matched_terms"] = overlap.sorted().joined(separator: ",")
            hit.metadata["lexical_overlap_count"] = "\(overlap.count)"
        }
    }

    private func lexicalOverlapScore(hit: GraphSearchHit, queryTerms: Set<String>) -> Double {
        guard !queryTerms.isEmpty else { return 0 }
        return Double(lexicalOverlaps(hit: hit, queryTerms: queryTerms).count) / Double(queryTerms.count)
    }

    private func lexicalOverlaps(hit: GraphSearchHit, queryTerms: Set<String>) -> Set<String> {
        let haystack = normalizedTerms([hit.title, hit.text, hit.metadata["subject_entity_name"] ?? "", hit.metadata["object_entity_name"] ?? ""].joined(separator: " "))
        return queryTerms.intersection(haystack)
    }

    private func normalizedTerms(_ text: String) -> Set<String> {
        let normalized = NativeSearchQueryNormalizer.normalize(text)
        var values = normalized.displayTokenValues
        values.append(contentsOf: normalized.strongTokens.map(\.value))
        values.append(contentsOf: normalized.scoringTokens.filter { !$0.isSoftStopWord }.map(\.value))
        return Set(values.filter { $0.count >= 2 || text.count <= 2 })
    }

    private func score(forRank rank: Int, weight: Double = 1.0) -> Double {
        weight / Double(60 + max(rank, 1))
    }
}
