import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryEntityMergeDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func entityMergeReviewWorkerAutoMergesExactAliasDuplicate() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryEntityMergeDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let existing = GraphEntity(id: "existing", graphID: "default", name: "Agent OS", entityKind: .workObject, scope: .project, aliases: ["Agent Operating System"], confidence: 0.9)
    let incoming = GraphEntity(id: "incoming", graphID: "default", name: "Agent Operating System", entityKind: .workObject, scope: .project, confidence: 0.7)
    try store.upsert(entity: existing)
    try store.upsert(entity: incoming)
    try store.upsert(job: GraphJobV3(
        id: "job-merge-1",
        graphID: "default",
        type: .entityMergeReview,
        payload: ["incoming_entity_id": incoming.id, "existing_entity_id": existing.id],
        createdAt: now,
        nextRunAt: now
    ))

    let result = try GraphEntityMergeReviewWorker(store: store).runNext(graphID: "default", now: now)

    #expect(result?.action == .merged)
    let updatedIncoming = try #require(try store.entity(id: incoming.id))
    #expect(updatedIncoming.status == .superseded)
    #expect(updatedIncoming.supersededByEntityID == existing.id)
    #expect(updatedIncoming.metadata["merge_review_action"] == GraphEntityMergeReviewAction.merged.rawValue)
    #expect(try store.runnableJobs(graphID: "default", at: now).contains { $0.id == "job-merge-1" } == false)
}

@Test func entityMergeReviewWorkerPausesAmbiguousDuplicateForReview() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryEntityMergeDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let existing = GraphEntity(id: "existing", graphID: "default", name: "Agent OS", entityKind: .workObject, scope: .project, confidence: 0.8)
    let incoming = GraphEntity(id: "incoming", graphID: "default", name: "Agentic Runtime", entityKind: .workObject, scope: .project, confidence: 0.8)
    try store.upsert(entity: existing)
    try store.upsert(entity: incoming)
    try store.upsert(job: GraphJobV3(
        id: "job-merge-2",
        graphID: "default",
        type: .entityMergeReview,
        payload: ["incoming_entity_id": incoming.id, "existing_entity_id": existing.id],
        createdAt: now,
        nextRunAt: now
    ))

    let result = try GraphEntityMergeReviewWorker(store: store).runNext(graphID: "default", now: now)

    #expect(result?.action == .needsReview)
    #expect(try store.entity(id: incoming.id)?.status == .active)
    #expect(try store.runnableJobs(graphID: "default", at: now).contains { $0.id == "job-merge-2" } == false)
}

@Test func entityMergeReviewWorkerMarksJobFailedWhenEntityMissing() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryEntityMergeDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    try store.upsert(job: GraphJobV3(
        id: "job-merge-missing",
        graphID: "default",
        type: .entityMergeReview,
        payload: ["incoming_entity_id": "missing-incoming", "existing_entity_id": "missing-existing"],
        createdAt: now,
        nextRunAt: now
    ))

    let result = try GraphEntityMergeReviewWorker(store: store).runNext(graphID: "default", now: now)

    #expect(result?.action == .failed)
}
