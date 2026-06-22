import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

private func temporaryAppMemoryOSHardeningDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func appMemoryOSFacadeRecordsRejectedLLMArtifactWithAuditAndMetric() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSHardeningDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 1_000)

    let result = try facade.validateAndRecordLLMArtifact(rawContent: "{not-json", modelID: "test-model", queueItemID: "queue-1", now: now)

    #expect(!result.accepted)
    #expect(result.issues.contains { $0.code == "json_decode_failed" })
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_processing_artifacts;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.llm_artifact.rejected';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_processing_metrics WHERE metric_name = 'memory_os.llm_artifact.accepted';").first?.first == "1")
}

@Test func appMemoryOSFacadeRecordsQueueFailureAndDeadLettersAtMaxAttempts() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSHardeningDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 1_000)
    let item = MemoryOSQueueItem(id: "queue-dead", kind: "extract", status: .processing, attemptCount: 1, maxAttempts: 2, nextRunAt: now, lockedAt: now.addingTimeInterval(-10), lockedBy: "worker", leaseExpiresAt: now.addingTimeInterval(60), idempotencyKey: "queue-dead-key")
    try store.enqueue(item)

    let transitioned = try facade.recordQueueFailure(item, errorCode: "schema_validation_failed", errorMessage: "Missing evidence", now: now)

    #expect(transitioned.status == .deadLetter)
    #expect(transitioned.attemptCount == 2)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_dead_letter_queue WHERE queue_item_id = 'queue-dead';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_queue_attempts WHERE queue_item_id = 'queue-dead';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.queue.failure';").first?.first == "1")
}
