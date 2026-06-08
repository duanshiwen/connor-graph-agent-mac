import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

private func temporaryDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func schemaMigratorCreatesRequiredTables() throws {
    let store = try SQLiteGraphStore(path: temporaryDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("schema_migrations"))
    #expect(tables.contains("graph_nodes"))
    #expect(tables.contains("semantic_edges"))
    #expect(tables.contains("observe_log_entries"))
}

@Test func graphStoreSavesAndLoadsGraphNode() throws {
    let store = try SQLiteGraphStore(path: temporaryDatabaseURL().path)
    try store.migrate()
    let node = GraphNode.workObject(id: "work-object-agent-os", title: "Agent OS", summary: "Graph-backed agent OS")

    try store.upsert(node: node)
    let loadedNode = try store.node(id: node.id)
    let loaded = try #require(loadedNode)

    #expect(loaded.id == node.id)
    #expect(loaded.type == .workObject)
    #expect(loaded.title == "Agent OS")
    #expect(loaded.summary == "Graph-backed agent OS")
}

@Test func graphStoreSavesAndLoadsSemanticEdge() throws {
    let store = try SQLiteGraphStore(path: temporaryDatabaseURL().path)
    try store.migrate()
    let edge = SemanticEdge(
        id: "edge-q-a",
        sourceNodeID: "question-1",
        targetNodeID: "answer-1",
        relation: .answeredBy,
        fact: "Question is answered by answer"
    )

    try store.upsert(edge: edge)
    let loadedEdge = try store.edge(id: edge.id)
    let loaded = try #require(loadedEdge)

    #expect(loaded.id == edge.id)
    #expect(loaded.sourceNodeID == "question-1")
    #expect(loaded.targetNodeID == "answer-1")
    #expect(loaded.relation == .answeredBy)
    #expect(loaded.fact == "Question is answered by answer")
}

@Test func graphStoreSavesAndQueriesObserveLogEntries() throws {
    let store = try SQLiteGraphStore(path: temporaryDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let entry = ObserveLogEntry(
        id: "obs-1",
        timestamp: now,
        kind: .candidateFact,
        source: .agent,
        content: "Agent OS uses graph-backed memory.",
        workObjectID: "work-object-agent-os"
    )

    try store.upsert(observeLogEntry: entry)
    let loadedEntry = try store.observeLogEntry(id: entry.id)
    let loaded = try #require(loadedEntry)
    let active = try store.observeLogEntries(status: .active, limit: 10)

    #expect(loaded.id == entry.id)
    #expect(loaded.kind == .candidateFact)
    #expect(loaded.workObjectID == "work-object-agent-os")
    #expect(active.map(\.id).contains(entry.id))
}

@Test func graphStoreQueriesNeighborhoodEdges() throws {
    let store = try SQLiteGraphStore(path: temporaryDatabaseURL().path)
    try store.migrate()
    let q = GraphNode.question(id: "question-1", title: "How should memory work?")
    let a = GraphNode.answer(id: "answer-1", title: "Use graph-backed memory")
    let edge = SemanticEdge.answeredBy(questionID: q.id, answerID: a.id)

    try store.upsert(node: q)
    try store.upsert(node: a)
    try store.upsert(edge: edge)

    let questionEdges = try store.neighborhoodEdges(nodeID: q.id)
    let answerEdges = try store.neighborhoodEdges(nodeID: a.id)

    #expect(questionEdges.map(\.id) == [edge.id])
    #expect(answerEdges.map(\.id) == [edge.id])
}
