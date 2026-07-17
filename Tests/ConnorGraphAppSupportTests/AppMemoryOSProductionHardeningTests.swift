import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphMemory
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

@Test func permanentLLMBillingFailureDeadLettersImmediately() throws {
    let classification = MemoryOSBackgroundFailureClassifier().classify(
        NSError(domain: "provider", code: 402, userInfo: [NSLocalizedDescriptionKey: "insufficient_quota: credit balance exhausted"])
    )

    #expect(classification.errorCode == "llm_billing_or_quota_exhausted")
    #expect(!classification.retryable)
    #expect(classification.requiresUserAction)
}

@Test func networkFailureUsesARecoverableDelay() throws {
    let classification = MemoryOSBackgroundFailureClassifier().classify(URLError(.networkConnectionLost))

    #expect(classification.errorCode == "llm_network_unavailable")
    #expect(classification.retryable)
    #expect(classification.retryDelay == 30)
}

@Test func l1UserActionFailureStillRetriesInsteadOfDeadLettering() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSHardeningDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 1_500)
    let item = MemoryOSQueueItem(
        id: "l1-billing-retry",
        kind: MemoryOSBackgroundJobKind.l1UnifiedProjection.rawValue,
        status: .processing,
        attemptCount: 2,
        maxAttempts: 3,
        nextRunAt: now,
        idempotencyKey: "l1-billing-retry"
    )
    try store.enqueue(item)

    let transitioned = try facade.recordQueueFailure(
        item,
        errorCode: "llm_billing_or_quota_exhausted",
        errorMessage: "Credit balance exhausted",
        now: now,
        retryable: false
    )

    #expect(transitioned.status == .retryScheduled)
    #expect(transitioned.maxAttempts == .max)
    #expect(transitioned.nextRunAt == now.addingTimeInterval(3_600))
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_dead_letter_queue;").first?.first == "0")
}

@Test func appMemoryOSFacadeRecoversExpiredLeaseWithoutDeletingL1() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSHardeningDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 2_000)
    _ = try facade.ingestChatMessage(messageID: "lease-message", sessionID: "session", role: "user", content: "Keep this L1 event.", occurredAt: now)
    let jobs = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1), now: now)
    var item = try #require(jobs.first)
    item.status = .processing
    item.lockedBy = "stopped-worker"
    item.lockedAt = now.addingTimeInterval(-600)
    item.leaseExpiresAt = now.addingTimeInterval(-300)
    try store.enqueue(item)

    let recovered = try facade.recoverExpiredBackgroundQueueLeases(now: now)

    #expect(recovered == 1)
    #expect(try store.queueItem(id: item.id)?.status == .retryScheduled)
    #expect(try store.queueItem(id: item.id)?.nextRunAt == now)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.background_job.expired_lease_recovered';").first?.first == "1")
}

@Test func appMemoryOSFacadeRevivesLegacyL1DeadLetter() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSHardeningDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 2_500)
    let item = MemoryOSQueueItem(
        id: "legacy-l1-dead-letter",
        kind: MemoryOSBackgroundJobKind.l1UnifiedProjection.rawValue,
        status: .deadLetter,
        attemptCount: 3,
        maxAttempts: 3,
        nextRunAt: now.addingTimeInterval(-60),
        idempotencyKey: "legacy-l1-dead-letter",
        errorCode: "llm_billing_or_quota_exhausted",
        errorMessage: "Old failure"
    )
    try store.enqueue(item)
    try store.saveDeadLetter(queueItem: item, now: now.addingTimeInterval(-60))

    let recovered = try facade.recoverExpiredBackgroundQueueLeases(now: now)

    #expect(recovered == 1)
    #expect(try store.queueItem(id: item.id)?.status == .retryScheduled)
    #expect(try store.queueItem(id: item.id)?.maxAttempts == .max)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_dead_letter_queue;").first?.first == "0")
}

@Test func appMemoryOSRunnerReportsPendingJobsWhenLLMUnavailable() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSHardeningDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 3_000)
    try store.enqueue(MemoryOSQueueItem(
        id: "waiting-for-llm",
        kind: MemoryOSBackgroundJobKind.l1UnifiedProjection.rawValue,
        nextRunAt: now,
        idempotencyKey: "waiting-for-llm"
    ))

    let summary = try AppMemoryOSBackgroundJobRunner(aiExecutorProvider: nil).runOnce(
        facade: AppMemoryOSFacade(store: store),
        now: now
    )

    #expect(summary.attentionMessage?.contains("没有可用的 LLM 连接") == true)
    #expect(try store.queueItem(id: "waiting-for-llm")?.status == .pending)
}
