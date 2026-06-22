import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func memoryOSStorePersistsL2StatementProcessingState() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSL2ProcessingStateDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 5_000)
    let state = MemoryOSL2StatementProcessingState(
        statementID: "statement-1",
        processingKind: .knowledgeSynthesis,
        status: .pending,
        sourceArtifactID: "artifact-1",
        processedByArtifactID: nil,
        lastAttemptAt: now,
        metadata: ["block": "block-1"]
    )

    try store.upsert(l2ProcessingState: state)
    let loaded = try store.l2ProcessingStates(processingKind: .knowledgeSynthesis, status: .pending, limit: 10)

    #expect(loaded == [state])
}

@Test func memoryOSStoreSchemaIncludesL2ProcessingStateTable() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSL2ProcessingStateDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("memory_l2_statement_processing_state"))
}

private func temporaryMemoryOSL2ProcessingStateDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-l2-processing-state-\(UUID().uuidString).sqlite")
}
