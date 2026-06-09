import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
@testable import ConnorGraphStore

@Test func sqliteHybridSearchKeepsLocalFirstWhenCrossEncoderAdapterIsMissing() async throws {
    let store = try SQLiteGraphStore(path: temporaryCrossEncoderDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-cross-missing", groupID: "default", sourceType: .chatMessage, name: "Cross encoder missing", content: "memory", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-cross-missing", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻")
    let agentOS = GraphNodeV2(id: "node-agent-cross-missing", groupID: "default", type: .workObject, canonicalName: "agent-os", title: "Agent OS")
    let fact = GraphFact(id: "fact-cross-missing", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: agentOS.id, relation: .worksOn, fact: "诗闻正在设计长期记忆系统。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: agentOS)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "长期记忆",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 1,
        centerNodeIDs: [agentOS.id],
        reranking: GraphRerankingConfig(strategies: [.graphitiLocal, .crossEncoder])
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.ownerID == fact.id)
    #expect(hit.metadata["graph_reranker"] == "graphiti_local")
    #expect(hit.metadata["graph_ranking"] == "boosted")
    #expect(hit.metadata["cross_encoder_status"] == "unavailable")
    #expect(hit.metadata["graph_reranking_strategies"] == "graphiti_local,cross_encoder")
}

@Test func sqliteHybridSearchAppliesInjectedCrossEncoderScores() async throws {
    let store = try SQLiteGraphStore(path: temporaryCrossEncoderDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-cross-applied", groupID: "default", sourceType: .chatMessage, name: "Cross encoder applied", content: "memory", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-cross-applied", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻")
    let firstTarget = GraphNodeV2(id: "node-first-cross-applied", groupID: "default", type: .entity, canonicalName: "first", title: "First")
    let secondTarget = GraphNodeV2(id: "node-second-cross-applied", groupID: "default", type: .entity, canonicalName: "second", title: "Second")
    let firstFact = GraphFact(id: "fact-first-cross-applied", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: firstTarget.id, relation: .mentions, fact: "Graphiti reranking memory candidate one.")
    let secondFact = GraphFact(id: "fact-second-cross-applied", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: secondTarget.id, relation: .mentions, fact: "Graphiti reranking memory candidate two.")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: firstTarget)
    try store.upsert(nodeV2: secondTarget)
    try store.upsert(fact: firstFact, sourceEpisodeIDs: [episode.id])
    try store.upsert(fact: secondFact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let reranker = StaticCrossEncoderReranker(scoresByOwnerID: [
        firstFact.id: 0.10,
        secondFact.id: 0.95
    ])
    let service = SQLiteGraphHybridSearchService(store: store, crossEncoderReranker: reranker)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti reranking memory candidate",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 2,
        reranking: GraphRerankingConfig(strategies: [.graphitiLocal, .crossEncoder], crossEncoderTopK: 2)
    ))

    #expect(response.hits.map(\.ownerID) == [secondFact.id, firstFact.id])
    let topHit = try #require(response.hits.first)
    #expect(topHit.metadata["cross_encoder_score"] == "0.950000")
    #expect(topHit.metadata["cross_encoder_reranked"] == "true")
    #expect(topHit.metadata["graph_reranking_strategies"] == "graphiti_local,cross_encoder")
}

@Test func sqliteHybridSearchMarksCandidatesOutsideCrossEncoderTopKAsSkipped() async throws {
    let store = try SQLiteGraphStore(path: temporaryCrossEncoderDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-cross-top-k", groupID: "default", sourceType: .chatMessage, name: "Cross top k", content: "memory", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-source-cross-top-k", groupID: "default", type: .entity, canonicalName: "source", title: "Source")
    let firstTarget = GraphNodeV2(id: "node-first-cross-top-k", groupID: "default", type: .entity, canonicalName: "first", title: "First")
    let secondTarget = GraphNodeV2(id: "node-second-cross-top-k", groupID: "default", type: .entity, canonicalName: "second", title: "Second")
    let firstFact = GraphFact(id: "fact-first-cross-top-k", groupID: "default", sourceNodeID: source.id, targetNodeID: firstTarget.id, relation: .mentions, fact: "Graphiti cross encoder top k memory first.")
    let secondFact = GraphFact(id: "fact-second-cross-top-k", groupID: "default", sourceNodeID: source.id, targetNodeID: secondTarget.id, relation: .mentions, fact: "Graphiti cross encoder top k memory second.")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: firstTarget)
    try store.upsert(nodeV2: secondTarget)
    try store.upsert(fact: firstFact, sourceEpisodeIDs: [episode.id])
    try store.upsert(fact: secondFact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(
        store: store,
        crossEncoderReranker: StaticCrossEncoderReranker(scoresByOwnerID: [firstFact.id: 0.90])
    )
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti cross encoder top k memory",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 2,
        reranking: GraphRerankingConfig(strategies: [.graphitiLocal, .crossEncoder], crossEncoderTopK: 1)
    ))

    let rerankedHit = try #require(response.hits.first { $0.metadata["cross_encoder_reranked"] == "true" })
    let skippedHit = try #require(response.hits.first { $0.ownerID != rerankedHit.ownerID })
    #expect(skippedHit.metadata["cross_encoder_status"] == "skipped")
    #expect(skippedHit.metadata["cross_encoder_skip_reason"] == "outside_top_k")
}

@Test func sqliteHybridSearchMarksCrossEncoderTopKZeroAsSkipped() async throws {
    let store = try SQLiteGraphStore(path: temporaryCrossEncoderDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-cross-zero", groupID: "default", sourceType: .chatMessage, name: "Cross zero", content: "memory", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-source-cross-zero", groupID: "default", type: .entity, canonicalName: "source", title: "Source")
    let target = GraphNodeV2(id: "node-target-cross-zero", groupID: "default", type: .entity, canonicalName: "target", title: "Target")
    let fact = GraphFact(id: "fact-cross-zero", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .mentions, fact: "Graphiti cross encoder disabled window memory.")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(
        store: store,
        crossEncoderReranker: StaticCrossEncoderReranker(scoresByOwnerID: [fact.id: 0.90])
    )
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti cross encoder disabled window memory",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 1,
        reranking: GraphRerankingConfig(strategies: [.graphitiLocal, .crossEncoder], crossEncoderTopK: 0)
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.metadata["cross_encoder_status"] == "skipped")
    #expect(hit.metadata["cross_encoder_skip_reason"] == "top_k_zero")
}

@Test func sqliteHybridSearchRecordsCanonicalRerankingStrategyOrder() async throws {
    let store = try SQLiteGraphStore(path: temporaryCrossEncoderDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-strategy-order", groupID: "default", sourceType: .chatMessage, name: "Strategy order", content: "memory", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-source-strategy-order", groupID: "default", type: .entity, canonicalName: "source", title: "Source")
    let target = GraphNodeV2(id: "node-target-strategy-order", groupID: "default", type: .entity, canonicalName: "target", title: "Target")
    let fact = GraphFact(id: "fact-strategy-order", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .mentions, fact: "Graphiti canonical strategy ordering memory.")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti canonical strategy ordering memory",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 1,
        reranking: GraphRerankingConfig(strategies: [.crossEncoder, .maximalMarginalRelevance, .graphitiLocal, .episodeMentions])
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.metadata["graph_reranking_strategies"] == "graphiti_local,episode_mentions,mmr,cross_encoder")
}

private struct StaticCrossEncoderReranker: GraphCrossEncoderReranker {
    var scoresByOwnerID: [String: Double]

    func scores(query: String, candidates: [GraphCrossEncoderCandidate]) async throws -> [GraphCrossEncoderScore] {
        candidates.map { candidate in
            GraphCrossEncoderScore(ownerType: candidate.ownerType, ownerID: candidate.ownerID, score: scoresByOwnerID[candidate.ownerID] ?? 0)
        }
    }
}

private func temporaryCrossEncoderDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-graph-cross-encoder-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}
