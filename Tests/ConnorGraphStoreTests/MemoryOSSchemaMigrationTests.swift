import Foundation
import Testing
import ConnorGraphStore

private func temporaryMemoryOSSchemaDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func memoryOSSchemaMigrationCreatesAllLayerTables() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSSchemaDatabaseURL().path)
    try store.migrate()
    let tables = try store.tableNames()

    #expect(tables.contains("memory_l0_provenance_objects"))
    #expect(tables.contains("memory_l1_processing_queue"))
    #expect(tables.contains("memory_l2_statements"))
    #expect(tables.contains("memory_l3_beliefs"))
    #expect(tables.contains("memory_l4_entities"))
}

@Test func memoryOSSchemaMigrationCreatesAllFTSTables() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSSchemaDatabaseURL().path)
    try store.migrate()
    let tables = try store.tableNames()

    #expect(tables.contains("memory_l0_provenance_fts"))
    #expect(tables.contains("memory_l2_nodes_fts"))
    #expect(tables.contains("memory_l2_statements_fts"))
    #expect(tables.contains("memory_l3_beliefs_fts"))
    #expect(tables.contains("memory_l4_entities_fts"))
    #expect(tables.contains("memory_l4_statements_fts"))
}

@Test func memoryOSSchemaMigrationDoesNotCreateSemanticGovernanceTables() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSSchemaDatabaseURL().path)
    try store.migrate()
    let tables = try store.tableNames()

    #expect(!tables.contains("memory_l2_conflicts"))
    #expect(!tables.contains("memory_l3_conflicts"))
}

@Test func memoryOSSchemaMigrationUsesTemporalSemanticColumns() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSSchemaDatabaseURL().path)
    try store.migrate()

    let l2Columns = try store.query(sql: "PRAGMA table_info(memory_l2_statements);").map { $0[1] }
    let l3Columns = try store.query(sql: "PRAGMA table_info(memory_l3_beliefs);").map { $0[1] }
    let l4Columns = try store.query(sql: "PRAGMA table_info(memory_l4_entity_statements);").map { $0[1] }

    #expect(l2Columns.contains("assertion_kind"))
    #expect(l2Columns.contains("source_artifact_id"))
    #expect(!l2Columns.contains("status"))
    #expect(!l2Columns.contains("invalid_at"))

    #expect(l3Columns.contains("projection_kind"))
    #expect(l3Columns.contains("valid_at"))
    #expect(l3Columns.contains("projected_at"))
    #expect(!l3Columns.contains("status"))

    #expect(l4Columns.contains("assertion_kind"))
    #expect(l4Columns.contains("source_artifact_id"))
    #expect(!l4Columns.contains("status"))
    #expect(!l4Columns.contains("invalid_at"))
}
