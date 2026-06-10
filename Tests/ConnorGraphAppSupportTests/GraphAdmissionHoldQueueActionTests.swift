import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private func temporaryAdmissionHoldDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func admissionHoldQueueRerunRequeuesPausedExtractionJobAndMarksInvestigating() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAdmissionHoldDatabaseURL().path)
    try store.migrate()
    try seedAdmissionHoldFixture(store: store)
    let repository = AppGraphAdmissionHoldQueueRepository(store: store)
    let now = Date(timeIntervalSince1970: 10)

    let result = try repository.rerunExtraction("hold-1", now: now)

    #expect(result.jobID == "job-1")
    #expect(result.status == .queued)
    let job = try #require(try store.job(id: "job-1"))
    #expect(job.status == .queued)
    #expect(job.nextRunAt == now)
    #expect(job.errorCode == nil)
    #expect(job.metadata["rerun_from_hold_item_id"] == "hold-1")
    #expect(try store.admissionHoldQueueItem(id: "hold-1")?.status == .investigating)
}

@Test func admissionHoldQueueRejectDismissesItemAndCancelsJob() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAdmissionHoldDatabaseURL().path)
    try store.migrate()
    try seedAdmissionHoldFixture(store: store)
    let repository = AppGraphAdmissionHoldQueueRepository(store: store)
    let now = Date(timeIntervalSince1970: 11)

    try repository.reject("hold-1", now: now)

    let item = try #require(try store.admissionHoldQueueItem(id: "hold-1"))
    #expect(item.status == .dismissed)
    #expect(item.resolvedAt == now)
    let job = try #require(try store.job(id: "job-1"))
    #expect(job.status == .cancelled)
    #expect(job.errorCode == "admission_hold_rejected")
}

@Test func admissionHoldQueueInspectEvidenceSummarizesTracePayload() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAdmissionHoldDatabaseURL().path)
    try store.migrate()
    try seedAdmissionHoldFixture(store: store)
    let repository = AppGraphAdmissionHoldQueueRepository(store: store)

    let inspection = try repository.inspectEvidence("hold-1")

    #expect(inspection.entityCount == 2)
    #expect(inspection.statementCount == 1)
    #expect(inspection.evidenceSpanCount == 1)
    #expect(inspection.missingEvidenceStatementCount == 0)
    #expect(inspection.preview.contains("span-1"))
}

@Test func admissionHoldQueueApproveCommitsHeldDraftAndResolvesItem() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAdmissionHoldDatabaseURL().path)
    try store.migrate()
    try seedAdmissionHoldFixture(store: store)
    let repository = AppGraphAdmissionHoldQueueRepository(store: store)
    let now = Date(timeIntervalSince1970: 12)

    let result = try repository.approveAndCommit("hold-1", now: now)

    #expect(result.committedEntityIDs == ["entity-default-person", "entity-default-tea"])
    #expect(result.committedStatementIDs.count == 1)
    #expect(try store.admissionHoldQueueItem(id: "hold-1")?.status == .resolved)
    #expect(try store.job(id: "job-1")?.status == .succeeded)
    #expect(try store.extractionTrace(id: result.replayTraceID)?.metadata["manual_approval"] == "true")
    #expect(try store.memoryChangeLogEntries(graphID: "default").first?.metadata["approved_hold_item_id"] == "hold-1")
}

private func seedAdmissionHoldFixture(store: SQLiteGraphKernelStore) throws {
    let source = GraphExtractionSource(
        id: "source-1",
        graphID: "default",
        sourceType: .chat,
        title: "Held source",
        content: "诗闻喜欢茶。",
        occurredAt: Date(timeIntervalSince1970: 1)
    )
    let job = GraphJobV3(
        id: "job-1",
        graphID: "default",
        type: .extraction,
        status: .paused,
        priority: 1,
        payload: GraphExtractionJobPayload(source: source).dictionary,
        errorCode: "admission_hold",
        errorMessage: "held by policy"
    )
    try store.upsert(job: job)
    try store.appendExtractionTrace(GraphExtractionTrace(
        id: "trace-1",
        jobID: "job-1",
        graphID: "default",
        sourceID: "source-1",
        sourceType: .chat,
        outcome: .held,
        admissionAction: .hold,
        admissionReasons: [.lowStatementConfidence],
        extractedEntityCount: 2,
        extractedStatementCount: 1,
        errorMessage: "held by policy",
        createdAt: Date(timeIntervalSince1970: 2)
    ))
    try store.appendExtractionTracePayload(GraphExtractionTracePayload(
        traceID: "trace-1",
        rawResponseJSON: heldExtractionJSON,
        normalizedJSON: heldExtractionJSON,
        createdAt: Date(timeIntervalSince1970: 2)
    ))
    try store.upsertAdmissionHoldQueueItem(GraphAdmissionHoldQueueItem(
        id: "hold-1",
        traceID: "trace-1",
        jobID: "job-1",
        graphID: "default",
        sourceID: "source-1",
        sourceType: .chat,
        reasons: [.lowStatementConfidence],
        recommendedActions: [.inspectEvidence, .rerunExtraction],
        message: "held by policy",
        createdAt: Date(timeIntervalSince1970: 3)
    ))
}

private let heldExtractionJSON = """
{
  "entities": [
    {
      "localID": "person",
      "name": "诗闻",
      "entityKind": "person_object",
      "scope": "personal",
      "canonicalClassID": null,
      "aliases": [],
      "summary": "当前用户",
      "confidence": 0.95,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    },
    {
      "localID": "tea",
      "name": "茶",
      "entityKind": "entity",
      "scope": "personal",
      "canonicalClassID": null,
      "aliases": [],
      "summary": "饮品",
      "confidence": 0.95,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    }
  ],
  "statements": [
    {
      "explicitID": null,
      "subjectLocalID": "person",
      "predicate": "PREFERS",
      "objectLocalID": "tea",
      "statementText": "诗闻喜欢茶。",
      "confidence": 0.95,
      "validAt": null,
      "referenceTime": null,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    }
  ],
  "evidenceSpans": [
    {
      "id": "span-1",
      "text": "诗闻喜欢茶。",
      "startOffset": 0,
      "endOffset": 6
    }
  ],
  "warnings": [],
  "confidence": 0.95,
  "metadata": {}
}
"""
