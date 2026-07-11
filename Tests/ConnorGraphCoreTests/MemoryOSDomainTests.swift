import Foundation
import Testing
import ConnorGraphCore

@Test func memoryOSStableKeyBuilderNormalizesEntityKeys() {
    let key = MemoryOSStableKeyBuilder.stableKey(type: "person", name: " Shiwen User ", scope: "personal")

    #expect(key == "personal:person:shiwen-user")
}

@Test func memoryOSDomainRoundTripsProvenanceObject() throws {
    let object = MemoryOSProvenanceObject(
        id: "prov-1",
        sourceType: .chatMessage,
        sourceID: "message-1",
        title: "User preference",
        content: "诗闻 prefers production-grade systems.",
        contentHash: "hash-1",
        occurredAt: Date(timeIntervalSince1970: 1_000),
        ingestedAt: Date(timeIntervalSince1970: 1_001),
        sessionID: "session-1",
        confidentiality: .personal,
        metadata: ["quality": "production"]
    )

    let data = try JSONEncoder().encode(object)
    let decoded = try JSONDecoder().decode(MemoryOSProvenanceObject.self, from: data)

    #expect(decoded == object)
}

@Test func memoryOSQueueItemCarriesProductionRecoveryFields() {
    let now = Date(timeIntervalSince1970: 2_000)
    let item = MemoryOSQueueItem(
        id: "queue-1",
        kind: "l2_processing",
        status: .leased,
        attemptCount: 2,
        maxAttempts: 5,
        nextRunAt: now,
        lockedAt: now,
        lockedBy: "worker-1",
        leaseExpiresAt: now.addingTimeInterval(60),
        idempotencyKey: "idem-1",
        payloadHash: "payload-hash"
    )

    #expect(item.status == .leased)
    #expect(item.attemptCount == 2)
    #expect(item.lockedBy == "worker-1")
    #expect(item.leaseExpiresAt != nil)
    #expect(item.idempotencyKey == "idem-1")
}

@Test func memoryOSEntitySupportsTemporalKernelFields() {
    let entity = MemoryOSEntity(
        stableKey: MemoryOSStableKeyBuilder.stableKey(type: "project", name: "Connor Memory OS"),
        entityType: "project",
        name: "Connor Memory OS",
        aliases: ["Memory OS"],
        summary: "Production memory system",
        confidence: 0.95,
        validFrom: Date(timeIntervalSince1970: 3_000)
    )

    #expect(entity.stableKey == "default:project:connor-memory-os")
    #expect(entity.aliases == ["Memory OS"])
    #expect(entity.validFrom != nil)
}

@Test func memoryOSL1UnifiedProjectionOutputRoundTripsOperationalKnowledgeAndConceptSections() throws {
    let output = MemoryOSL1UnifiedProjectionOutput(
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
                relatedEntityNames: ["L1 unified projection"]
            )
        ],
        conceptEntities: [
            MemoryOSExtractedConceptEntity(name: "L1 unified projection", conceptType: "memory_architecture_pattern", domain: "software-engineering", summary: "A single L1 extraction pass that can emit L2, L3, and L4 records.")
        ],
        conceptRelations: [
            MemoryOSExtractedConceptRelation(subjectName: "L1 unified projection", predicate: .hasPart, objectName: "L1 unified projection", text: "L1 unified projection produces layered memory records.")
        ],
        promotionDecisions: [
            MemoryOSL1PromotionDecision(candidateID: "knowledge-1", accepted: true, signalQualityAccepted: true, reuseScopeAccepted: true, noveltyAccepted: true, structurabilityAccepted: true, reasons: ["All filters pass"], evidenceStatementIDs: ["stmt-1"], evidenceSpanIDs: ["span-1"])
        ],
        warnings: [GraphStructuredExtractionWarning(id: "warn-1", code: "review", message: "reviewed")],
        metadata: ["stage": "l1_unified_projection"]
    )

    let data = try JSONEncoder().encode(output)
    let decoded = try JSONDecoder().decode(MemoryOSL1UnifiedProjectionOutput.self, from: data)

    #expect(decoded == output)
    #expect(decoded.operationalStatements.first?.explicitID == "stmt-1")
    #expect(decoded.knowledgeCandidates.first?.evidenceStatementIDs == ["stmt-1"])
    #expect(decoded.conceptEntities.first?.name == "L1 unified projection")
    #expect(decoded.promotionDecisions.first?.accepted == true)
    #expect(decoded.conceptRelations.first?.predicate == .hasPart)
}

@Test func memoryOSL4RelationPredicateRejectsUnknownJSONValues() throws {
    let validJSON = """
    {
      "subjectName": "memory-os",
      "predicate": "HAS_PART",
      "objectName": "l4",
      "text": "Memory OS has L4.",
      "metadata": {}
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(MemoryOSExtractedConceptRelation.self, from: validJSON)
    #expect(decoded.predicate == .hasPart)

    let invalidJSON = """
    {
      "subjectName": "memory-os",
      "predicate": "has_a",
      "objectName": "l4",
      "text": "Memory OS has L4.",
      "metadata": {}
    }
    """.data(using: .utf8)!

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(MemoryOSExtractedConceptRelation.self, from: invalidJSON)
    }
}

@Test func memoryOSEntityStatementCarriesTypedL4Predicate() throws {
    let statement = MemoryOSEntityStatement(
        id: "stmt-1",
        entityID: "entity-memory-os",
        predicate: .dependsOn,
        objectEntityID: "entity-l0",
        text: "Memory OS depends on provenance.",
        confidence: 0.9,
        evidenceSpanIDs: ["span-1"]
    )

    let data = try JSONEncoder().encode(statement)
    let decoded = try JSONDecoder().decode(MemoryOSEntityStatement.self, from: data)

    #expect(decoded.predicate == .dependsOn)
}

@Test func memoryOSAcceptanceModeTreatsGracefulModesAsAccepted() {
    #expect(MemoryOSAcceptanceMode.strictAccepted.isAccepted)
    #expect(MemoryOSAcceptanceMode.normalizedAccepted.isAccepted)
    #expect(MemoryOSAcceptanceMode.repairedAccepted.isAccepted)
    #expect(MemoryOSAcceptanceMode.degradedAccepted.isAccepted)
    #expect(!MemoryOSAcceptanceMode.rejected.isAccepted)
}

@Test func memoryOSArtifactValidationResultDefaultsAcceptanceModeFromAcceptedFlag() {
    let accepted = MemoryOSArtifactValidationResult(
        artifactID: "artifact-1",
        accepted: true,
        normalizedRecordCount: 3
    )
    let rejected = MemoryOSArtifactValidationResult(
        artifactID: "artifact-2",
        accepted: false
    )

    #expect(accepted.acceptanceModeKind == .strictAccepted)
    #expect(accepted.acceptedRecordCount == 3)
    #expect(rejected.acceptanceModeKind == .rejected)
    #expect(rejected.acceptedRecordCount == 0)
}

@Test func memoryOSValidationIssueExposesTypedSeverityAndDisposition() {
    let issue = MemoryOSValidationIssue(
        code: "separator_variant",
        message: "created by was normalized to CREATED_BY",
        severity: MemoryOSIssueSeverity.informational.rawValue,
        scope: "relation",
        disposition: MemoryOSIssueDisposition.normalizeAndKeep.rawValue,
        recordReference: "relation-1",
        repairHint: "Prefer canonical predicate names in future outputs."
    )

    #expect(issue.severityKind == .informational)
    #expect(issue.dispositionKind == .normalizeAndKeep)
    #expect(issue.scope == "relation")
    #expect(issue.recordReference == "relation-1")
}

@Test func memoryOSProjectionBuildResultDefaultsAcceptanceModeFromValidation() {
    let validation = MemoryOSArtifactValidationResult(
        artifactID: "artifact-1",
        accepted: true,
        acceptanceMode: MemoryOSAcceptanceMode.degradedAccepted.rawValue,
        normalizedRecordCount: 2,
        degradedRecordCount: 1
    )

    let result = MemoryOSProjectionBuildResult(
        accepted: true,
        validation: validation
    )

    #expect(result.acceptanceModeKind == .degradedAccepted)
}
