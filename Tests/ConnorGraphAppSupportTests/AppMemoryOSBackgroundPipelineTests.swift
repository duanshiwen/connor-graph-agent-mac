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

private func temporaryAppMemoryOSBackgroundPipelineDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-background-pipeline-\(UUID().uuidString).sqlite")
}
