import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryMemoryOSHealthDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func memoryOSStoreHealthReportCanBePersisted() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSHealthDatabaseURL().path)
    try store.migrate()
    let report = try store.schemaHealthReport(now: Date(timeIntervalSince1970: 1_000))
    let reportJSON = store.json(report)

    try store.execute("""
    INSERT INTO memory_store_health_checks(id, status, checked_at, report_json)
    VALUES ('health-1', '\(report.status.rawValue)', '2026-06-22T03:21:00Z', \(store.quote(reportJSON)))
    """)

    let rows = try store.query(sql: "SELECT id, status FROM memory_store_health_checks WHERE id = 'health-1'")
    #expect(rows == [["health-1", "healthy"]])
}

@Test func clearingMemoryOSRemovesEveryMemoryLayerAndRetainsSchema() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSHealthDatabaseURL().path)
    try store.migrate()
    try store.execute("""
    INSERT INTO memory_l0_provenance_objects
      (id, source_type, title, content, content_hash, occurred_at, ingested_at, confidentiality, status)
      VALUES ('l0', 'manual', 'L0', 'content', 'hash', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 'private', 'active');
    INSERT INTO memory_l1_capture_events
      (id, provenance_object_id, event_type, occurred_at, processing_state)
      VALUES ('l1', 'l0', 'chat', '2026-01-01T00:00:00Z', 'captured');
    INSERT INTO memory_l2_nodes
      (id, stable_key, node_type, name, created_at, updated_at)
      VALUES ('l2', 'test:l2', 'concept', 'L2', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
    INSERT INTO memory_l3_beliefs
      (id, statement, created_at, updated_at)
      VALUES ('l3', 'L3 belief', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
    INSERT INTO memory_l4_entities
      (id, stable_key, entity_type, name, confidence, created_at, updated_at)
      VALUES ('l4', 'test:l4', 'person', 'L4', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
    INSERT INTO memory_store_health_checks
      (id, status, checked_at, report_json)
      VALUES ('health', 'healthy', '2026-01-01T00:00:00Z', '{}');
    """)

    try store.clearAllMemoryData()

    for table in [
        "memory_l0_provenance_objects",
        "memory_l1_capture_events",
        "memory_l2_nodes",
        "memory_l3_beliefs",
        "memory_l4_entities",
        "memory_store_health_checks"
    ] {
        #expect(try store.query(sql: "SELECT COUNT(*) FROM \(table);") == [["0"]])
    }
    #expect(try store.schemaHealthReport().status == .healthy)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_schema_migrations;") == [["1"]])
}
