import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryKernelDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphKernelStoreCreatesV3Tables() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryKernelDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("graph_episodes_v3"))
    #expect(tables.contains("graph_entities"))
    #expect(tables.contains("graph_statements"))
    #expect(tables.contains("graph_ontology_classes"))
    #expect(tables.contains("graph_anomalies"))
    #expect(tables.contains("graph_entities_fts"))
    #expect(tables.contains("graph_statements_fts"))
    #expect(tables.contains("graph_episodes_fts"))
}

@Test func graphKernelStoreRoundTripsEntityStatementAndEpisode() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryKernelDatabaseURL().path)
    try store.migrate()
    let occurredAt = Date(timeIntervalSince1970: 2_000)
    let episode = GraphEpisodeV3(
        id: "episode-1",
        graphID: "default",
        sourceType: .chatMessage,
        title: "Preference evidence",
        content: "诗闻 prefers structured plans.",
        sourceDescription: "test",
        occurredAt: occurredAt,
        ingestedAt: occurredAt
    )
    let person = GraphEntity(
        id: "person-shiwen",
        graphID: "default",
        name: "诗闻",
        entityKind: .personObject,
        scope: .personal,
        canonicalClassID: "person",
        aliases: ["Shiwen"]
    )
    let preference = GraphEntity(
        id: "preference-structured-plans",
        graphID: "default",
        name: "structured plans",
        entityKind: .lifeObject,
        scope: .personal,
        canonicalClassID: "preference"
    )
    let statement = GraphStatement(
        id: "statement-prefers",
        graphID: "default",
        subjectEntityID: person.id,
        predicate: .prefers,
        objectEntityID: preference.id,
        statementText: "诗闻 prefers structured plans.",
        validAt: occurredAt,
        committedAt: occurredAt,
        confidence: 0.9,
        justifications: [GraphJustification(type: .userStated, source: episode.id, strength: 1.0, evidenceSpan: episode.content)],
        sourceEpisodeIDs: [episode.id]
    )

    try store.upsert(episode: episode)
    try store.upsert(entity: person)
    try store.upsert(entity: preference)
    try store.upsert(statement: statement)

    #expect(try store.episode(id: episode.id)?.content == episode.content)
    #expect(try store.entity(id: person.id)?.aliases == ["Shiwen"])
    #expect(try store.statement(id: statement.id)?.beliefStatus == .active)
    #expect(try store.searchEntitiesFTS(query: "Shiwen", graphID: "default", limit: 10).map(\.id) == [person.id])
    #expect(try store.searchStatementsFTS(query: "structured", graphID: "default", limit: 10).map(\.id) == [statement.id])
    #expect(try store.searchEpisodesFTS(query: "plans", graphID: "default", limit: 10).map(\.id) == [episode.id])
}

@Test func graphKernelStoreSeedsPersonalKnowledgeAndProjectOntology() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryKernelDatabaseURL().path)
    try store.migrate()
    try store.seedBaseOntology(graphID: "default")

    let classes = try store.ontologyClasses(graphID: "default")
    let classIDs = Set(classes.map(\.classID))

    #expect(classIDs.contains("person"))
    #expect(classIDs.contains("email"))
    #expect(classIDs.contains("calendar_event"))
    #expect(classIDs.contains("preference"))
    #expect(classIDs.contains("task"))
    #expect(classIDs.contains("project"))
    #expect(classIDs.contains("decision"))
    #expect(classIDs.contains("source_document"))
}
