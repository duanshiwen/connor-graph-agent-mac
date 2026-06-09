import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryEmbeddingDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphStoreSavesLoadsAndSearchesEmbeddingsByCosineSimilarity() throws {
    let store = try SQLiteGraphStore(path: temporaryEmbeddingDatabaseURL().path)
    try store.migrate()
    let createdAt = Date(timeIntervalSince1970: 1_000)
    let agentEmbedding = GraphEmbedding(
        id: "embedding-agent",
        groupID: "default",
        ownerType: .fact,
        ownerID: "fact-agent",
        embeddingModel: "test-embedding-v1",
        vector: [1.0, 0.0, 0.0],
        contentHash: "agent-hash",
        createdAt: createdAt
    )
    let unrelatedEmbedding = GraphEmbedding(
        id: "embedding-unrelated",
        groupID: "default",
        ownerType: .node,
        ownerID: "node-unrelated",
        embeddingModel: "test-embedding-v1",
        vector: [0.0, 1.0, 0.0],
        contentHash: "unrelated-hash",
        createdAt: createdAt
    )

    try store.upsert(embedding: unrelatedEmbedding)
    try store.upsert(embedding: agentEmbedding)

    let loaded = try #require(try store.graphEmbedding(id: "embedding-agent"))
    #expect(loaded == agentEmbedding)

    let results = try store.searchEmbeddings(
        queryVector: [0.9, 0.1, 0.0],
        groupID: "default",
        embeddingModel: "test-embedding-v1",
        ownerTypes: [.fact, .node],
        limit: 10
    )

    #expect(results.map(\.embedding.ownerID) == ["fact-agent", "node-unrelated"])
    #expect(results[0].score > results[1].score)
    #expect(results[0].score > 0.99)
}

@Test func graphStoreEmbeddingSearchFiltersGroupModelOwnerTypeAndDimensions() throws {
    let store = try SQLiteGraphStore(path: temporaryEmbeddingDatabaseURL().path)
    try store.migrate()

    try store.upsert(embedding: GraphEmbedding(id: "same", groupID: "default", ownerType: .fact, ownerID: "fact-same", embeddingModel: "model-a", vector: [1.0, 0.0], contentHash: "same"))
    try store.upsert(embedding: GraphEmbedding(id: "other-group", groupID: "other", ownerType: .fact, ownerID: "fact-other-group", embeddingModel: "model-a", vector: [1.0, 0.0], contentHash: "other-group"))
    try store.upsert(embedding: GraphEmbedding(id: "other-model", groupID: "default", ownerType: .fact, ownerID: "fact-other-model", embeddingModel: "model-b", vector: [1.0, 0.0], contentHash: "other-model"))
    try store.upsert(embedding: GraphEmbedding(id: "other-type", groupID: "default", ownerType: .episode, ownerID: "episode-other-type", embeddingModel: "model-a", vector: [1.0, 0.0], contentHash: "other-type"))
    try store.upsert(embedding: GraphEmbedding(id: "other-dimensions", groupID: "default", ownerType: .fact, ownerID: "fact-other-dimensions", embeddingModel: "model-a", vector: [1.0, 0.0, 0.0], contentHash: "other-dimensions"))

    let results = try store.searchEmbeddings(
        queryVector: [1.0, 0.0],
        groupID: "default",
        embeddingModel: "model-a",
        ownerTypes: [.fact],
        limit: 10
    )

    #expect(results.map(\.embedding.ownerID) == ["fact-same"])
}
