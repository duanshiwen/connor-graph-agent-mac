import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

private func temporaryDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func schemaMigratorCreatesRequiredTemporalGraphTables() throws {
    let store = try SQLiteGraphStore(path: temporaryDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("schema_migrations"))
    #expect(tables.contains("graph_episodes"))
    #expect(tables.contains("graph_nodes_v2"))
    #expect(tables.contains("graph_facts"))
    #expect(tables.contains("observe_log_entries"))
    #expect(tables.contains("chat_sessions"))
    #expect(tables.contains("chat_messages"))
}

@Test func graphStoreSavesAndLoadsGraphNodeV2() throws {
    let store = try SQLiteGraphStore(path: temporaryDatabaseURL().path)
    try store.migrate()
    let node = GraphNodeV2(
        id: "work-object-agent-os",
        groupID: "default",
        stableKey: "work_object:agent-os",
        type: .workObject,
        canonicalName: "Agent OS",
        title: "Agent OS",
        summary: "Graph-backed agent OS"
    )

    try store.upsert(nodeV2: node)
    let loadedNode = try store.graphNodeV2(id: node.id)
    let loaded = try #require(loadedNode)

    #expect(loaded.id == node.id)
    #expect(loaded.type == .workObject)
    #expect(loaded.title == "Agent OS")
    #expect(loaded.summary == "Graph-backed agent OS")
}

@Test func graphStoreSavesAndLoadsGraphFact() throws {
    let store = try SQLiteGraphStore(path: temporaryDatabaseURL().path)
    try store.migrate()
    let source = GraphNodeV2(id: "question-1", groupID: "default", type: .question, canonicalName: "Question", title: "Question")
    let target = GraphNodeV2(id: "answer-1", groupID: "default", type: .answer, canonicalName: "Answer", title: "Answer")
    let fact = GraphFact(
        id: "fact-q-a",
        groupID: "default",
        sourceNodeID: source.id,
        targetNodeID: target.id,
        relation: .answeredBy,
        fact: "Question is answered by answer"
    )

    try store.upsert(nodeV2: source)
    try store.upsert(nodeV2: target)
    try store.upsert(fact: fact)
    let loadedFact = try store.graphFact(id: fact.id)
    let loaded = try #require(loadedFact)

    #expect(loaded.id == fact.id)
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

@Test func graphStoreQueriesAdjacentFacts() throws {
    let store = try SQLiteGraphStore(path: temporaryDatabaseURL().path)
    try store.migrate()
    let q = GraphNodeV2(id: "question-1", groupID: "default", type: .question, canonicalName: "How should memory work?", title: "How should memory work?")
    let a = GraphNodeV2(id: "answer-1", groupID: "default", type: .answer, canonicalName: "Use graph-backed memory", title: "Use graph-backed memory")
    let fact = GraphFact(id: "fact-q-a", groupID: "default", sourceNodeID: q.id, targetNodeID: a.id, relation: .answeredBy, fact: "question-1 is answered by answer-1")

    try store.upsert(nodeV2: q)
    try store.upsert(nodeV2: a)
    try store.upsert(fact: fact)

    let questionFacts = try store.adjacentFacts(nodeID: q.id, groupID: "default")
    let answerFacts = try store.adjacentFacts(nodeID: a.id, groupID: "default")

    #expect(questionFacts.map(\.id) == [fact.id])
    #expect(answerFacts.map(\.id) == [fact.id])
}
