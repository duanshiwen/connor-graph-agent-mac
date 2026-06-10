import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func graphWriteCandidateReviewCommitsApprovedCreateNodeThroughResolverBackedPath() throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    let repository = AppGraphWriteCandidateRepository(store: store)
    let candidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createNode,
        proposedByRunID: "run-1",
        rationale: "Create reviewed node",
        confidence: 0.9,
        payloadJSON: #"{"id":"reviewed","entityKind":"entity","name":"Reviewed Node","summary":"A reviewed candidate node."}"#
    )
    try store.upsert(graphWriteCandidate: candidate)

    let approved = try repository.approve(candidate)
    let result = try repository.commit(approved)

    #expect(result.createdEntityIDs == ["entity-default-reviewed"])
    #expect(try store.entity(id: "entity-default-reviewed")?.metadata["extraction_local_id"] == "reviewed")
    #expect(try store.writeCandidates(groupID: "default").first { $0.id == candidate.id }?.status == .committed)
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
        payloadJSON: #"{"entityKind":"entity","name":"Unsafe"}"#
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
        payloadJSON: #"{"id":"governed","entityKind":"entity","name":"Governed Node"}"#
    )
    try store.upsert(graphWriteCandidate: candidate)

    let approved = try await repository.approveGoverned(candidate)
    let result = try await repository.commitGoverned(approved)

    #expect(result.createdEntityIDs == ["entity-default-governed"])
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
        payloadJSON: #"{"id":"denied","entityKind":"entity","name":"Denied Node"}"#
    )

    let approved = try await repository.approveGoverned(candidate)
    do {
        _ = try await repository.commitGoverned(approved)
        Issue.record("Expected read-only policy to deny graph write commit")
    } catch GraphWriteCandidateCommitError.permissionDenied {
        #expect(try store.entity(id: "entity-default-denied") == nil)
        let auditEvents = try store.agentAuditEvents(runID: "run-read-only")
        #expect(auditEvents.map(\.eventType).contains(.permissionDecision))
        #expect(auditEvents.map(\.eventType).contains(.graphWriteCommitFailed))
        #expect(auditEvents.first { $0.eventType == .permissionDecision }?.decision?.outcome == .denied)
    }
}

@Test func graphWriteCandidateValidationFailsMissingReferencedEntitiesBeforeCommit() async throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    let repository = AppGraphWriteCandidateRepository(store: store, permissionMode: .trustedWrite)
    let candidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createFact,
        proposedByRunID: "run-validation",
        rationale: "Create fact with missing endpoints",
        confidence: 0.9,
        payloadJSON: #"{"sourceEntityID":"missing-source","targetEntityID":"missing-target","predicate":"RELATED_TO","statementText":"Missing source relates to missing target."}"#
    )
    try store.upsert(graphWriteCandidate: candidate)

    let validated = try await repository.validateGoverned(candidate)

    #expect(validated.validation.isValid == false)
    #expect(try store.writeCandidates(groupID: "default").first { $0.id == candidate.id }?.status == .validationFailed)
    #expect(try store.writeCandidates(groupID: "default").first { $0.id == candidate.id }?.validationErrors.contains { $0.contains("Missing graph entity") } == true)
    let auditEvents = try store.agentAuditEvents(runID: "run-validation")
    #expect(auditEvents.map(\.eventType).contains(.graphWriteValidationStarted))
    #expect(auditEvents.map(\.eventType).contains(.graphWriteValidationFailed))
}

@Test func graphWriteCandidateCreateFactReusesExistingEntitiesThroughResolverBackedPath() async throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    try store.upsert(entity: GraphEntity(id: "entity-a", graphID: "default", name: "Entity A", entityKind: .entity, scope: .project))
    try store.upsert(entity: GraphEntity(id: "entity-b", graphID: "default", name: "Entity B", entityKind: .entity, scope: .project))
    let repository = AppGraphWriteCandidateRepository(store: store, permissionMode: .trustedWrite)
    let candidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createFact,
        proposedByRunID: "run-fact",
        rationale: "Entity A relates to Entity B",
        confidence: 0.95,
        payloadJSON: #"{"subjectEntityID":"entity-a","objectEntityID":"entity-b","predicate":"RELATED_TO","statementText":"Entity A relates to Entity B."}"#
    )

    let approved = try await repository.approveGoverned(candidate)
    let result = try await repository.commitGoverned(approved)

    #expect(result.createdEntityIDs.isEmpty)
    #expect(result.createdStatementIDs.count == 1)
    let statements = try store.statements(graphID: "default")
    #expect(statements.contains { $0.subjectEntityID == "entity-a" && $0.objectEntityID == "entity-b" })
}

@Test func graphWriteCandidateAuditTimelineFiltersEventsByCandidateID() async throws {
    let store = try SQLiteGraphStore(path: ":memory:")
    try store.migrate()
    let repository = AppGraphWriteCandidateRepository(store: store, permissionMode: .trustedWrite)
    let candidate = GraphWriteCandidate(
        groupID: "default",
        kind: .createNode,
        proposedByRunID: "run-audit-timeline",
        rationale: "Create audited node",
        confidence: 0.9,
        payloadJSON: #"{"id":"audit","entityKind":"entity","name":"Audited Node"}"#
    )

    let approved = try await repository.approveGoverned(candidate)
    _ = try await repository.commitGoverned(approved)

    let timeline = try repository.loadAuditTimeline(for: candidate)
    #expect(timeline.map(\.title).contains("Candidate approved"))
    #expect(timeline.map(\.title).contains("Permission decision"))
    #expect(timeline.map(\.title).contains("Commit finished"))
    #expect(timeline.first { $0.title == "Commit finished" }?.severity == .success)
}
