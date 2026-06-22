import Foundation
import Testing
import ConnorGraphStore

private func temporaryMemoryOSImportDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func sqliteMemoryOSSchemaIncludesLegacyImportRunLedger() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSImportDatabaseURL().path)
    try store.migrate()

    try store.execute("""
    INSERT INTO memory_legacy_import_runs(id, status, dry_run, started_at, metadata_json)
    VALUES ('import-1', 'succeeded', 1, '2026-06-22T03:21:00Z', '{}')
    """)

    let rows = try store.query(sql: "SELECT id, status, dry_run FROM memory_legacy_import_runs WHERE id = 'import-1'")

    #expect(rows.first == ["import-1", "succeeded", "1"])
}
