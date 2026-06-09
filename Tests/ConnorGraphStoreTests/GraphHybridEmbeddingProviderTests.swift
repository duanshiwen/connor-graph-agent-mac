import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
@testable import ConnorGraphStore

private struct QueryAwareTestEmbeddingProvider: EmbeddingProvider {
    let model = "query-aware-test-v1"
    let dimensions = 2

    func embedding(for text: String) async throws -> [Double] {
        let lowercased = text.lowercased()
        if lowercased.contains("agent os") || lowercased.contains("graphiti") {
            return [1.0, 0.0]
        }
        return [0.0, 1.0]
    }
}

@Test func sqliteHybridSearchUsesEmbeddingProviderWhenQueryEmbeddingIsMissing() async throws {
    let store = try SQLiteGraphStore(path: temporaryHybridEmbeddingProviderDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-provider", groupID: "default", sourceType: .chatMessage, name: "Provider episode", content: "Graph semantic note", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-shiwen-provider", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let target = GraphNodeV2(id: "node-agent-provider", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS")
    let fact = GraphFact(id: "fact-provider", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .worksOn, fact: "诗闻正在设计 Agent OS 的 Graphiti-grade memory。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    _ = try await store.processPendingEmbeddingIndexTasks(provider: QueryAwareTestEmbeddingProvider(), limit: 20)
    try store.processPendingFTSIndexTasks(limit: 20)

    let service = SQLiteGraphHybridSearchService(store: store, embeddingProvider: QueryAwareTestEmbeddingProvider())
    let response = try await service.search(query: GraphSearchQuery(
        text: "local Agent OS memory",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 5
    ))

    #expect(response.hits.map(\.ownerID) == [fact.id])
    #expect(response.hits.first?.retrievalMethod == "semantic")
}

@Test func explicitQueryEmbeddingOverridesHybridSearchEmbeddingProvider() async throws {
    let store = try SQLiteGraphStore(path: temporaryHybridEmbeddingProviderDatabaseURL().path)
    try store.migrate()

    let episode = GraphEpisode(id: "episode-explicit", groupID: "default", sourceType: .chatMessage, name: "Explicit episode", content: "Explicit semantic note", sourceDescription: "chat")
    let source = GraphNodeV2(id: "node-shiwen-explicit", groupID: "default", type: .person, canonicalName: "诗闻", title: "诗闻")
    let target = GraphNodeV2(id: "node-agent-explicit", groupID: "default", type: .workObject, canonicalName: "Agent OS", title: "Agent OS")
    let fact = GraphFact(id: "fact-explicit", groupID: "default", sourceNodeID: source.id, targetNodeID: target.id, relation: .worksOn, fact: "诗闻正在设计 Agent OS 的 Graphiti-grade memory。")

    try store.upsert(episode: episode)
    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact, sourceEpisodeIDs: [episode.id])
    try store.upsert(embedding: GraphEmbedding(id: "embedding-explicit", groupID: "default", ownerType: .fact, ownerID: fact.id, embeddingModel: "query-aware-test-v1", vector: [1.0, 0.0], contentHash: "explicit"))

    let service = SQLiteGraphHybridSearchService(store: store, embeddingProvider: QueryAwareTestEmbeddingProvider())
    let response = try await service.search(query: GraphSearchQuery(
        text: "Agent OS should not matter because explicit vector points away",
        groupID: "default",
        includeNodes: false,
        includeFacts: true,
        includeEpisodes: false,
        limit: 5,
        embeddingModel: "query-aware-test-v1",
        queryEmbedding: [0.0, 1.0]
    ))

    #expect(response.hits.isEmpty)
}

private func temporaryHybridEmbeddingProviderDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-hybrid-embedding-provider-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}
