import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphStore

@Test func memoryOSLegacyDeletionGateRoutesGraphMemoryToMemoryOS() throws {
    let route = ConnorNativeShellRouteResolver().route(for: .graphMemory)
    #expect(route.legacySidebarID == "memoryOS")
}

@Test func memoryOSLegacyDeletionGateUsesDedicatedMemoryOSDatabasePath() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)

    #expect(paths.memoryOSDatabaseURL.lastPathComponent == "memory-os.sqlite")
    #expect(paths.memoryOSDatabaseURL.deletingLastPathComponent().lastPathComponent == "graph")
}

@Test func memoryOSLegacyDeletionGateFreshStoreDoesNotCreateOldWorkflowTables() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    let store = try SQLiteMemoryOSStore(path: url.path)
    try store.migrate()

    let tables = try store.tableNames()
    let forbiddenTables: Set<String> = [
        "memory_staging_buffers",
        "graph_extraction_traces",
        "graph_extraction_trace_payloads",
        "graph_admission_hold_queue",
        "graph_memory_change_log",
        "graph_write_candidates"
    ]

    #expect(tables.intersection(forbiddenTables).isEmpty)
}

@Test func memoryOSLegacyDeletionGateFacadeIsOperationalEntrypoint() throws {
    let store = try SQLiteMemoryOSStore(path: ":memory:")
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)

    let summary = try facade.operationalSummary()

    #expect(summary.l0ProvenanceObjectCount == 0)
    #expect(summary.l1PendingCaptureCount == 0)
    #expect(summary.healthReport.status == .healthy)
}
