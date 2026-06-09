import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
@testable import ConnorGraphStore

@Test func sqliteHybridSearchAppliesMMRToDiversifySimilarCandidates() async throws {
    let store = try SQLiteGraphStore(path: temporaryMMRDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-mmr", groupID: "default", sourceType: .chatMessage, name: "MMR", content: "memory", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-mmr", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻")
    let targetA = GraphNodeV2(id: "node-a-mmr", groupID: "default", type: .entity, canonicalName: "a", title: "A")
    let targetB = GraphNodeV2(id: "node-b-mmr", groupID: "default", type: .entity, canonicalName: "b", title: "B")
    let targetC = GraphNodeV2(id: "node-c-mmr", groupID: "default", type: .entity, canonicalName: "c", title: "C")
    let factA = GraphFact(id: "fact-a-mmr", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: targetA.id, relation: .mentions, fact: "Graphiti memory local search alpha.")
    let factB = GraphFact(id: "fact-b-mmr", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: targetB.id, relation: .mentions, fact: "Graphiti memory local search beta.")
    let factC = GraphFact(id: "fact-c-mmr", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: targetC.id, relation: .mentions, fact: "Graphiti memory local search gamma.")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: targetA)
    try store.upsert(nodeV2: targetB)
    try store.upsert(nodeV2: targetC)
    try store.upsert(fact: factA, sourceEpisodeIDs: [episode.id])
    try store.upsert(fact: factB, sourceEpisodeIDs: [episode.id])
    try store.upsert(fact: factC, sourceEpisodeIDs: [episode.id])
    try store.upsert(embedding: GraphEmbedding(id: "embedding:test-mmr:fact:\(factA.id)", groupID: "default", ownerType: .fact, ownerID: factA.id, embeddingModel: "test-mmr", vector: [1.0, 0.0], contentHash: "a"))
    try store.upsert(embedding: GraphEmbedding(id: "embedding:test-mmr:fact:\(factB.id)", groupID: "default", ownerType: .fact, ownerID: factB.id, embeddingModel: "test-mmr", vector: [0.99, 0.01], contentHash: "b"))
    try store.upsert(embedding: GraphEmbedding(id: "embedding:test-mmr:fact:\(factC.id)", groupID: "default", ownerType: .fact, ownerID: factC.id, embeddingModel: "test-mmr", vector: [0.6, 0.8], contentHash: "c"))
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti memory local search",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 3,
        embeddingModel: "test-mmr",
        queryEmbedding: [1.0, 0.0],
        reranking: GraphRerankingConfig(strategies: [.graphitiLocal, .maximalMarginalRelevance], mmrLambda: 0.2)
    ))

    #expect(response.hits.first?.ownerID == factA.id)
    #expect(response.hits.dropFirst().first?.ownerID == factC.id)
    let secondHit = try #require(response.hits.dropFirst().first)
    #expect(secondHit.metadata["mmr_rank"] == "2")
    #expect(secondHit.metadata["mmr_lambda"] == "0.200000")
    #expect(secondHit.metadata["mmr_score"] != nil)
    #expect(secondHit.metadata["graph_reranking_strategies"] == "graphiti_local,mmr")
}

@Test func sqliteHybridSearchFallsBackWhenMMREmbeddingsAreUnavailable() async throws {
    let store = try SQLiteGraphStore(path: temporaryMMRDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-mmr-fallback", groupID: "default", sourceType: .chatMessage, name: "MMR fallback", content: "memory", sourceDescription: "chat")
    let shiwen = GraphNodeV2(id: "node-shiwen-mmr-fallback", groupID: "default", type: .person, canonicalName: "shiwen", title: "诗闻")
    let target = GraphNodeV2(id: "node-target-mmr-fallback", groupID: "default", type: .entity, canonicalName: "target", title: "Target")
    let fact = GraphFact(id: "fact-mmr-fallback", groupID: "default", sourceNodeID: shiwen.id, targetNodeID: target.id, relation: .mentions, fact: "Graphiti memory local search fallback.")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: shiwen)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti memory local search fallback",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 1,
        reranking: GraphRerankingConfig(strategies: [.graphitiLocal, .maximalMarginalRelevance], mmrLambda: 0.5)
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.ownerID == fact.id)
    #expect(hit.metadata["mmr_status"] == "unavailable")
    #expect(hit.metadata["mmr_embedding_status"] == "missing")
    #expect(hit.metadata["mmr_skip_reason"] == "missing_query_embedding")
    #expect(hit.metadata["graph_reranking_strategies"] == "graphiti_local,mmr")
}

@Test func sqliteHybridSearchMarksMMRUnavailableWhenCandidateEmbeddingsAreMissing() async throws {
    let store = try SQLiteGraphStore(path: temporaryMMRDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-mmr-no-candidates", groupID: "default", sourceType: .chatMessage, name: "MMR no candidates", content: "memory", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-source-mmr-no-candidates", groupID: "default", type: .entity, canonicalName: "source", title: "Source")
    let target = GraphNodeV2(id: "node-target-mmr-no-candidates", groupID: "default", type: .entity, canonicalName: "target", title: "Target")
    let fact = GraphFact(id: "fact-mmr-no-candidates", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .mentions, fact: "Graphiti memory local search without candidate embeddings.")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti memory local search without candidate embeddings",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 1,
        embeddingModel: "test-mmr",
        queryEmbedding: [1.0, 0.0],
        reranking: GraphRerankingConfig(strategies: [.graphitiLocal, .maximalMarginalRelevance], mmrLambda: 0.5)
    ))

    let hit = try #require(response.hits.first)
    #expect(hit.metadata["mmr_status"] == "unavailable")
    #expect(hit.metadata["mmr_embedding_status"] == "missing")
    #expect(hit.metadata["mmr_skip_reason"] == "missing_candidate_embeddings")
}

private func temporaryMMRDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-graph-mmr-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}
