import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphStore

private func temporaryHybridSemanticDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func sqliteHybridSearchReturnsSemanticFactHitsWhenFTSDoesNotMatch() async throws {
    let store = try SQLiteGraphStore(path: temporaryHybridSemanticDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-semantic", groupID: "default", sourceType: .chatMessage, name: "Design note", content: "本地记忆系统设计记录。", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-shiwen", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let target = GraphNodeV2(id: "node-agent", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS")
    let fact = GraphFact(id: "fact-semantic", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .worksOn, fact: "诗闻正在建设本地优先的长期记忆图谱。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.upsert(embedding: GraphEmbedding(id: "embedding-fact-semantic", groupID: "default", ownerType: .fact, ownerID: fact.id, embeddingModel: "test-embedding-v1", vector: [1.0, 0.0, 0.0], contentHash: "fact-semantic"))
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "durable personal memory",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 5,
        embeddingModel: "test-embedding-v1",
        queryEmbedding: [0.95, 0.05, 0.0]
    ))

    #expect(response.hits.map(\.ownerID) == ["fact-semantic"])
    #expect(response.hits.first?.retrievalMethod == "semantic")
    #expect(response.hits.first?.sourceEpisodeIDs == ["episode-semantic"])
}

@Test func sqliteHybridSearchDeduplicatesFTSAndSemanticHitsWithHybridMethod() async throws {
    let store = try SQLiteGraphStore(path: temporaryHybridSemanticDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-hybrid", groupID: "default", sourceType: .chatMessage, name: "Hybrid note", content: "Graphiti memory", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-shiwen", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let target = GraphNodeV2(id: "node-agent", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS")
    let fact = GraphFact(id: "fact-hybrid", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .worksOn, fact: "诗闻正在设计 Graphiti memory 系统。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.upsert(embedding: GraphEmbedding(id: "embedding-fact-hybrid", groupID: "default", ownerType: .fact, ownerID: fact.id, embeddingModel: "test-embedding-v1", vector: [1.0, 0.0], contentHash: "fact-hybrid"))
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "Graphiti",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 5,
        embeddingModel: "test-embedding-v1",
        queryEmbedding: [1.0, 0.0]
    ))

    #expect(response.hits.map(\.ownerID) == ["fact-hybrid"])
    #expect(response.hits.first?.retrievalMethod == "hybrid")
}
