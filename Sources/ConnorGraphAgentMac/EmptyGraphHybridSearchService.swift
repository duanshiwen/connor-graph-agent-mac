import ConnorGraphSearch

struct EmptyGraphHybridSearchService: GraphHybridSearchService, Sendable {
    func search(query: GraphSearchQuery) async throws -> GraphSearchResponse {
        GraphSearchResponse(hits: [])
    }
}
