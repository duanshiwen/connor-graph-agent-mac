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
