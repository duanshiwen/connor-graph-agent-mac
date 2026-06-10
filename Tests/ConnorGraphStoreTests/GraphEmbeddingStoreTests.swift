import Testing
import ConnorGraphCore

@Test func graphEmbeddingComputesVectorNorm() throws {
    let embedding = GraphEmbedding(
        id: "embedding-1",
        graphID: "default",
        ownerType: .statement,
        ownerID: "statement-1",
        embeddingModel: "test-model",
        vector: [3.0, 4.0],
        contentHash: "hash"
    )

    #expect(embedding.vectorNorm == 5.0)
}

@Test func graphEmbeddingSearchResultCarriesScore() throws {
    let embedding = GraphEmbedding(
        id: "embedding-1",
        graphID: "default",
        ownerType: .entity,
        ownerID: "entity-1",
        embeddingModel: "test-model",
        vector: [1.0, 0.0],
        contentHash: "hash"
    )

    let result = GraphEmbeddingSearchResult(embedding: embedding, score: 0.95)

    #expect(result.embedding == embedding)
    #expect(result.score == 0.95)
}
