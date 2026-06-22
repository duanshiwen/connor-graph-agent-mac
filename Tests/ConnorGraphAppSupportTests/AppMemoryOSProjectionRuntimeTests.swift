import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

private func temporaryAppMemoryOSProjectionDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private func encodedProjectionFixture(confidence: Double = 0.94, includeEvidence: Bool = true) throws -> String {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "person-1", name: "诗闻", entityKind: .personObject, scope: .personal, confidence: 0.95, evidenceSpanIDs: includeEvidence ? ["span-1"] : []),
            GraphStructuredExtractedEntity(localID: "project-1", name: "Connor Memory OS", entityKind: .workObject, scope: .project, confidence: 0.93, evidenceSpanIDs: includeEvidence ? ["span-1"] : [])
        ],
        statements: [
            GraphStructuredExtractedStatement(explicitID: "stmt-1", subjectLocalID: "person-1", predicate: .relatedTo, objectLocalID: "project-1", statementText: "诗闻正在推进 Connor Memory OS H4。", confidence: confidence, evidenceSpanIDs: includeEvidence ? ["span-1"] : [])
        ],
        evidenceSpans: includeEvidence ? [GraphStructuredEvidenceSpan(id: "span-1", text: "诗闻正在推进 Connor Memory OS H4。")] : []
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(output), encoding: .utf8)!
}

@Test func appMemoryOSFacadeProjectsAcceptedArtifactAndMarksQueueSucceeded() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSProjectionDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 4_000)
    let item = MemoryOSQueueItem(id: "queue-projection", kind: "project_artifact", status: .processing, attemptCount: 1, maxAttempts: 3, nextRunAt: now, lockedAt: now.addingTimeInterval(-10), lockedBy: "worker", leaseExpiresAt: now.addingTimeInterval(60), idempotencyKey: "queue-projection-key")
    try store.enqueue(item)

    let summary = try facade.projectAndRecordLLMArtifact(rawContent: try encodedProjectionFixture(), modelID: "test-model", queueItem: item, processingRunID: "run-1", now: now)

    #expect(summary.accepted)
    #expect(summary.nodeCount == 2)
    #expect(summary.statementCount == 1)
    #expect(summary.entityCount == 2)
    #expect(summary.entityStatementCount == 1)
    #expect(summary.beliefCount == 0)
    #expect(try store.queueItem(id: "queue-projection")?.status == .succeeded)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_statements;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l4_entities;").first?.first == "2")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.projection.succeeded';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.queue.succeeded';").first?.first == "1")
}

@Test func appMemoryOSFacadeRejectsInvalidProjectionArtifactAndRetriesQueue() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSProjectionDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 4_000)
    let item = MemoryOSQueueItem(id: "queue-retry", kind: "project_artifact", status: .processing, attemptCount: 0, maxAttempts: 2, nextRunAt: now, lockedAt: now.addingTimeInterval(-10), lockedBy: "worker", leaseExpiresAt: now.addingTimeInterval(60), idempotencyKey: "queue-retry-key")
    try store.enqueue(item)

    let summary = try facade.projectAndRecordLLMArtifact(rawContent: try encodedProjectionFixture(includeEvidence: false), modelID: "test-model", queueItem: item, now: now)

    #expect(!summary.accepted)
    #expect(summary.issues.contains { $0.code == "schema_validation_failed" })
    #expect(try store.queueItem(id: "queue-retry")?.status == .retryScheduled)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_statements;").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.projection.rejected';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.queue.failure';").first?.first == "1")
}
