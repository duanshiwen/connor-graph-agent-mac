import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryMemoryOSOperationsDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func memoryOSStorePersistsProductionArtifactsAuditMetricsAndHealth() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSOperationsDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)

    let artifact = MemoryOSLLMArtifactEnvelope(
        id: "artifact-1",
        queueItemID: "queue-1",
        processingRunID: "run-1",
        artifactType: "graph_structured_extraction",
        schemaName: "GraphStructuredExtractionOutput",
        modelID: "test-model",
        rawContent: "{}",
        contentHash: "hash",
        createdAt: now
    )
    try store.save(artifact: artifact)
    try store.save(audit: MemoryOSAuditEvent(id: "audit-1", eventType: "memory_os.llm_artifact.accepted", subjectID: artifact.id, payload: ["accepted": "true"], createdAt: now))
    try store.save(metric: MemoryOSProcessingMetric(id: "metric-1", name: "memory_os.llm_artifact.accepted", value: 1, createdAt: now))
    try store.saveHealthReport(MemoryOSStoreHealthReport(expectedVersion: 1, actualVersion: 1, status: .healthy, checkedAt: now))

    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_processing_artifacts WHERE id = 'artifact-1';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE id = 'audit-1';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_processing_metrics WHERE id = 'metric-1';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_store_health_checks WHERE status = 'healthy';").first?.first == "1")
}

@Test func memoryOSStoreReportsQueueSnapshotAndPersistsDeadLetter() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSOperationsDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let expired = now.addingTimeInterval(-60)

    try store.enqueue(MemoryOSQueueItem(id: "pending", kind: "extract", status: .pending, nextRunAt: now, idempotencyKey: "pending-key"))
    try store.enqueue(MemoryOSQueueItem(id: "leased", kind: "extract", status: .leased, nextRunAt: now, lockedAt: expired, lockedBy: "worker", leaseExpiresAt: expired, idempotencyKey: "leased-key"))
    let dead = MemoryOSQueueItem(id: "dead", kind: "extract", status: .deadLetter, payloadJSON: "{\"x\":1}", attemptCount: 3, maxAttempts: 3, nextRunAt: now, idempotencyKey: "dead-key", errorCode: "schema_error", errorMessage: "Invalid")
    try store.enqueue(dead)
    try store.saveDeadLetter(queueItem: dead, now: now)

    let snapshot = try store.queueOperationalSnapshot(now: now)

    #expect(snapshot.pending == 1)
    #expect(snapshot.leased == 1)
    #expect(snapshot.deadLetter == 1)
    #expect(snapshot.expiredLeases == 1)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_dead_letter_queue WHERE queue_item_id = 'dead';").first?.first == "1")
}
