import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func appMemoryOSFacadeEnqueuesL1ToL2BackgroundJobsFromPendingCaptures() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundPipelineDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 6_000)
    for index in 0..<3 {
        _ = try facade.ingestChatMessage(messageID: "message-\(index)", sessionID: "session", role: "user", content: "Important memory content \(index)", occurredAt: now.addingTimeInterval(Double(index)))
    }

    let enqueued = try facade.enqueueL1ToL2BackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 2, maxEventsPerBlock: 2, maxTokensPerBlock: 1000), now: now)

    #expect(enqueued.count == 2)
    let runnable = try store.runnableQueueItems(kind: MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue, limit: 10, now: now)
    #expect(runnable.count == 2)
    let payload = try store.decode(MemoryOSL1ToL2JobDraft.self, runnable[0].payloadJSON)
    #expect(payload.schemaName == "GraphStructuredExtractionOutput")
    #expect(payload.prompt.contains("L2 operational facts"))
}

@Test func appMemoryOSFacadeEnqueuesL2ToKnowledgeJobsFromProcessingState() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundPipelineDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 6_000)
    for index in 0..<3 {
        let node = MemoryOSNode(id: "node-\(index)", stableKey: "node-\(index)", nodeType: "topic", name: "Topic \(index)")
        try store.upsert(node: node)
        let statement = MemoryOSStatement(id: "statement-\(index)", subjectID: node.id, predicate: "observed", text: "Reusable pattern \(index)", confidence: 0.8, validAt: now, committedAt: now, evidenceSpanIDs: ["span-\(index)"])
        try store.upsert(statement: statement)
        try store.upsert(l2ProcessingState: MemoryOSL2StatementProcessingState(statementID: statement.id, processingKind: .knowledgeSynthesis, status: .pending, lastAttemptAt: now))
    }

    let enqueued = try facade.enqueueL2ToKnowledgeBackgroundJobs(policy: MemoryOSL2KnowledgeSynthesisTriggerPolicy(minPendingStatementCount: 2, maxStatementsPerBlock: 2), now: now)

    #expect(enqueued.count == 2)
    let runnable = try store.runnableQueueItems(kind: MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue, limit: 10, now: now)
    #expect(runnable.count == 2)
    let payload = try store.decode(MemoryOSL2ToKnowledgeJobDraft.self, runnable[0].payloadJSON)
    #expect(payload.schemaName == "MemoryOSKnowledgeExtractionOutput")
    #expect(payload.prompt.contains("four knowledge filters"))
}

@Test func projectionQueuePayloadPreservesKnowledgeSchema() throws {
    let payload = MemoryOSProjectionQueuePayload(rawContent: "{}", modelID: "model", processingRunID: "run", schemaName: "MemoryOSKnowledgeExtractionOutput", artifactType: "memory_os_knowledge_extraction")

    #expect(payload.schemaName == "MemoryOSKnowledgeExtractionOutput")
    #expect(payload.artifactType == "memory_os_knowledge_extraction")
}

private func temporaryAppMemoryOSBackgroundPipelineDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-background-pipeline-\(UUID().uuidString).sqlite")
}
