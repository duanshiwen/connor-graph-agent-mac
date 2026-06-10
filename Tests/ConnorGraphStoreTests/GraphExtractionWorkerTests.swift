import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryExtractionWorkerDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private struct StubGraphExtractor: GraphExtractorProvider {
    var draft: GraphExtractionDraft

    func extract(from source: GraphExtractionSource) async throws -> GraphExtractionDraft {
        draft
    }
}

@Test func extractionWorkerRunsExtractionJobAndCommitsGraphBatch() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryExtractionWorkerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let source = GraphExtractionSource(id: "email-1", graphID: "default", sourceType: .email, title: "Tea", content: "诗闻 prefers tea", occurredAt: now)
    let draft = GraphExtractionDraft(
        source: source,
        entities: [
            GraphExtractedEntityDraft(localID: "shiwen", name: "诗闻", entityKind: .personObject, scope: .personal),
            GraphExtractedEntityDraft(localID: "tea", name: "tea", entityKind: .lifeObject, scope: .personal)
        ],
        statements: [
            GraphExtractedStatementDraft(subjectLocalID: "shiwen", predicate: .prefers, objectLocalID: "tea", statementText: "诗闻 prefers tea", confidence: 0.85, metadata: ["evidence_span_ids": "span-1"])
        ],
        metadata: ["llm_model_id": "fake-model", "prompt_tokens": "12", "latency_ms": "34"]
    )
    try store.upsert(job: GraphJobV3(
        id: "job-extract-1",
        graphID: "default",
        type: .extraction,
        payload: GraphExtractionJobPayload(source: source).dictionary,
        createdAt: now,
        nextRunAt: now
    ))

    let result = try await GraphExtractionWorker(store: store, extractor: StubGraphExtractor(draft: draft)).runNext(graphID: "default", now: now)

    #expect(result?.jobID == "job-extract-1")
    #expect(result?.extractedEntityCount == 2)
    #expect(result?.extractedStatementCount == 1)
    #expect(result?.writeResult.committedStatementIDs.count == 1)
    #expect(try store.episode(id: "episode-email-1") != nil)
    #expect(try store.statements(graphID: "default", predicate: .prefers).count == 1)
    let traces = try store.extractionTraces(jobID: "job-extract-1")
    #expect(traces.count == 1)
    #expect(traces[0].outcome == .committed)
    #expect(traces[0].admissionAction == .autoCommit)
    #expect(traces[0].committedStatementCount == 1)
    #expect(traces[0].metadata["llm_model_id"] == "fake-model")
    #expect(traces[0].metadata["prompt_tokens"] == "12")
    #expect(traces[0].metadata["latency_ms"] == "34")
    #expect(try store.runnableJobs(graphID: "default", at: now).contains { $0.id == "job-extract-1" } == false)
}

@Test func extractionWorkerHoldsLowConfidenceDraftWithoutCommitting() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryExtractionWorkerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let source = GraphExtractionSource(id: "email-2", graphID: "default", sourceType: .email, title: "Weak", content: "Maybe poetry likes oolong", occurredAt: now)
    let draft = GraphExtractionDraft(
        source: source,
        entities: [
            GraphExtractedEntityDraft(localID: "poetry", name: "poetry", entityKind: .personObject, scope: .personal),
            GraphExtractedEntityDraft(localID: "oolong", name: "oolong", entityKind: .lifeObject, scope: .personal)
        ],
        statements: [
            GraphExtractedStatementDraft(subjectLocalID: "poetry", predicate: .prefers, objectLocalID: "oolong", statementText: "Maybe poetry likes oolong", confidence: 0.4, metadata: ["evidence_span_ids": "span-1"])
        ]
    )
    try store.upsert(job: GraphJobV3(
        id: "job-extract-low-confidence",
        graphID: "default",
        type: .extraction,
        payload: GraphExtractionJobPayload(source: source).dictionary,
        createdAt: now,
        nextRunAt: now
    ))

    let result = try await GraphExtractionWorker(store: store, extractor: StubGraphExtractor(draft: draft)).runNext(graphID: "default", now: now)

    #expect(result?.action == .held)
    #expect(result?.admissionDecision?.reasons.contains(.lowStatementConfidence) == true)
    #expect(result?.writeResult.committedStatementIDs.isEmpty == true)
    #expect(try store.statements(graphID: "default", predicate: .prefers).isEmpty)
    let traces = try store.extractionTraces(jobID: "job-extract-low-confidence")
    #expect(traces.count == 1)
    #expect(traces[0].outcome == .held)
    #expect(traces[0].admissionAction == .hold)
    #expect(traces[0].admissionReasons.contains(.lowStatementConfidence))
    #expect(try store.runnableJobs(graphID: "default", at: now).contains { $0.id == "job-extract-low-confidence" } == false)
}

@Test func extractionWorkerMarksJobFailedWhenPayloadIsInvalid() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryExtractionWorkerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let emptySource = GraphExtractionSource(id: "unused", graphID: "default", sourceType: .manual, title: "unused", content: "unused", occurredAt: now)
    try store.upsert(job: GraphJobV3(id: "bad-job", graphID: "default", type: .extraction, payload: [:], createdAt: now, nextRunAt: now))

    let result = try await GraphExtractionWorker(store: store, extractor: StubGraphExtractor(draft: GraphExtractionDraft(source: emptySource))).runNext(graphID: "default", now: now)

    #expect(result?.action == .failed)
    #expect(result?.errorMessage?.contains("invalidPayload") == true)
    let traces = try store.extractionTraces(jobID: "bad-job")
    #expect(traces.count == 1)
    #expect(traces[0].outcome == .failed)
    #expect(traces[0].errorMessage?.contains("invalidPayload") == true)
}
