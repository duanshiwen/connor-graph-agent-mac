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

@Test func governedGraphWriteCandidateCommitRecordsPermissionAndAuditTrail() async throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    let repository = AppGraphWriteCandidateRepository(store: store, permissionMode: .trustedWrite)
    let candidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createNode,
        proposedByRunID: "run-governed",
        rationale: "Create governed node",
        confidence: 0.95,
        payloadJSON: #"{"id":"node-governed","nodeType":"entity","canonicalName":"Governed Node","title":"Governed Node"}"#
    )
    try store.upsert(graphWriteCandidate: candidate)

    let approved = try await repository.approveGoverned(candidate)
    let result = try await repository.commitGoverned(approved)

    #expect(result.createdNodeIDs == ["node-governed"])
    let auditEvents = try store.agentAuditEvents(runID: "run-governed")
    #expect(auditEvents.map(\.eventType).contains(.permissionDecision))
    #expect(auditEvents.map(\.eventType).contains(.graphWriteCommitStarted))
    #expect(auditEvents.map(\.eventType).contains(.graphWriteCommitFinished))
    #expect(auditEvents.first { $0.eventType == .permissionDecision }?.decision?.outcome == .approved)
}

@Test func governedGraphWriteCandidateCommitDeniesReadOnlyPolicy() async throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    let repository = AppGraphWriteCandidateRepository(store: store, permissionMode: .readOnly)
    let candidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createNode,
        proposedByRunID: "run-read-only",
        rationale: "Should not commit in read-only mode",
        confidence: 0.8,
        payloadJSON: #"{"id":"node-denied","nodeType":"entity","canonicalName":"Denied Node","title":"Denied Node"}"#
    )

    let approved = try await repository.approveGoverned(candidate)
    do {
        _ = try await repository.commitGoverned(approved)
        Issue.record("Expected read-only policy to deny graph write commit")
    } catch GraphWriteCandidateCommitError.permissionDenied {
        #expect(try store.graphNodeV2(id: "node-denied") == nil)
        let auditEvents = try store.agentAuditEvents(runID: "run-read-only")
        #expect(auditEvents.map(\.eventType).contains(.permissionDecision))
        #expect(auditEvents.map(\.eventType).contains(.graphWriteCommitFailed))
        #expect(auditEvents.first { $0.eventType == .permissionDecision }?.decision?.outcome == .denied)
    }
}

@Test func graphWriteCandidateValidationFailsMissingReferencedNodesBeforeCommit() async throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    let repository = AppGraphWriteCandidateRepository(store: store, permissionMode: .trustedWrite)
    let candidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createFact,
        proposedByRunID: "run-validation",
        rationale: "Create fact with missing endpoints",
        confidence: 0.9,
        payloadJSON: #"{"sourceNodeID":"missing-source","targetNodeID":"missing-target","relation":"RELATED_TO","fact":"Missing source relates to missing target."}"#
    )
    try store.upsert(graphWriteCandidate: candidate)

    let validated = try await repository.validateGoverned(candidate)

    #expect(validated.validation.isValid == false)
    #expect(try store.graphWriteCandidate(id: candidate.id)?.status == .validationFailed)
    #expect(try store.graphWriteCandidate(id: candidate.id)?.validationErrors.contains { $0.contains("missing source node") } == true)
    let auditEvents = try store.agentAuditEvents(runID: "run-validation")
    #expect(auditEvents.map(\.eventType).contains(.graphWriteValidationStarted))
    #expect(auditEvents.map(\.eventType).contains(.graphWriteValidationFailed))
}
