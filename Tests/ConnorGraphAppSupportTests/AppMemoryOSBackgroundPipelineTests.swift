import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func appMemoryOSFacadeEnqueuesL1UnifiedProjectionBackgroundJobsFromPendingCaptures() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundPipelineDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 6_000)
    for index in 0..<3 {
        _ = try facade.ingestChatMessage(messageID: "message-\(index)", sessionID: "session", role: "user", content: "Important memory content \(index)", occurredAt: now.addingTimeInterval(Double(index)))
    }

    let enqueued = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 2, maxEventsPerBlock: 2, maxTokensPerBlock: 1000), now: now)

    #expect(enqueued.count == 2)
    let runnable = try store.runnableQueueItems(kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue, limit: 10, now: now)
    #expect(runnable.count == 2)
    let payload = try store.decode(MemoryOSL1UnifiedProjectionJobDraft.self, runnable[0].payloadJSON)
    #expect(payload.schemaName == "MemoryOSL1UnifiedProjectionOutput")
    #expect(payload.prompt.contains("L2 entity-centered working memory"))
    #expect(payload.prompt.contains("L3 reusable knowledge candidates"))
    #expect(payload.prompt.contains("L4 stable entities"))
}

@Test func projectionQueuePayloadPreservesKnowledgeSchema() throws {
    let payload = MemoryOSProjectionQueuePayload(rawContent: "{}", modelID: "model", processingRunID: "run", schemaName: "MemoryOSKnowledgeExtractionOutput", artifactType: "memory_os_knowledge_extraction")

    #expect(payload.schemaName == "MemoryOSKnowledgeExtractionOutput")
    #expect(payload.artifactType == "memory_os_knowledge_extraction")
}

@Test func planningL1TwiceReusesExistingQueueJobWithoutForeignKeyFailure() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundPipelineDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 6_500)
    _ = try facade.ingestChatMessage(messageID: "message-duplicate", sessionID: "session", role: "user", content: "Memory OS L1 duplicate planning should be idempotent.", occurredAt: now)

    let first = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10), now: now)
    let firstItem = try #require(first.first)
    try store.saveQueueAttempt(queueItemID: firstItem.id, attemptNumber: 1, status: .failed, startedAt: now, finishedAt: now, errorCode: "simulated_failure")

    let second = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10), now: now.addingTimeInterval(60))

    #expect(second.isEmpty)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_processing_queue;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_queue_attempts WHERE queue_item_id = \(store.quote(firstItem.id));").first?.first == "1")
}

@Test func pendingL1PlannerIgnoresCaptureEventsAlreadyReferencedByActiveQueueItems() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundPipelineDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 6_600)
    let ingestion = try facade.ingestChatMessage(messageID: "message-active", sessionID: "session", role: "user", content: "This capture is already owned by an active queue item.", occurredAt: now)
    let capture = try #require(ingestion.captureEvent)
    let draft = MemoryOSL1UnifiedProjectionJobDraft(
        captureEventIDs: [capture.id],
        provenanceObjectIDs: [capture.provenanceObjectID],
        sourceSpanIDs: [],
        prompt: "Already planned",
        createdAt: now
    )
    let payload = store.json(draft)
    try store.enqueue(MemoryOSQueueItem(
        id: "queue-active-existing",
        kind: draft.kind,
        status: .processing,
        payloadJSON: payload,
        nextRunAt: now,
        idempotencyKey: "manual-active-existing",
        payloadHash: String(payload.hashValue),
        createdAt: now,
        updatedAt: now
    ))

    let enqueued = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10), now: now)

    #expect(enqueued.isEmpty)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_processing_queue;").first?.first == "1")
}

@Test func successfulL1JobDeletesCaptureEventsAndTimeBlockLinks() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundPipelineDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 6_700)
    let ingestion = try facade.ingestChatMessage(messageID: "message-cleanup", sessionID: "session", role: "user", content: "Cleanup should delete time block links before capture events.", occurredAt: now)
    let capture = try #require(ingestion.captureEvent)
    try store.upsert(timeBlock: MemoryOSTimeBlock(id: "time-block-cleanup", title: "Cleanup", startedAt: now, endedAt: now.addingTimeInterval(60), tokenEstimate: 10, status: .succeeded))
    try store.execute("""
    INSERT INTO memory_l1_time_block_events(time_block_id, capture_event_id, sequence)
    VALUES ('time-block-cleanup', \(store.quote(capture.id)), 0);
    """)
    _ = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10), now: now)

    let summaries = try facade.runBackgroundAIQueueOnce(executor: PipelineStaticMemoryOSBackgroundExecutor(rawArtifactJSON: try pipelineEncodedGraphArtifact()), now: now)

    #expect(summaries.count == 1)
    #expect(summaries[0].accepted)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_time_block_events WHERE capture_event_id = \(store.quote(capture.id));").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events WHERE id = \(store.quote(capture.id));").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_processing_queue WHERE status = 'succeeded';").first?.first == "1")
}

private final class PipelineStaticMemoryOSBackgroundExecutor: MemoryOSBackgroundModelExecutor, @unchecked Sendable {
    let rawArtifactJSON: String
    init(rawArtifactJSON: String) { self.rawArtifactJSON = rawArtifactJSON }
    func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse {
        MemoryOSBackgroundModelResponse(rawArtifactJSON: rawArtifactJSON, metadata: ["model_id": "mock-memory-worker"])
    }
}

private func pipelineEncodedGraphArtifact() throws -> String {
    let output = MemoryOSL1UnifiedProjectionOutput(
        operationalEntities: [],
        operationalStatements: [],
        evidenceSpans: [],
        knowledgeCandidates: [],
        conceptEntities: [],
        conceptRelations: [],
        promotionDecisions: []
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(output), encoding: .utf8)!
}

private func temporaryAppMemoryOSBackgroundPipelineDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-background-pipeline-\(UUID().uuidString).sqlite")
}
