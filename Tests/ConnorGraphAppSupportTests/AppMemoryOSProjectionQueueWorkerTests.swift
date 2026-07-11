import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

private func temporaryAppMemoryOSProjectionWorkerDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private func encodedWorkerProjectionFixture() throws -> String {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "person-1", name: "诗闻", entityKind: .personObject, scope: .personal, confidence: 0.95, evidenceSpanIDs: ["span-1"]),
            GraphStructuredExtractedEntity(localID: "project-1", name: "Connor Memory OS", entityKind: .workObject, scope: .project, confidence: 0.93, evidenceSpanIDs: ["span-1"])
        ],
        statements: [
            GraphStructuredExtractedStatement(explicitID: "stmt-1", subjectLocalID: "person-1", predicate: .relatedTo, objectLocalID: "project-1", statementText: "H4 worker projects durable Memory OS queue jobs。", confidence: 0.94, evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "H4 worker projects durable Memory OS queue jobs。")]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(output), encoding: .utf8)!
}

private func degradedWorkerProjectionFixture() throws -> String {
    let output = MemoryOSL1UnifiedProjectionOutput(
        operationalEntities: [
            GraphStructuredExtractedEntity(localID: "project-1", name: "Connor Memory OS", entityKind: .workObject, scope: .project, confidence: 0.93, evidenceSpanIDs: ["span-1"])
        ],
        operationalStatements: [
            GraphStructuredExtractedStatement(explicitID: "stmt-worker-good-1", subjectLocalID: "project-1", predicate: .relatedTo, objectLocalID: "project-1", statementText: "Worker projection keeps safe records.", confidence: 0.94, evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "Worker projection keeps safe records.")],
        knowledgeCandidates: [
            MemoryOSKnowledgeCandidate(
                id: "knowledge-worker-noise-1",
                title: "Projection worker noise candidate",
                claim: "This candidate should be dropped without failing the artifact.",
                category: "heuristic",
                knowledgeType: "heuristic",
                domain: "software-engineering",
                signalAssessment: MemoryOSKnowledgeSignalAssessment(signalQualityAccepted: true, reuseScopeAccepted: false, noveltyAccepted: true, structurabilityAccepted: true, reasons: ["Not reusable"]),
                confidence: 0.7,
                evidenceStatementIDs: ["stmt-worker-good-1"],
                evidenceSpanIDs: ["span-1"],
                relatedEntityNames: ["Connor Memory OS"]
            )
        ],
        conceptEntities: [],
        conceptRelations: [],
        promotionDecisions: []
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(output), encoding: .utf8)!
}

@Test func appMemoryOSProjectionQueueWorkerProcessesRunnableJobs() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSProjectionWorkerDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 5_000)
    let payload = MemoryOSProjectionQueuePayload(rawContent: try encodedWorkerProjectionFixture(), modelID: "test-model", processingRunID: "run-worker-1")
    try store.enqueue(MemoryOSQueueItem(id: "queue-worker-1", kind: "project_artifact", status: .pending, priority: 10, payloadJSON: store.json(payload), nextRunAt: now, idempotencyKey: "queue-worker-1-key"))

    let summaries = try facade.runProjectionQueueOnce(workerID: "test-worker", now: now)

    #expect(summaries.count == 1)
    #expect(summaries.first?.accepted == true)
    #expect(try store.queueItem(id: "queue-worker-1")?.status == .succeeded)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_statements;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l3_beliefs;").first?.first == "0")
}

@Test func appMemoryOSProjectionQueueWorkerRetriesMalformedPayloadWithoutProjecting() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSProjectionWorkerDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 5_000)
    try store.enqueue(MemoryOSQueueItem(id: "queue-worker-bad", kind: "project_artifact", status: .pending, payloadJSON: "{bad-json", attemptCount: 0, maxAttempts: 2, nextRunAt: now, idempotencyKey: "queue-worker-bad-key"))

    let summaries = try facade.runProjectionQueueOnce(workerID: "test-worker", now: now)

    #expect(summaries.count == 1)
    #expect(summaries.first?.accepted == false)
    #expect(try store.queueItem(id: "queue-worker-bad")?.status == .retryScheduled)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_statements;").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_queue_attempts WHERE queue_item_id = 'queue-worker-bad';").first?.first == "1")
}

@Test func appMemoryOSProjectionRecordsGracefulAcceptanceMetrics() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSProjectionWorkerDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 6_000)
    let raw = try degradedWorkerProjectionFixture()

    let summary = try facade.projectAndRecordLLMArtifact(
        rawContent: raw,
        modelID: "test-model",
        artifactType: "memory_os_l1_unified_projection",
        schemaName: "MemoryOSL1UnifiedProjectionOutput",
        now: now
    )

    let metrics = try store.recentMetricSums(names: [
        "memory_os.projection.accepted",
        "memory_os.projection.degraded_accepted",
        "memory_os.projection.records.dropped"
    ])

    #expect(summary.accepted)
    #expect(summary.acceptanceModeKind == .degradedAccepted)
    #expect(summary.droppedRecordCount == 1)
    #expect(Int(metrics["memory_os.projection.accepted", default: 0]) == 1)
    #expect(Int(metrics["memory_os.projection.degraded_accepted", default: 0]) == 1)
    #expect(Int(metrics["memory_os.projection.records.dropped", default: 0]) == 1)
}
