import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

private func temporaryAppMemoryOSOrphanDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-orphan-\(UUID().uuidString).sqlite")
}

private func ingestOrphanScenarioMessages(_ facade: AppMemoryOSFacade, count: Int, prefix: String, now: Date) throws {
    for index in 0..<count {
        _ = try facade.ingestChatMessage(
            messageID: "\(prefix)-message-\(index)",
            sessionID: "session",
            role: "user",
            content: "Orphan scenario event \(prefix) \(index) content.",
            occurredAt: now.addingTimeInterval(Double(index))
        )
    }
}

/// Mirror the production cloud-sync tombstone path (AppAccountDataSyncCoordinator): delete the
/// L0 provenance object with foreign keys disabled so the L1 capture event survives as an orphan.
private func deleteProvenanceObjectAsSyncTombstone(_ store: SQLiteMemoryOSStore, id: String) throws {
    try store.withForeignKeysDisabled {
        try store.deleteProvenanceObject(id: id)
    }
}

private func deleteAllProvenanceObjectsAsSyncTombstones(_ store: SQLiteMemoryOSStore, keeping intactProvenanceID: String? = nil) throws {
    try store.withForeignKeysDisabled {
        let ids = try store.query(sql: "SELECT id FROM memory_l0_provenance_objects;").compactMap(\.first)
        for id in ids where id != intactProvenanceID {
            try store.deleteProvenanceObject(id: id)
        }
    }
}

@Test func enqueueL1UnifiedProjectionSkipsOrphanEventsInsteadOfThrowing() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSOrphanDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 10_000)
    try ingestOrphanScenarioMessages(facade, count: 3, prefix: "skip", now: now)

    // Simulate a cloud-sync tombstone: L0 is gone but the L1 capture event survives.
    let orphanProvenanceID = try #require(store.query(sql: "SELECT provenance_object_id FROM memory_l1_capture_events ORDER BY occurred_at ASC LIMIT 1;").first?.first)
    try deleteProvenanceObjectAsSyncTombstone(store, id: orphanProvenanceID)

    let enqueued = try facade.enqueueL1UnifiedProjectionBackgroundJobs(
        policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10),
        now: now
    )

    #expect(enqueued.count == 1)
    let draft = try store.decode(MemoryOSL1UnifiedProjectionJobDraft.self, enqueued[0].payloadJSON)
    #expect(draft.captureEventIDs.count == 2)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "2")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.l1.orphan_provenance.purged';").first?.first == "1")
}

@Test func replanDownscaledBackgroundJobPurgesOrphanAndReschedulesRemaining() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSOrphanDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 11_000)
    try ingestOrphanScenarioMessages(facade, count: 10, prefix: "replan", now: now)
    let enqueued = try facade.enqueueL1UnifiedProjectionBackgroundJobs(
        policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10),
        now: now
    )
    let item = try #require(enqueued.first)
    let draft = try store.decode(MemoryOSL1UnifiedProjectionJobDraft.self, item.payloadJSON)
    let orphanProvenanceID = try #require(draft.provenanceObjectIDs.first)
    try deleteProvenanceObjectAsSyncTombstone(store, id: orphanProvenanceID)

    let summary = try facade.replanDownscaledBackgroundJob(
        item,
        errorCode: "background_ai_token_budget_exceeded",
        errorMessage: "exceededTokenBudget: 2000000",
        now: now
    )

    #expect(summary.issues.first?.code == "background_ai_batch_downscaled")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "9")
    let queueItems = try store.queueItems(kinds: [item.kind]).filter { $0.status == .pending }
    let subDrafts = try queueItems.map { try store.decode(MemoryOSL1UnifiedProjectionJobDraft.self, $0.payloadJSON) }
    #expect(subDrafts.map(\.captureEventIDs.count).sorted() == [4, 5])
    #expect(Set(subDrafts.flatMap(\.captureEventIDs)).count == 9)
}

@Test func replanDownscaledBackgroundJobCancelsJobWhenAllEventsLostProvenance() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSOrphanDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 12_000)
    try ingestOrphanScenarioMessages(facade, count: 3, prefix: "all-orphan", now: now)
    let enqueued = try facade.enqueueL1UnifiedProjectionBackgroundJobs(
        policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10),
        now: now
    )
    let item = try #require(enqueued.first)
    try deleteAllProvenanceObjectsAsSyncTombstones(store)

    let summary = try facade.replanDownscaledBackgroundJob(
        item,
        errorCode: "background_ai_token_budget_exceeded",
        errorMessage: "exceededTokenBudget",
        now: now
    )

    #expect(summary.issues.first?.code == "background_ai_l0_provenance_missing")
    #expect(try store.queueItem(id: item.id)?.status == .cancelled)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_dead_letter_queue;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.background_job.l0_provenance_missing';").first?.first == "1")
}

@Test func sweepOrphanL1CaptureEventsPurgesDanglingPendingEvents() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSOrphanDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 13_000)
    try ingestOrphanScenarioMessages(facade, count: 4, prefix: "sweep", now: now)
    let intactProvenanceID = try #require(store.query(sql: "SELECT provenance_object_id FROM memory_l1_capture_events ORDER BY occurred_at ASC LIMIT 1;").first?.first)
    try deleteAllProvenanceObjectsAsSyncTombstones(store, keeping: intactProvenanceID)

    let purged = try facade.sweepOrphanL1CaptureEvents(now: now)

    #expect(purged == 3)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.l1.orphan_provenance.purged';").first?.first == "1")
}

@Test func runDailySweepPurgesOrphansEvenWhenEnqueueWouldNotTrigger() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSOrphanDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store, canRunL1Extraction: { _ in true })
    let now = Date(timeIntervalSince1970: 14_000)
    try ingestOrphanScenarioMessages(facade, count: 5, prefix: "sweep-daily", now: now)
    try deleteAllProvenanceObjectsAsSyncTombstones(store)

    // Default l1AgePolicy has minPendingCount = 1_000_000, so enqueue stays empty — but the
    // orphan GC must still purge dangling events before the eligibility guard.
    let enqueued = try AppMemoryOSPipelineTriggerCoordinator(facade: facade).runDailySweep(now: now)

    #expect(enqueued.isEmpty)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.l1.orphan_provenance.purged';").first?.first == "1")
}
