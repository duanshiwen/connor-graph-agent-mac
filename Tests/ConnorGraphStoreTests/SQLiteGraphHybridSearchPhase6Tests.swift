import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphStore

private func temporaryPhase6SearchDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphRetrievalExpandsNeighborhoodAcrossConfiguredDepth() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryPhase6SearchDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 2_000)
    let alice = GraphEntity(id: "entity-alice", graphID: "default", name: "Alice", entityKind: .personObject, scope: .project, canonicalClassID: "person")
    let bob = GraphEntity(id: "entity-bob", graphID: "default", name: "Bob", entityKind: .personObject, scope: .project, canonicalClassID: "person")
    let carol = GraphEntity(id: "entity-carol", graphID: "default", name: "Carol", entityKind: .personObject, scope: .project, canonicalClassID: "person")
    try store.upsert(entity: alice)
    try store.upsert(entity: bob)
    try store.upsert(entity: carol)
    try store.upsert(statement: GraphStatement(
        id: "statement-alice-bob",
        graphID: "default",
        subjectEntityID: alice.id,
        predicate: .knowsPerson,
        objectEntityID: bob.id,
        statementText: "Alice knows Bob.",
        validAt: now,
        committedAt: now,
        confidence: 0.9
    ))
    try store.upsert(statement: GraphStatement(
        id: "statement-bob-carol",
        graphID: "default",
        subjectEntityID: bob.id,
        predicate: .knowsPerson,
        objectEntityID: carol.id,
        statementText: "Bob knows Carol.",
        validAt: now,
        committedAt: now,
        confidence: 0.9
    ))

    let service = SQLiteGraphHybridSearchService(store: store)
    let oneHopQuery = GraphSearchQuery(text: "seed", graphID: "default", includeEntities: false, includeStatements: false, includeEpisodes: false, limit: 10, centerEntityIDs: [alice.id], reranking: GraphRerankingConfig(strategies: [.graphitiLocal], graphExpansionDepth: 1))
    let oneHop = try await service.search(query: oneHopQuery)
    #expect(oneHop.hits.contains { $0.ownerID == "statement-alice-bob" })
    #expect(oneHop.hits.contains { $0.ownerID == "statement-bob-carol" } == false)

    let twoHop = try await service.search(query: GraphSearchQuery(text: "seed", graphID: "default", includeEntities: false, includeStatements: false, includeEpisodes: false, limit: 10, centerEntityIDs: [alice.id], reranking: GraphRerankingConfig(strategies: [.graphitiLocal], graphExpansionDepth: 2)))
    let secondHop = try #require(twoHop.hits.first { $0.ownerID == "statement-bob-carol" })
    #expect(secondHop.retrievalMethod.contains("graph_neighborhood_hop2_v2"))
    #expect(secondHop.metadata["graph_hop"] == "2")
    #expect(secondHop.metadata["retrieval_pipeline"] == "fts+graph_expansion+rrf+local_rerank")
}

@Test func graphRetrievalAddsLocalRerankAndMatchedTermExplanations() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryPhase6SearchDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 3_000)
    let shiwen = GraphEntity(id: "person-shiwen", graphID: "default", name: "诗闻", entityKind: .personObject, scope: .personal, canonicalClassID: "person")
    let retrieval = GraphEntity(id: "concept-retrieval", graphID: "default", name: "graph retrieval", entityKind: .concept, scope: .project, canonicalClassID: "concept")
    try store.upsert(entity: shiwen)
    try store.upsert(entity: retrieval)
    try store.upsert(statement: GraphStatement(
        id: "statement-retrieval-preference",
        graphID: "default",
        subjectEntityID: shiwen.id,
        predicate: .prefers,
        objectEntityID: retrieval.id,
        statementText: "诗闻 prefers graph retrieval with clear rerank explanations.",
        validAt: now,
        committedAt: now,
        confidence: 0.95
    ))

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(text: "retrieval", graphID: "default", limit: 10, reranking: GraphRerankingConfig(strategies: [.graphitiLocal, .maximalMarginalRelevance])))
    let hit = try #require(response.hits.first { $0.ownerID == "statement-retrieval-preference" })

    #expect(hit.metadata["matched_terms"]?.contains("retrieval") == true)
    #expect(hit.metadata["rerank_reasons"]?.contains("lexical_overlap") == true)
    #expect(hit.metadata["rerank_reasons"]?.contains("confidence") == true)
    #expect(hit.metadata["retrieval_pipeline"] == "fts+graph_expansion+rrf+local_rerank")
}

@Test func graphRetrievalLexicalOverlapUsesSharedTextFilterLexicon() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryPhase6SearchDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 4_000)
    let person = GraphEntity(id: "person-shiwen", graphID: "default", name: "诗闻", entityKind: .personObject, scope: .personal, canonicalClassID: "person")
    let trip = GraphEntity(id: "trip-jakarta", graphID: "default", name: "雅加达旅行", entityKind: .lifeObject, scope: .personal, canonicalClassID: "trip")
    try store.upsert(entity: person)
    try store.upsert(entity: trip)
    try store.upsert(statement: GraphStatement(
        id: "statement-jakarta-cost",
        graphID: "default",
        subjectEntityID: person.id,
        predicate: .prefers,
        objectEntityID: trip.id,
        statementText: "诗闻关注雅加达旅行费用规划。",
        validAt: now,
        committedAt: now,
        confidence: 0.9
    ))

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(
        text: "去雅加达玩一个星期需要多少钱",
        graphID: "default",
        includeEntities: false,
        includeStatements: false,
        includeEpisodes: false,
        limit: 10,
        centerEntityIDs: [person.id],
        reranking: GraphRerankingConfig(strategies: [.graphitiLocal], graphExpansionDepth: 1)
    ))
    let hit = try #require(response.hits.first { $0.ownerID == "statement-jakarta-cost" })

    #expect(hit.metadata["matched_terms"]?.contains("雅加达") == true)
    #expect(hit.metadata["matched_terms"]?.contains("一个") != true)
    #expect(hit.metadata["matched_terms"]?.contains("星期") != true)
    #expect(hit.metadata["matched_terms"]?.contains("需要") != true)
    #expect(hit.metadata["matched_terms"]?.contains("多少") != true)
    #expect(hit.metadata["rerank_reasons"]?.contains("lexical_overlap") == true)
}

@Test func agentContextRenderedTextIncludesRetrievalReason() throws {
    let context = AgentContext(
        query: "graph retrieval",
        items: [AgentContextItem(
            sourceID: "statement:1",
            kind: .edge,
            content: "Statement[PREFERS] graph retrieval should be explainable",
            reason: "matched via statement_fts_v3+graph_neighborhood_hop1_v2"
        )]
    )

    #expect(context.renderedText.contains("Reason: matched via statement_fts_v3+graph_neighborhood_hop1_v2"))
}
