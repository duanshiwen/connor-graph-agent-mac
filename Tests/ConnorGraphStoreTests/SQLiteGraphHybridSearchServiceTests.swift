import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphSearch
import ConnorGraphStore

private func temporaryHybridSearchDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func hybridSearchFusesFTSNeighborhoodAndSourceEpisodes() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryHybridSearchDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let episode = GraphEpisodeV3(
        id: "episode-structured-plans",
        graphID: "default",
        sourceType: .chatMessage,
        title: "Structured planning evidence",
        content: "诗闻 prefers structured plans before implementation.",
        sourceDescription: "test chat",
        occurredAt: now,
        ingestedAt: now
    )
    let person = GraphEntity(
        id: "person-shiwen",
        graphID: "default",
        name: "诗闻",
        entityKind: .personObject,
        scope: .personal,
        canonicalClassID: "person"
    )
    let preference = GraphEntity(
        id: "pref-structured-plans",
        graphID: "default",
        name: "structured plans",
        entityKind: .lifeObject,
        scope: .personal,
        canonicalClassID: "preference"
    )
    let statement = GraphStatement(
        id: "statement-structured-plans",
        graphID: "default",
        subjectEntityID: person.id,
        predicate: .prefers,
        objectEntityID: preference.id,
        statementText: "诗闻 prefers structured plans.",
        validAt: now,
        committedAt: now,
        confidence: 0.9,
        sourceEpisodeIDs: [episode.id]
    )

    try store.upsert(episode: episode)
    try store.upsert(entity: person)
    try store.upsert(entity: preference)
    try store.upsert(statement: statement)

    let service = SQLiteGraphHybridSearchService(store: store)
    let response = try await service.search(query: GraphSearchQuery(text: "structured", graphID: "default", limit: 10))

    let hitsByID = Dictionary(uniqueKeysWithValues: response.hits.map { ($0.id, $0) })
    let statementHit = try #require(hitsByID["statement:\(statement.id)"])
    let episodeHit = try #require(hitsByID["episode:\(episode.id)"])

    #expect(statementHit.retrievalMethod.contains("statement_fts_v3"))
    #expect(statementHit.retrievalMethod.contains("graph_neighborhood_hop1_v2"))
    #expect(statementHit.metadata["fusion_methods"]?.contains("graph_neighborhood_hop1_v2") == true)
    #expect(episodeHit.retrievalMethod.contains("episode_fts_v3") || episodeHit.retrievalMethod.contains("source_episode_expansion_v1"))
}
