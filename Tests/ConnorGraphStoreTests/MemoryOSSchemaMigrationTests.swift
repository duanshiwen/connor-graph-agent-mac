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
