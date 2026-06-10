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
            GraphExtractedStatementDraft(subjectLocalID: "shiwen", predicate: .prefers, objectLocalID: "tea", statementText: "诗闻 prefers tea", confidence: 0.85)
        ]
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
    #expect(result?.writeResult.committedStatementIDs.count == 1)
    #expect(try store.episode(id: "episode-email-1") != nil)
    #expect(try store.statements(graphID: "default", predicate: .prefers).count == 1)
    #expect(try store.runnableJobs(graphID: "default", at: now).contains { $0.id == "job-extract-1" } == false)
}

@Test func extractionWorkerMarksJobFailedWhenPayloadIsInvalid() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryExtractionWorkerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let emptySource = GraphExtractionSource(id: "unused", graphID: "default", sourceType: .manual, title: "unused", content: "unused", occurredAt: now)
    try store.upsert(job: GraphJobV3(id: "bad-job", graphID: "default", type: .extraction, payload: [:], createdAt: now, nextRunAt: now))

    let result = try await GraphExtractionWorker(store: store, extractor: StubGraphExtractor(draft: GraphExtractionDraft(source: emptySource))).runNext(graphID: "default", now: now)

    #expect(result?.action == .failed)
}
