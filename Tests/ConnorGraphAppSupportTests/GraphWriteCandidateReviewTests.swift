import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func graphWriteCandidateReviewCommitsApprovedCreateNodeCandidate() throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    let repository = AppGraphWriteCandidateRepository(store: store)
    let candidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createNode,
        proposedByRunID: "run-1",
        rationale: "Create reviewed node",
        confidence: 0.9,
        payloadJSON: #"{"id":"node-reviewed","nodeType":"entity","canonicalName":"Reviewed Node","title":"Reviewed Node","summary":"A reviewed candidate node."}"#
    )
    try store.upsert(graphWriteCandidate: candidate)

    let approved = try repository.approve(candidate)
    let result = try repository.commit(approved)

    #expect(result.createdNodeIDs == ["node-reviewed"])
    #expect(try store.graphNodeV2(id: "node-reviewed")?.metadata["committedFromCandidateID"] == candidate.id)
    #expect(try store.graphWriteCandidate(id: candidate.id)?.status == .committed)
}

@Test func graphWriteCandidateReviewRejectsUnapprovedDirectCommit() throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    let service = GraphWriteCandidateCommitService()
    let candidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createNode,
        proposedByRunID: "run-1",
        rationale: "Must be approved first",
        confidence: 0.8,
        payloadJSON: #"{"nodeType":"entity","canonicalName":"Unsafe","title":"Unsafe"}"#
    )

    #expect(throws: GraphWriteCandidateCommitError.notApproved(candidate.id)) {
        _ = try service.commit(candidate, store: store)
    }
}
