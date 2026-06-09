import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryV2DatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphStoreMigratesGraphitiGradeV2Tables() throws {
    let store = try SQLiteGraphStore(path: temporaryV2DatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("graph_episodes"))
    #expect(tables.contains("graph_nodes_v2"))
    #expect(tables.contains("graph_facts"))
    #expect(tables.contains("graph_mentions"))
    #expect(tables.contains("graph_fact_sources"))
    #expect(tables.contains("graph_generation_runs"))
    #expect(tables.contains("graph_node_candidates"))
    #expect(tables.contains("graph_fact_candidates"))
    #expect(tables.contains("graph_embeddings"))
    #expect(tables.contains("graph_index_tasks"))
    #expect(tables.contains("graph_jobs"))
    #expect(tables.contains("graph_job_events"))
    #expect(tables.contains("graph_cost_budgets"))
}

@Test func graphStoreMigratesGraphitiGradeFTSTables() throws {
    let store = try SQLiteGraphStore(path: temporaryV2DatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("graph_nodes_fts"))
    #expect(tables.contains("graph_facts_fts"))
    #expect(tables.contains("graph_episodes_fts"))
}

@Test func graphStoreMigratesGraphitiGradeIndexes() throws {
    let store = try SQLiteGraphStore(path: temporaryV2DatabaseURL().path)
    try store.migrate()

    let indexes = try store.indexNames()

    #expect(indexes.contains("idx_graph_episodes_group_time"))
    #expect(indexes.contains("idx_graph_episodes_source"))
    #expect(indexes.contains("idx_graph_nodes_v2_stable_key"))
    #expect(indexes.contains("idx_graph_nodes_v2_type"))
    #expect(indexes.contains("idx_graph_facts_source"))
    #expect(indexes.contains("idx_graph_facts_target"))
    #expect(indexes.contains("idx_graph_facts_temporal"))
    #expect(indexes.contains("idx_graph_embeddings_owner"))
    #expect(indexes.contains("idx_graph_jobs_runnable"))
}

@Test func graphStoreV2MigrationIsIdempotentAndPreservesChatHistory() throws {
    let store = try SQLiteGraphStore(path: temporaryV2DatabaseURL().path)
    try store.migrate()

    var session = AgentSession(id: "session-v2", title: "V2 Migration")
    let user = session.appendUserMessage("Keep this user message")
    let assistant = session.appendAssistantMessage("Keep this assistant message")
    try store.upsert(chatSession: session)
    try store.append(chatMessage: user, sessionID: session.id)
    try store.append(chatMessage: assistant, sessionID: session.id)

    try store.migrate()
    try store.migrate()

    let loaded = try #require(try store.chatSession(id: session.id))
    #expect(loaded.messages.map(\.id) == [user.id, assistant.id])
    #expect(loaded.messages.map(\.content) == ["Keep this user message", "Keep this assistant message"])
}
