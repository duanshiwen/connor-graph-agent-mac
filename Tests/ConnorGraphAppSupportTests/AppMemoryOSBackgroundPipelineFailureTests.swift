import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func l1UnifiedProjectionBackgroundJobRetriesWhenModelExecutorThrowsAndKeepsL1Buffer() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundFailureDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 9_000)
    _ = try facade.ingestChatMessage(messageID: "message-1", sessionID: "session", role: "user", content: "Important memory.", occurredAt: now)
    _ = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1), now: now)

    let summaries = try facade.runBackgroundAIQueueOnce(executor: ThrowingMemoryOSBackgroundExecutor(), now: now)

    #expect(summaries.count == 1)
    #expect(!summaries[0].accepted)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "1")
    let queued = try store.query(sql: "SELECT status, attempt_count FROM memory_l1_processing_queue WHERE kind = '\(MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue)';")
    #expect(queued.first?[0] == MemoryOSQueueStatus.retryScheduled.rawValue)
    #expect(queued.first?[1] == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_queue_attempts;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.background_job.model_failed';").first?.first == "1")
}

@Test func l1BackgroundJobKeepsRetryingAfterLegacyMaxAttemptsAndKeepsL1Buffer() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundFailureDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 9_000)
    _ = try facade.ingestChatMessage(messageID: "message-1", sessionID: "session", role: "user", content: "Important memory.", occurredAt: now)
    let enqueued = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1), now: now)
    var item = try #require(enqueued.first)
    item.maxAttempts = 1
    try store.enqueue(item)

    _ = try facade.runBackgroundAIQueueOnce(executor: ThrowingMemoryOSBackgroundExecutor(), now: now)

    #expect(try store.queueItem(id: item.id)?.status == .retryScheduled)
    #expect(try store.queueItem(id: item.id)?.maxAttempts == .max)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_dead_letter_queue;").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.background_job.dead_lettered';").first?.first == "0")
}

private struct ThrowingMemoryOSBackgroundExecutor: MemoryOSBackgroundModelExecutor {
    func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse {
        throw NSError(domain: "memory-worker", code: 42, userInfo: [NSLocalizedDescriptionKey: "model unavailable"])
    }
}

private struct StaticRejectedMemoryOSBackgroundExecutor: MemoryOSBackgroundModelExecutor {
    func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse {
        MemoryOSBackgroundModelResponse(rawArtifactJSON: "{\"knowledgeCandidates\":[{\"id\":\"bad\",\"title\":\"Bad\",\"claim\":\"No evidence\",\"category\":\"general\",\"knowledgeType\":\"theory\",\"scope\":\"general\",\"domain\":\"general\",\"signalAssessment\":{\"signalQualityAccepted\":true,\"reuseScopeAccepted\":true,\"noveltyAccepted\":true,\"structurabilityAccepted\":true},\"confidence\":0.8,\"evidenceStatementIDs\":[],\"relatedEntityNames\":[]}],\"conceptEntities\":[],\"conceptRelations\":[]}")
    }
}

private func temporaryAppMemoryOSBackgroundFailureDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-background-failure-\(UUID().uuidString).sqlite")
}
