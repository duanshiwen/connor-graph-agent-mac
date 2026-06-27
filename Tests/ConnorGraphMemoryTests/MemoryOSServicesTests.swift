import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryOSIngestionArchivesMeaningfulContentWithEvidence() {
    let service = MemoryOSIngestionService()
    let now = Date(timeIntervalSince1970: 1_000)
    let result = service.ingest(MemoryOSIngestionInput(sourceType: .chatMessage, sourceID: "m1", title: "Message", content: "Production memory requires evidence.", occurredAt: now, sessionID: "s1"), now: now)

    #expect(result.decision.action == .archive)
    #expect(result.provenanceObject?.contentHash.isEmpty == false)
    #expect(result.span?.provenanceObjectID == result.provenanceObject?.id)
    #expect(result.captureEvent?.provenanceObjectID == result.provenanceObject?.id)
}

@Test func memoryOSIngestionDiscardsEmptyContentWithAuditReason() {
    let result = MemoryOSIngestionService().ingest(MemoryOSIngestionInput(sourceType: .manual, title: "Empty", content: "", occurredAt: Date()))

    #expect(result.decision.action == .discard)
    #expect(result.decision.reason == "empty_content")
    #expect(result.provenanceObject == nil)
}

@Test func memoryOSIngestionArchivesShortNonEmptyContent() {
    let result = MemoryOSIngestionService().ingest(MemoryOSIngestionInput(sourceType: .manual, title: "Short", content: "好", occurredAt: Date()))

    #expect(result.decision.action == .archive)
    #expect(result.decision.reason == "archive_by_default_with_evidence")
    #expect(result.provenanceObject?.content == "好")
    #expect(result.span?.text == "好")
    #expect(result.captureEvent?.provenanceObjectID == result.provenanceObject?.id)
}

@Test func memoryOSTimeBlockBuilderSplitsAcrossDays() {
    let builder = MemoryOSTimeBlockBuilder(targetTokenLimit: 100, hardTokenLimit: 200)
    let day1 = Date(timeIntervalSince1970: 1_000)
    let day2 = Date(timeIntervalSince1970: 90_000)
    let events = [
        MemoryOSCaptureEvent(id: "e1", provenanceObjectID: "p1", eventType: "manual", occurredAt: day1, tokenEstimate: 10),
        MemoryOSCaptureEvent(id: "e2", provenanceObjectID: "p2", eventType: "manual", occurredAt: day2, tokenEstimate: 10)
    ]

    let blocks = builder.buildBlocks(from: events)

    #expect(blocks.count == 2)
}

@Test func memoryOSStatementValidatorRequiresEvidenceForTemporalStatements() {
    let statement = MemoryOSStatement(subjectID: "n1", predicate: "states", text: "No evidence")

    let issues = MemoryOSStatementValidator().validate(statement)

    #expect(issues.contains { $0.code == "missing_evidence" })
}

@Test func memoryOSProjectionServiceRanksLatestTemporalStatementsFirst() {
    let older = Date(timeIntervalSince1970: 1_000)
    let newer = Date(timeIntervalSince1970: 2_000)
    let oldStatement = MemoryOSStatement(id: "old", subjectID: "n", predicate: "p", text: "old", confidence: 0.99, validAt: older, committedAt: older, evidenceSpanIDs: ["s"])
    let newStatement = MemoryOSStatement(id: "new", subjectID: "n", predicate: "p", text: "new", confidence: 0.7, validAt: newer, committedAt: newer, evidenceSpanIDs: ["s"])

    let projection = MemoryOSProjectionService().currentProjection(statements: [oldStatement, newStatement])

    #expect(projection.first?.id == "new")
}

@Test func memoryOSBeliefValidatorRequiresEvidenceForTemporalBeliefProjections() {
    let belief = MemoryOSBelief(topic: "memory", statement: "Memory is production-grade", projectionKind: .summarized, confidence: 0.9)

    let issues = MemoryOSBeliefValidator().validate(belief)

    #expect(issues.contains { $0.code == "missing_belief_evidence" })
}

@Test func memoryOSEntityDisambiguationUsesStableKeyThenAlias() {
    let service = MemoryOSEntityDisambiguationService()
    let entity = MemoryOSEntity(stableKey: MemoryOSStableKeyBuilder.stableKey(type: "project", name: "Connor Memory OS"), entityType: "project", name: "Connor Memory OS", aliases: ["MemoryOS"])

    #expect(service.chooseExistingEntity(named: "Connor Memory OS", type: "project", candidates: [entity])?.id == entity.id)
    #expect(service.chooseExistingEntity(named: "MemoryOS", type: "project", candidates: [entity])?.id == entity.id)
}

@Test func memoryOSRecoveryDetectsExpiredLeasesAndComputesBackoff() {
    let service = MemoryOSRecoveryService()
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(service.shouldRecoverLease(status: .leased, leaseExpiresAt: now.addingTimeInterval(-1), now: now))
    #expect(!service.shouldRecoverLease(status: .succeeded, leaseExpiresAt: now.addingTimeInterval(-1), now: now))
    #expect(service.nextRetryDelay(attemptCount: 3) == 8)
}

@Test func memoryOSArtifactValidatorAcceptsL1UnifiedProjectionOutput() throws {
    let output = makeAcceptedL1UnifiedProjectionOutput()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let raw = String(data: try encoder.encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, artifactType: "memory_os_l1_unified_projection", schemaName: "MemoryOSL1UnifiedProjectionOutput", modelID: "test-model")

    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    #expect(validation.accepted)
    #expect(validation.normalizedRecordCount == 5)
}

@Test func memoryOSArtifactValidatorRejectsL1UnifiedKnowledgeCandidateWithoutAcceptedSignals() throws {
    var output = makeAcceptedL1UnifiedProjectionOutput()
    output.knowledgeCandidates[0].signalAssessment = MemoryOSKnowledgeSignalAssessment(signalQualityAccepted: true, reuseScopeAccepted: false, noveltyAccepted: true, structurabilityAccepted: true, reasons: ["Not reusable"])
    let raw = String(data: try JSONEncoder().encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, artifactType: "memory_os_l1_unified_projection", schemaName: "MemoryOSL1UnifiedProjectionOutput", modelID: "test-model")

    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    #expect(!validation.accepted)
    #expect(validation.issues.contains { $0.code == "knowledge_promotion_rejected" })
}

@Test func memoryOSArtifactValidatorRejectsProfilePreferenceWithoutPersonMetadata() throws {
    var output = makeAcceptedL1UnifiedProjectionOutput()
    output.operationalStatements[0].metadata = ["l2_fact_type": "profile_preference"]
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let raw = String(data: try encoder.encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, artifactType: "memory_os_l1_unified_projection", schemaName: "MemoryOSL1UnifiedProjectionOutput", modelID: "test-model")

    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    #expect(!validation.accepted)
    #expect(validation.issues.contains { $0.code == "missing_profile_person_metadata" })
}

@Test func memoryOSArtifactValidatorRejectsCurrentUserGenericAliases() throws {
    var output = makeAcceptedL1UnifiedProjectionOutput()
    output.operationalEntities[0] = GraphStructuredExtractedEntity(
        localID: "current_user",
        name: "Current User",
        entityKind: .personObject,
        scope: .personal,
        aliases: ["用户", "user"],
        summary: "Current user anchor",
        evidenceSpanIDs: ["span-1"],
        metadata: ["stable_key": "current_user", "person_role": "current_user"]
    )
    output.operationalStatements[0] = GraphStructuredExtractedStatement(
        explicitID: "stmt-1",
        subjectLocalID: "current_user",
        predicate: .prefers,
        objectLocalID: "current_user",
        statementText: "Current user prefers structured plans.",
        evidenceSpanIDs: ["span-1"],
        metadata: [
            "l2_fact_type": "profile_preference",
            "person_role": "current_user",
            "person_resolution": "resolved",
            "profile_dimension": "interaction_guidance",
            "evidence_quality": "user_explicit",
            "stability": "stable"
        ]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let raw = String(data: try encoder.encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, artifactType: "memory_os_l1_unified_projection", schemaName: "MemoryOSL1UnifiedProjectionOutput", modelID: "test-model")

    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    #expect(!validation.accepted)
    #expect(validation.issues.contains { $0.code == "current_user_generic_alias" })
}

@Test func memoryOSArtifactValidatorRejectsL1UnifiedConceptRelationWithoutRequiredMetadata() throws {
    var output = makeAcceptedL1UnifiedProjectionOutput()
    output.conceptRelations[0].metadata = [:]
    let raw = String(data: try JSONEncoder().encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, artifactType: "memory_os_l1_unified_projection", schemaName: "MemoryOSL1UnifiedProjectionOutput", modelID: "test-model")

    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    #expect(!validation.accepted)
    #expect(validation.issues.contains { $0.code == "missing_l4_relation_metadata" })
}

@Test func memoryOSArtifactValidatorRejectsL1UnifiedConceptRelationWithUnknownEntity() throws {
    var output = makeAcceptedL1UnifiedProjectionOutput()
    output.conceptRelations[0].objectLocalID = "missing-concept"
    let raw = String(data: try JSONEncoder().encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, artifactType: "memory_os_l1_unified_projection", schemaName: "MemoryOSL1UnifiedProjectionOutput", modelID: "test-model")

    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    #expect(!validation.accepted)
    #expect(validation.issues.contains { $0.code == "unknown_relation_object" })
}

private func makeAcceptedL1UnifiedProjectionOutput() -> MemoryOSL1UnifiedProjectionOutput {
    MemoryOSL1UnifiedProjectionOutput(
        operationalEntities: [
            GraphStructuredExtractedEntity(localID: "project", name: "Connor Memory OS", entityKind: .workObject, scope: .project, summary: "Local-first memory system", evidenceSpanIDs: ["span-1"])
        ],
        operationalStatements: [
            GraphStructuredExtractedStatement(explicitID: "stmt-1", subjectLocalID: "project", predicate: .hasGoal, objectLocalID: "project", statementText: "Connor Memory OS should project L1 into durable memory layers.", evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "Connor Memory OS should project L1 into L2, L3, and L4.")],
        knowledgeCandidates: [
            MemoryOSKnowledgeCandidate(
                id: "knowledge-1",
                title: "Memory layer projection discipline",
                claim: "A memory system can project one evidence-backed capture block into operational facts, reusable knowledge, and stable entities while preserving layer boundaries.",
                category: "internal/standards",
                knowledgeType: "standard",
                scope: "work-object",
                domain: "software-engineering",
                signalAssessment: MemoryOSKnowledgeSignalAssessment(signalQualityAccepted: true, reuseScopeAccepted: true, noveltyAccepted: true, structurabilityAccepted: true, reasons: ["Reusable Memory OS design rule"]),
                confidence: 0.91,
                evidenceStatementIDs: ["stmt-1"],
                evidenceSpanIDs: ["span-1"],
                relatedEntityIDs: ["concept-1"]
            )
        ],
        conceptEntities: [
            MemoryOSExtractedConceptEntity(localID: "concept-1", name: "L1 unified projection", conceptType: "memory_architecture_pattern", domain: "software-engineering", summary: "A single L1 extraction pass that can emit L2, L3, and L4 records.", evidenceSpanIDs: ["span-1"])
        ],
        conceptRelations: [
            MemoryOSExtractedConceptRelation(id: "rel-1", subjectLocalID: "concept-1", predicate: .relatedTo, objectLocalID: "concept-1", text: "L1 unified projection relates to layered memory records.", evidenceSpanIDs: ["span-1"], metadata: ["reason": "The concept describes layered memory projection discipline."])
        ],
        promotionDecisions: [
            MemoryOSL1PromotionDecision(candidateID: "knowledge-1", accepted: true, signalQualityAccepted: true, reuseScopeAccepted: true, noveltyAccepted: true, structurabilityAccepted: true, reasons: ["All filters pass"], evidenceStatementIDs: ["stmt-1"], evidenceSpanIDs: ["span-1"])
        ],
        confidence: 0.9,
        metadata: ["stage": "l1_unified_projection"]
    )
}
