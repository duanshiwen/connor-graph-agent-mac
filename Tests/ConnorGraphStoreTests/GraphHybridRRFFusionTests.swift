import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
@testable import ConnorGraphStore

@Test func sqliteHybridSearchUsesRRFFusionForFTSAndSemanticRanks() async throws {
    let store = try SQLiteGraphStore(path: temporaryHybridRRFDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-rrf", groupID: "default", sourceType: .chatMessage, name: "RRF episode", content: "Graphiti memory", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-shiwen-rrf", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let target = GraphNodeV2(id: "node-agent-rrf", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS")
    let ftsOnlyFact = GraphFact(id: "fact-fts-only", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .mentions, fact: "Graphiti appears in a lexical-only note.")
    let hybridFact = GraphFact(id: "fact-hybrid-rrf", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .worksOn, fact: "诗闻正在设计 Graphiti memory 系统。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: ftsOnlyFact, sourceEpisodeIDs: [episode.id])
    try store.upsert(fact: hybridFact, sourceEpisodeIDs: [episode.id])
    try store.upsert(embedding: GraphEmbedding(id: "embedding-hybrid-rrf", groupID: "default", ownerType: .fact, ownerID: hybridFact.id, embeddingModel: "rrf-test-v1", vector: [1.0, 0.0], contentHash: "hybrid"))
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 2,
        embeddingModel: "rrf-test-v1",
        queryEmbedding: [1.0, 0.0]
    ))

    #expect(response.hits.first?.ownerID == hybridFact.id)
    #expect(response.hits.first?.retrievalMethod == "hybrid")
    #expect(response.hits.first?.metadata["fusion"] == "rrf")
    #expect(response.hits.first?.metadata["retrieval_methods"] == "fts,semantic")
    #expect(response.hits.first?.metadata["rrf_fts_rank"] != nil)
    #expect(response.hits.first?.metadata["rrf_semantic_rank"] == "1")
    #expect((response.hits.first?.score ?? 0) < 1.0)
    #expect((response.hits.first?.score ?? 0) > (response.hits.dropFirst().first?.score ?? 0))
}

@Test func sqliteHybridSearchRecordsRRFRankMetadataForSemanticOnlyHits() async throws {
    let store = try SQLiteGraphStore(path: temporaryHybridRRFDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-semantic-rrf", groupID: "default", sourceType: .chatMessage, name: "Semantic RRF episode", content: "semantic", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-shiwen-semantic-rrf", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let target = GraphNodeV2(id: "node-agent-semantic-rrf", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS")
    let fact = GraphFact(id: "fact-semantic-rrf", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .worksOn, fact: "诗闻正在设计 Agent OS 长期记忆。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.upsert(embedding: GraphEmbedding(id: "embedding-semantic-rrf", groupID: "default", ownerType: .fact, ownerID: fact.id, embeddingModel: "rrf-test-v1", vector: [1.0, 0.0], contentHash: "semantic"))
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "lexical miss",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 1,
        embeddingModel: "rrf-test-v1",
        queryEmbedding: [1.0, 0.0]
    ))

    #expect(response.hits.map(\.ownerID) == [fact.id])
    #expect(response.hits.first?.retrievalMethod == "semantic")
    #expect(response.hits.first?.metadata["fusion"] == "rrf")
    #expect(response.hits.first?.metadata["retrieval_methods"] == "semantic")
    #expect(response.hits.first?.metadata["rrf_semantic_rank"] == "1")
    #expect(response.hits.first?.metadata["rrf_fts_rank"] == nil)
}

private func temporaryHybridRRFDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-hybrid-rrf-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}
