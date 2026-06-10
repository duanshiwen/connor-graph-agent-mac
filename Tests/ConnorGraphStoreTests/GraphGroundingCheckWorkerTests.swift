import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryGroundingCheckDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private struct GroundingRunnerStubExtractor: GraphExtractorProvider {
    var draft: GraphExtractionDraft

    func extract(from source: GraphExtractionSource) async throws -> GraphExtractionDraft {
        draft
    }
}

@Test func groundingCheckWorkerVerifiesStatementWithEvidence() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryGroundingCheckDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    try seedGroundingEntities(store: store, now: now)
    try store.upsert(statement: GraphStatement(
        id: "statement-grounded",
        graphID: "default",
        subjectEntityID: "person",
        predicate: .prefers,
        objectEntityID: "tea",
        statementText: "诗闻喜欢茶。",
        validAt: now,
        confidence: 0.9,
        justifications: [GraphJustification(type: .userStated, source: "chat", strength: 0.9, evidenceSpan: "诗闻喜欢茶。")]
    ))
    try store.upsert(job: GraphJobV3(
        id: "job-grounding-grounded",
        graphID: "default",
        type: .groundingCheck,
        payload: ["statement_id": "statement-grounded"],
        createdAt: now,
        nextRunAt: now
    ))

    let result = try GraphGroundingCheckWorker(store: store).run(job: try #require(try store.job(id: "job-grounding-grounded")), now: now)

    #expect(result.action == .verified)
    #expect(result.anomalyID == nil)
    #expect(try store.job(id: "job-grounding-grounded")?.status == .succeeded)
    let statement = try #require(try store.statement(id: "statement-grounded"))
    #expect(statement.metadata["grounding_status"] == "verified")
    #expect(statement.metadata["grounding_reason"] == "has_evidence_span_justification")
}

@Test func groundingCheckWorkerFlagsUngroundedStatementAndQueuesAnomalyResolution() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryGroundingCheckDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 2_000)
    try seedGroundingEntities(store: store, now: now)
    try store.upsert(statement: GraphStatement(
        id: "statement-ungrounded",
        graphID: "default",
        subjectEntityID: "person",
        predicate: .prefers,
        objectEntityID: "tea",
        statementText: "诗闻喜欢茶。",
        validAt: now,
        confidence: 0.9
    ))
    try store.upsert(job: GraphJobV3(
        id: "job-grounding-ungrounded",
        graphID: "default",
        type: .groundingCheck,
        payload: ["statement_id": "statement-ungrounded"],
        createdAt: now,
        nextRunAt: now
    ))

    let result = try GraphGroundingCheckWorker(store: store).run(job: try #require(try store.job(id: "job-grounding-ungrounded")), now: now)

    #expect(result.action == .flagged)
    #expect(result.anomalyID == "anomaly-grounding-statement-ungrounded")
    #expect(try store.job(id: "job-grounding-ungrounded")?.status == .succeeded)
    let statement = try #require(try store.statement(id: "statement-ungrounded"))
    #expect(statement.metadata["grounding_status"] == "needs_review")
    #expect(statement.metadata["grounding_anomaly_id"] == "anomaly-grounding-statement-ungrounded")
    let anomaly = try #require(try store.anomaly(id: "anomaly-grounding-statement-ungrounded"))
    #expect(anomaly.anomalyType == .commonSenseViolation)
    #expect(anomaly.metadata["anomaly_subtype"] == "ungrounded_statement")
    #expect(try store.job(id: "job-anomaly-resolution-anomaly-grounding-statement-ungrounded")?.type == .anomalyResolution)
}

@Test func backgroundJobRunnerDispatchesGroundingCheckJob() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryGroundingCheckDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 3_000)
    try seedGroundingEntities(store: store, now: now)
    try store.upsert(statement: GraphStatement(
        id: "statement-runner-grounded",
        graphID: "default",
        subjectEntityID: "person",
        predicate: .prefers,
        objectEntityID: "tea",
        statementText: "诗闻喜欢茶。",
        validAt: now,
        sourceEpisodeIDs: ["episode-1"]
    ))
    try store.upsert(job: GraphJobV3(
        id: "job-grounding-runner",
        graphID: "default",
        type: .groundingCheck,
        payload: ["statement_id": "statement-runner-grounded"],
        createdAt: now,
        nextRunAt: now
    ))
    let source = GraphExtractionSource(id: "unused", graphID: "default", sourceType: .manual, title: "unused", content: "unused", occurredAt: now)

    let result = try await GraphBackgroundJobRunner(store: store, extractor: GroundingRunnerStubExtractor(draft: GraphExtractionDraft(source: source))).runOnce(graphID: "default", now: now)

    #expect(result?.jobID == "job-grounding-runner")
    #expect(result?.jobType == .groundingCheck)
    #expect(result?.outcome == .succeeded)
    #expect(try store.statement(id: "statement-runner-grounded")?.metadata["grounding_status"] == "verified")
}

private func seedGroundingEntities(store: SQLiteGraphKernelStore, now: Date) throws {
    try store.upsert(entity: GraphEntity(
        id: "person",
        graphID: "default",
        name: "诗闻",
        entityKind: .personObject,
        scope: .personal,
        createdAt: now
    ))
    try store.upsert(entity: GraphEntity(
        id: "tea",
        graphID: "default",
        name: "茶",
        entityKind: .lifeObject,
        scope: .personal,
        createdAt: now
    ))
}
