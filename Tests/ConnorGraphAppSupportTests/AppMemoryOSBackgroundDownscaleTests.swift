import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

private func temporaryAppMemoryOSDownscaleDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-downscale-\(UUID().uuidString).sqlite")
}

@Test func replanDownscaledBackgroundJobSplitsBatchInHalfAndReenqueues() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSDownscaleDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 5_000)
    for index in 0..<10 {
        _ = try facade.ingestChatMessage(
            messageID: "downscale-message-\(index)",
            sessionID: "session",
            role: "user",
            content: "Event \(index) content that needs extraction.",
            occurredAt: now.addingTimeInterval(Double(index))
        )
    }
    let enqueued = try facade.enqueueL1UnifiedProjectionBackgroundJobs(
        policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10),
        now: now
    )
    let item = try #require(enqueued.first)

    let summary = try facade.replanDownscaledBackgroundJob(
        item,
        errorCode: "background_ai_token_budget_exceeded",
        errorMessage: "exceededTokenBudget: 2000000",
        now: now
    )

    #expect(summary.issues.first?.code == "background_ai_batch_downscaled")
    let queueItems = try store.queueItems(kinds: [item.kind])
    #expect(queueItems.count == 2)
    #expect(queueItems.allSatisfy { $0.status == .pending })
    #expect(queueItems.contains { $0.id == item.id })
    let drafts = try queueItems.map { try store.decode(MemoryOSL1UnifiedProjectionJobDraft.self, $0.payloadJSON) }
    #expect(drafts.map(\.captureEventIDs.count) == [5, 5])
    #expect(Set(drafts.flatMap(\.captureEventIDs)).count == 10)
    #expect(drafts.allSatisfy { $0.metadata["downscale_level"] == "1" })
    #expect(drafts.allSatisfy { $0.metadata["parent_queue_item_id"] == item.id })
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.background_job.downscaled';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "10")
}

@Test func replanDownscaledSingleEventIsolatesEventAndCancelsJob() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSDownscaleDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 6_000)
    _ = try facade.ingestChatMessage(
        messageID: "isolate-message",
        sessionID: "session",
        role: "user",
        content: "Single poison event content.",
        occurredAt: now
    )
    let enqueued = try facade.enqueueL1UnifiedProjectionBackgroundJobs(
        policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10),
        now: now
    )
    let item = try #require(enqueued.first)

    let summary = try facade.replanDownscaledBackgroundJob(
        item,
        errorCode: "background_ai_context_length_exceeded",
        errorMessage: "Prompt is too long even for a single event.",
        now: now
    )

    #expect(summary.issues.first?.code == "background_ai_single_event_isolated")
    #expect(try store.queueItem(id: item.id)?.status == .cancelled)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_dead_letter_queue;").first?.first == "1")
    #expect(try store.query(sql: "SELECT processing_state FROM memory_l1_capture_events;").first?.first == MemoryOSQueueStatus.deadLetter.rawValue)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.background_job.single_event_isolated';").first?.first == "1")
}

@Test func recordQueueFailureWithPauseStrategyProbesOnLongInterval() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSDownscaleDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 7_000)
    let item = MemoryOSQueueItem(
        id: "paused-job",
        kind: MemoryOSBackgroundJobKind.l1UnifiedProjection.rawValue,
        status: .processing,
        attemptCount: 1,
        maxAttempts: 3,
        nextRunAt: now,
        idempotencyKey: "paused-job"
    )
    try store.enqueue(item)

    let transitioned = try facade.recordQueueFailure(
        item,
        errorCode: "llm_billing_or_quota_exhausted",
        errorMessage: "insufficient_quota",
        now: now,
        retryable: false,
        strategy: .pause
    )

    #expect(transitioned.status == .retryScheduled)
    #expect(transitioned.maxAttempts == .max)
    #expect(transitioned.nextRunAt == now.addingTimeInterval(MemoryOSBackgroundFailureClassifier.pauseProbeInterval))
}

@Test func resumePausedBackgroundJobsBringsUserActionBatchesBack() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSDownscaleDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 8_000)
    let paused = MemoryOSQueueItem(
        id: "resume-paused",
        kind: MemoryOSBackgroundJobKind.l1UnifiedProjection.rawValue,
        status: .retryScheduled,
        attemptCount: 2,
        maxAttempts: .max,
        nextRunAt: now.addingTimeInterval(86_400),
        idempotencyKey: "resume-paused",
        errorCode: "llm_authentication_required",
        errorMessage: "unauthorized"
    )
    try store.enqueue(paused)
    let transient = MemoryOSQueueItem(
        id: "resume-transient",
        kind: MemoryOSBackgroundJobKind.l1UnifiedProjection.rawValue,
        status: .retryScheduled,
        attemptCount: 1,
        maxAttempts: .max,
        nextRunAt: now.addingTimeInterval(300),
        idempotencyKey: "resume-transient",
        errorCode: "llm_network_unavailable",
        errorMessage: "network"
    )
    try store.enqueue(transient)

    let resumed = try facade.resumePausedBackgroundJobs(now: now)

    #expect(resumed == 1)
    #expect(try store.queueItem(id: paused.id)?.nextRunAt == now)
    #expect(try store.queueItem(id: transient.id)?.nextRunAt == now.addingTimeInterval(300))
}

@Test func toolArgumentValidationReturnsErrorResultInsteadOfThrowing() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSDownscaleDatabaseURL().path)
    try store.migrate()
    let executor = MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store))
    let context = MemoryOSBackgroundToolExecutionContext(runID: "run", iteration: 1)

    let invalid = try executor.execute(
        MemoryOSBackgroundToolCall(id: "call-1", name: "memory_os_recent_context", argumentsJSON: #"{"unsupported":true}"#),
        context: context
    )
    #expect(invalid.error != nil)
    #expect(invalid.error?.contains("invalidArguments") == true)
    #expect(invalid.error?.contains("unsupported") == true)

    let disallowed = try executor.execute(
        MemoryOSBackgroundToolCall(id: "call-2", name: "not_allowed_tool", argumentsJSON: #"{}"#),
        context: context
    )
    #expect(disallowed.error != nil)
    #expect(disallowed.error?.contains("toolNotAllowed") == true)
}
