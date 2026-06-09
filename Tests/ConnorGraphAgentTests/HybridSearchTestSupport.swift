import ConnorGraphSearch

struct TestHybridSearchService: GraphHybridSearchService, Sendable {
    var response: GraphSearchResponse

    init(hits: [GraphSearchHit] = []) {
        self.response = GraphSearchResponse(hits: hits)
    }

    init(response: GraphSearchResponse) {
        self.response = response
    }

    func search(query: GraphSearchQuery) async throws -> GraphSearchResponse {
        response
    }
}
