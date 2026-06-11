import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryV3DatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphKernelStoreMigratesV3CoreTables() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryV3DatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("graph_entities"))
    #expect(tables.contains("graph_statements"))
    #expect(tables.contains("graph_episodes_v3"))
    #expect(tables.contains("graph_ontology_classes"))
    #expect(tables.contains("graph_jobs_v3"))
    #expect(tables.contains("graph_extraction_traces"))
    #expect(tables.contains("graph_extraction_trace_payloads"))
    #expect(tables.contains("graph_admission_hold_queue"))
    #expect(tables.contains("graph_anomalies"))
    #expect(tables.contains("graph_memory_change_log"))
    #expect(tables.contains("graph_write_candidates"))
    #expect(tables.contains("agent_sessions"))
    #expect(tables.contains("agent_runs"))
    #expect(tables.contains("agent_events"))
    #expect(tables.contains("agent_audit_events"))
    #expect(tables.contains("agent_pending_approvals"))
    #expect(tables.contains("memory_staging_buffers"))
}

@Test func graphKernelStoreMigratesV3FTSTables() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryV3DatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("graph_entities_fts"))
    #expect(tables.contains("graph_statements_fts"))
    #expect(tables.contains("graph_episodes_fts"))
}

@Test func graphKernelStoreMigratesV3Indexes() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryV3DatabaseURL().path)
    try store.migrate()

    let indexes = try store.indexNames()

    #expect(indexes.contains("idx_graph_entities_kind"))
    #expect(indexes.contains("idx_graph_entities_scope_kind"))
    #expect(indexes.contains("idx_graph_statements_predicate"))
    #expect(indexes.contains("idx_graph_statements_subject"))
    #expect(indexes.contains("idx_graph_statements_object"))
    #expect(indexes.contains("idx_graph_episodes_v3_graph_time"))
    #expect(indexes.contains("idx_graph_jobs_v3_runnable"))
    #expect(indexes.contains("idx_graph_memory_change_log_graph"))
    #expect(indexes.contains("idx_graph_write_candidates_status"))
    #expect(indexes.contains("idx_agent_sessions_updated"))
    #expect(indexes.contains("idx_agent_events_run"))
    #expect(indexes.contains("idx_agent_audit_events_run"))
    #expect(indexes.contains("idx_agent_pending_approvals_run"))
    #expect(indexes.contains("idx_agent_pending_approvals_status"))
}

@Test func graphKernelStoreMigrationIsIdempotentAndPreservesAgentSessionHistory() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryV3DatabaseURL().path)
    try store.migrate()

    var session = AgentSession(id: "session-v3", title: "V3 Migration")
    let user = session.appendUserMessage("Keep this user message")
    let assistant = session.appendAssistantMessage("Keep this assistant message")
    try store.upsertSession(session)

    try store.migrate()
    try store.migrate()

    let loaded = try #require(try store.session(id: session.id))
    #expect(loaded.messages.map(\.id) == [user.id, assistant.id])
    #expect(loaded.messages.map(\.content) == ["Keep this user message", "Keep this assistant message"])
}
