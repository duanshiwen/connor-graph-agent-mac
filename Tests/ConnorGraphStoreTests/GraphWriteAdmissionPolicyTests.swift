import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

private func admissionSource() -> GraphExtractionSource {
    GraphExtractionSource(
        id: "chat-1",
        graphID: "default",
        sourceType: .chat,
        title: "Preference",
        content: "诗闻 prefers tea.",
        occurredAt: Date(timeIntervalSince1970: 1_000)
    )
}

private func admissionDraft(
    entityConfidence: Double = 0.9,
    statementConfidence: Double = 0.9,
    statementMetadata: [String: String] = ["evidence_span_ids": "span-1"],
    entityName: String = "诗闻",
    entitySummary: String = ""
) -> GraphExtractionDraft {
    GraphExtractionDraft(
        source: admissionSource(),
        entities: [
            GraphExtractedEntityDraft(
                localID: "person",
                name: entityName,
                entityKind: .personObject,
                scope: .personal,
                summary: entitySummary,
                confidence: entityConfidence,
                metadata: ["evidence_span_ids": "span-1"]
            ),
            GraphExtractedEntityDraft(
                localID: "tea",
                name: "tea",
                entityKind: .lifeObject,
                scope: .personal,
                confidence: entityConfidence,
                metadata: ["evidence_span_ids": "span-1"]
            )
        ],
        statements: [
            GraphExtractedStatementDraft(
                subjectLocalID: "person",
                predicate: .prefers,
                objectLocalID: "tea",
                statementText: "诗闻 prefers tea.",
                confidence: statementConfidence,
                metadata: statementMetadata
            )
        ]
    )
}

@Test func admissionPolicyAutoCommitsHighConfidenceEvidenceBackedDraft() throws {
    let decision = try GraphWriteAdmissionPolicy().decide(draft: admissionDraft())

    #expect(decision.action == .autoCommit)
    #expect(decision.reasons == [.highConfidenceEvidenceBacked])
    #expect(decision.shouldCommit)
}

@Test func admissionPolicyHoldsLowConfidenceDraft() throws {
    let decision = try GraphWriteAdmissionPolicy().decide(draft: admissionDraft(statementConfidence: 0.4))

    #expect(decision.action == .hold)
    #expect(decision.reasons.contains(.lowStatementConfidence))
    #expect(!decision.shouldCommit)
}

@Test func admissionPolicyHoldsStatementsWithoutEvidence() throws {
    let decision = try GraphWriteAdmissionPolicy().decide(draft: admissionDraft(statementMetadata: [:]))

    #expect(decision.action == .hold)
    #expect(decision.reasons.contains(.missingStatementEvidence))
}

@Test func admissionPolicyDiscardsEmptyDraft() throws {
    let decision = try GraphWriteAdmissionPolicy().decide(draft: GraphExtractionDraft(source: admissionSource()))

    #expect(decision.action == .discard)
    #expect(decision.reasons == [.emptyDraft])
}

@Test func admissionPolicyCanAskForSensitivePersonalMemoryWhenConfigured() throws {
    let policy = GraphWriteAdmissionPolicy(askUserForSensitivePersonalMemory: true)
    let draft = admissionDraft(entityName: "OpenAI API key", entitySummary: "A secret credential")

    let decision = try policy.decide(draft: draft)

    #expect(decision.action == .askUser)
    #expect(decision.reasons.contains(.sensitivePersonalMemory))
}

@Test func admissionPolicyUsesPrecomputedEntityResolutionPlan() throws {
    let plan = GraphEntityResolutionPlan(entries: [
        GraphEntityResolutionPlanEntry(
            localID: "person",
            name: "诗闻",
            entityKind: .personObject,
            scope: .personal,
            action: .potentialDuplicate,
            matchedEntityID: "entity-existing-shiwen",
            reason: .fts
        )
    ])

    let decision = try GraphWriteAdmissionPolicy().decide(draft: admissionDraft(), resolutionPlan: plan)

    #expect(decision.action == .hold)
    #expect(decision.reasons.contains(.potentialDuplicateEntity))
}

@Test func admissionPolicyAsksForStatementConflictPreview() throws {
    let conflictPreview = GraphExtractionConflictPreview(conflicts: [
        GraphStatementConflict(
            incomingStatementID: "incoming",
            existingStatementID: "existing",
            type: .directContradiction,
            severity: .high,
            reason: "test"
        )
    ])

    let decision = try GraphWriteAdmissionPolicy().decide(
        draft: admissionDraft(),
        resolutionPlan: nil,
        conflictPreview: conflictPreview
    )

    #expect(decision.action == .askUser)
    #expect(decision.reasons.contains(.statementConflict))
}
