import Testing
import ConnorGraphSearch

@Test func graphRerankingConfigCarriesPhase6RetrievalControls() throws {
    let config = GraphRerankingConfig(graphExpansionDepth: 9, candidatePoolMultiplier: 20)
    #expect(config.graphExpansionDepth == 4)
    #expect(config.candidatePoolMultiplier == 10)

    let query = GraphSearchQuery(text: "Alice", graphID: "default", reranking: config)
    #expect(query.reranking.graphExpansionDepth == 4)
    #expect(query.reranking.candidatePoolMultiplier == 10)
}
