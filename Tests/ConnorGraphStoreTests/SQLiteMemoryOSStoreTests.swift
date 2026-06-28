import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryMemoryOSDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func sqliteMemoryOSStoreCreatesProductionSchema() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()
    let indexes = try store.indexNames()

    for table in SQLiteMemoryOSStore.requiredSchemaTables {
        #expect(tables.contains(table), "Missing table: \(table)")
    }
    for index in SQLiteMemoryOSStore.requiredSchemaIndexes {
        #expect(indexes.contains(index), "Missing index: \(index)")
    }
}

@Test func sqliteMemoryOSStoreDoesNotCreateLegacyWorkflowTables() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()
    let legacyTables: Set<String> = [
        "memory_staging_buffers",
        "graph_extraction_traces",
        "graph_extraction_trace_payloads",
        "graph_admission_hold_queue",
        "graph_memory_change_log",
        "graph_write_candidates"
    ]

    #expect(tables.intersection(legacyTables).isEmpty)
}

@Test func sqliteMemoryOSStoreReportsHealthySchemaAfterMigration() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSDatabaseURL().path)
    try store.migrate()

    let report = try store.schemaHealthReport(now: Date(timeIntervalSince1970: 10))

    #expect(report.expectedVersion == SQLiteMemoryOSStore.currentSchemaVersion)
    #expect(report.actualVersion == SQLiteMemoryOSStore.currentSchemaVersion)
    #expect(report.status == .healthy)
    #expect(report.missingTables.isEmpty)
    #expect(report.missingIndexes.isEmpty)
}

@Test func sqliteMemoryOSStoreReportsMigrationRequiredBeforeMigration() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSDatabaseURL().path)

    let report = try store.schemaHealthReport(now: Date(timeIntervalSince1970: 10))

    #expect(report.actualVersion == 0)
    #expect(report.status == .migrationRequired)
}

@Test func sqliteMemoryOSStoreEnablesProductionPragmas() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSDatabaseURL().path)
    try store.migrate()

    #expect(try store.pragmaValue("foreign_keys") == "1")
    #expect((try store.pragmaValue("journal_mode"))?.lowercased() == "wal")
    #expect((try store.pragmaValue("busy_timeout")) == "5000")
}

@Test func sqliteMemoryOSStoreRoundTripsL0L1L2L3L4Records() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)

    let provenance = MemoryOSProvenanceObject(
        id: "prov-1",
        sourceType: .chatMessage,
        sourceID: "message-1",
        title: "Preference evidence",
        content: "诗闻 requires production-grade Memory OS.",
        contentHash: "hash-1",
        occurredAt: now,
        ingestedAt: now,
        sessionID: "session-1"
    )
    try store.upsert(provenance: provenance)
    let span = MemoryOSProvenanceSpan(id: "span-1", provenanceObjectID: provenance.id, startOffset: 0, endOffset: 20, text: "production-grade Memory OS")
    try store.upsert(span: span)
    let capture = MemoryOSCaptureEvent(id: "capture-1", provenanceObjectID: provenance.id, eventType: "chat_message", occurredAt: now, tokenEstimate: 12)
    try store.upsert(captureEvent: capture)
    let queue = MemoryOSQueueItem(id: "queue-1", kind: "l2_processing", nextRunAt: now, idempotencyKey: "idem-1", payloadHash: "payload-1", createdAt: now, updatedAt: now)
    try store.enqueue(queue)

    let node = MemoryOSNode(id: "node-1", stableKey: "default:project:memory-os", nodeType: "project", name: "Memory OS", summary: "Production-grade memory")
    try store.upsert(node: node)
    let statement = MemoryOSStatement(id: "stmt-1", subjectID: node.id, predicate: "requires", text: "Memory OS requires production-grade storage.", assertionKind: .observed, confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: [span.id])
    try store.upsert(statement: statement)
    let belief = MemoryOSBelief(id: "belief-1", statement: "Memory OS must be production-grade.", domain: "software-engineering", relatedObjectNames: "Semantic memory", createdAt: now, updatedAt: now)
    try store.upsert(belief: belief)
    let entity = MemoryOSEntity(id: "entity-1", stableKey: "default:project:memory-os", entityType: "project", name: "Memory OS", aliases: ["Connor Memory OS"], summary: "Stable entity for the memory system", confidence: 0.9, createdAt: now, updatedAt: now)
    try store.upsert(entity: entity)

    #expect(try store.provenanceObject(id: provenance.id)?.content == provenance.content)
    #expect(try store.queueItem(id: queue.id)?.idempotencyKey == "idem-1")
    #expect(try store.searchStatementsFTS(query: "storage").contains(statement.id))
    #expect(try store.entity(id: entity.id)?.aliases == ["Connor Memory OS"])
    #expect(try store.searchEntitiesFTS(query: "Connor").contains(entity.id))

    let indexQueue = try store.pendingSearchIndexQueueItems(limit: 20)
    #expect(indexQueue.contains { $0["layer"] == "L0" && $0["record_id"] == provenance.id })
    #expect(indexQueue.contains { $0["layer"] == "L1" && $0["record_id"] == capture.id })
    #expect(indexQueue.contains { $0["layer"] == "L2" && $0["record_id"] == node.id })
    #expect(indexQueue.contains { $0["layer"] == "L2" && $0["record_id"] == statement.id })
    #expect(indexQueue.contains { $0["layer"] == "L3" && $0["record_id"] == belief.id })
    #expect(indexQueue.contains { $0["layer"] == "L4" && $0["record_id"] == entity.id })
    let firstQueueID = try #require(indexQueue.first?["id"])
    try store.markSearchIndexQueueItemProcessed(id: firstQueueID, now: now)
    #expect(try store.pendingSearchIndexQueueItems(limit: 20).allSatisfy { $0["id"] != firstQueueID })
}

@Test func sqliteMemoryOSStoreMigrationIsIdempotent() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSDatabaseURL().path)

    try store.migrate()
    try store.migrate()

    #expect(try store.schemaHealthReport().status == .healthy)
}

@Test func sqliteMemoryOSStoreRoundTripsBackgroundRunTrace() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 2_000)

    let run = MemoryOSBackgroundRunRecord(
        id: "run-1",
        queueItemID: "queue-1",
        kind: "memory.l1.synthesize_knowledge",
        source: "l1_capture_events",
        status: .running,
        startedAt: now,
        modelID: "test-model",
        iterationCount: 1,
        toolCallCount: 1,
        statelessBatch: true,
        metadata: ["batch": "current"]
    )
    try store.save(backgroundRun: run)
    try store.save(backgroundMessage: MemoryOSBackgroundMessageRecord(
        id: "message-1",
        runID: run.id,
        sequence: 0,
        role: .user,
        content: "Preset prompt + current batch only",
        metadata: ["scope": "initial"]
    ))
    try store.save(backgroundToolCall: MemoryOSBackgroundToolCallRecord(
        id: "tool-1",
        runID: run.id,
        iteration: 1,
        toolName: "memory_os_search",
        argumentsJSON: #"{"query":"current user","layers":["L3","L4"]}"#,
        resultJSON: #"{"results":[]}"#,
        status: .succeeded,
        startedAt: now,
        finishedAt: now.addingTimeInterval(1),
        metadata: ["trace": "run-local"]
    ))

    let runs = try store.backgroundRuns(limit: 10)
    let loadedRun = try #require(runs.first { $0.id == run.id })
    #expect(loadedRun.statelessBatch)
    #expect(loadedRun.queueItemID == "queue-1")
    #expect(loadedRun.metadata["batch"] == "current")

    let messages = try store.backgroundMessages(runID: run.id)
    #expect(messages.map(\.content) == ["Preset prompt + current batch only"])
    #expect(messages.first?.metadata["scope"] == "initial")

    let toolCalls = try store.backgroundToolCalls(runID: run.id)
    #expect(toolCalls.count == 1)
    #expect(toolCalls.first?.toolName == "memory_os_search")
    #expect(toolCalls.first?.metadata["trace"] == "run-local")
}
