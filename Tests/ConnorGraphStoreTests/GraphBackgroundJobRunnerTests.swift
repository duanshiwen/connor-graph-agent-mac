import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryBackgroundRunnerDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private struct BackgroundRunnerFakeExtractor: GraphExtractorProvider {
    var draft: GraphExtractionDraft

    func extract(from source: GraphExtractionSource) async throws -> GraphExtractionDraft {
        draft
    }
}

@Test func backgroundJobRunnerDispatchesExtractionJob() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryBackgroundRunnerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let source = GraphExtractionSource(id: "email-1", graphID: "default", sourceType: .email, title: "Tea", content: "诗闻 prefers tea", occurredAt: now)
    let draft = GraphExtractionDraft(
        source: source,
        entities: [
            GraphExtractedEntityDraft(localID: "shiwen", name: "诗闻", entityKind: .personObject, scope: .personal),
            GraphExtractedEntityDraft(localID: "tea", name: "tea", entityKind: .lifeObject, scope: .personal)
        ],
        statements: [GraphExtractedStatementDraft(
            subjectLocalID: "shiwen",
            predicate: .prefers,
            objectLocalID: "tea",
            statementText: "诗闻 prefers tea",
            metadata: ["evidence_text": "诗闻 prefers tea"]
        )]
    )
    try store.upsert(job: GraphJobV3(id: "job-extraction", graphID: "default", type: .extraction, priority: 10, payload: GraphExtractionJobPayload(source: source).dictionary, createdAt: now, nextRunAt: now))

    let result = try await GraphBackgroundJobRunner(store: store, extractor: BackgroundRunnerFakeExtractor(draft: draft)).runOnce(graphID: "default", now: now)

    #expect(result?.jobID == "job-extraction")
    #expect(result?.jobType == .extraction)
    #expect(result?.outcome == .succeeded)
    #expect(try store.statements(graphID: "default", predicate: .prefers).count == 1)
}

@Test func backgroundJobRunnerFailsExtractionWhenExtractorIsUnavailable() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryBackgroundRunnerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let source = GraphExtractionSource(id: "note-1", graphID: "default", sourceType: .manual, title: "Memory", content: "Important memory", occurredAt: now)
    try store.upsert(job: GraphJobV3(id: "job-unavailable-extraction", graphID: "default", type: .extraction, priority: 10, payload: GraphExtractionJobPayload(source: source).dictionary, createdAt: now, nextRunAt: now))

    let result = try await GraphBackgroundJobRunner(store: store, extractor: UnavailableGraphExtractor()).runOnce(graphID: "default", now: now)
    let storedJob = try #require(try store.job(id: "job-unavailable-extraction"))

    #expect(result?.jobID == "job-unavailable-extraction")
    #expect(result?.jobType == .extraction)
    #expect(result?.outcome == .failed)
    #expect(result.map { $0.message.contains("OpenAI-compatible LLM provider") } == true)
    #expect(storedJob.status == .failed)
    #expect(storedJob.errorCode == "extraction_failed")
    #expect(storedJob.errorMessage?.contains("OpenAI-compatible LLM provider") == true)
    #expect(try store.statements(graphID: "default").isEmpty)
}

@Test func backgroundJobRunnerDispatchesHighestPriorityRunnableJob() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryBackgroundRunnerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let entity = GraphEntity(id: "entity", graphID: "default", name: "Graph Kernel", entityKind: .workObject, scope: .project)
    try store.upsert(entity: entity)
    try store.upsert(job: GraphJobV3(id: "job-low", graphID: "default", type: .indexRefresh, priority: 1, payload: ["owner_type": GraphIndexOwnerType.entity.rawValue, "owner_id": entity.id], createdAt: now, nextRunAt: now))
    try store.upsert(job: GraphJobV3(id: "job-high", graphID: "default", type: .indexRefresh, priority: 99, payload: ["owner_type": GraphIndexOwnerType.entity.rawValue, "owner_id": entity.id], createdAt: now, nextRunAt: now))
    let source = GraphExtractionSource(id: "unused", graphID: "default", sourceType: .manual, title: "unused", content: "unused", occurredAt: now)

    let result = try await GraphBackgroundJobRunner(store: store, extractor: BackgroundRunnerFakeExtractor(draft: GraphExtractionDraft(source: source))).runOnce(graphID: "default", now: now)

    #expect(result?.jobID == "job-high")
    #expect(result?.jobType == .indexRefresh)
    #expect(result?.outcome == .succeeded)
}

@Test func backgroundJobRunnerRunsAvailableJobsUntilLimit() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryBackgroundRunnerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let entity = GraphEntity(id: "entity", graphID: "default", name: "Graph Kernel", entityKind: .workObject, scope: .project)
    try store.upsert(entity: entity)
    try store.upsert(job: GraphJobV3(id: "job-1", graphID: "default", type: .indexRefresh, priority: 2, payload: ["owner_type": GraphIndexOwnerType.entity.rawValue, "owner_id": entity.id], createdAt: now, nextRunAt: now))
    try store.upsert(job: GraphJobV3(id: "job-2", graphID: "default", type: .indexRefresh, priority: 1, payload: ["owner_type": GraphIndexOwnerType.entity.rawValue, "owner_id": entity.id], createdAt: now, nextRunAt: now))
    let source = GraphExtractionSource(id: "unused", graphID: "default", sourceType: .manual, title: "unused", content: "unused", occurredAt: now)

    let results = try await GraphBackgroundJobRunner(store: store, extractor: BackgroundRunnerFakeExtractor(draft: GraphExtractionDraft(source: source))).runAvailable(graphID: "default", now: now, limit: 5)

    #expect(results.map(\.jobID) == ["job-1", "job-2"])
    #expect(results.allSatisfy { $0.outcome == .succeeded })
    #expect(try store.runnableJobs(graphID: "default", at: now).isEmpty)
}

@Test func backgroundJobRunnerSkipsUnsupportedJobTypesWithExplicitUnsupportedReason() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryBackgroundRunnerDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    try store.upsert(job: GraphJobV3(id: "job-confidence-decay", graphID: "default", type: .confidenceDecay, priority: 1, payload: [:], createdAt: now, nextRunAt: now))
    let source = GraphExtractionSource(id: "unused", graphID: "default", sourceType: .manual, title: "unused", content: "unused", occurredAt: now)

    let result = try await GraphBackgroundJobRunner(store: store, extractor: BackgroundRunnerFakeExtractor(draft: GraphExtractionDraft(source: source))).runOnce(graphID: "default", now: now)
    let storedJob = try store.job(id: "job-confidence-decay")
    let stored = try #require(storedJob)

    #expect(result?.jobID == "job-confidence-decay")
    #expect(result?.outcome == .skipped)
    #expect(result?.message == "Unsupported background job type: confidenceDecay")
    #expect(stored.status == .succeeded)
    #expect(stored.errorCode == "unsupported_job_type")
    #expect(stored.errorMessage == "Unsupported background job type: confidenceDecay")
}
