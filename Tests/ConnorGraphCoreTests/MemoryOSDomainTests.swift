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
                relatedEntityIDs: ["concept-1"]
            )
        ],
        conceptEntities: [
            MemoryOSExtractedConceptEntity(localID: "concept-1", name: "L1 unified projection", conceptType: "memory_architecture_pattern", domain: "software-engineering", summary: "A single L1 extraction pass that can emit L2, L3, and L4 records.", evidenceSpanIDs: ["span-1"])
        ],
        conceptRelations: [
            MemoryOSExtractedConceptRelation(id: "rel-1", subjectLocalID: "concept-1", predicate: "produces", objectLocalID: "concept-1", text: "L1 unified projection produces layered memory records.", evidenceSpanIDs: ["span-1"])
        ],
        promotionDecisions: [
            MemoryOSL1PromotionDecision(candidateID: "knowledge-1", accepted: true, signalQualityAccepted: true, reuseScopeAccepted: true, noveltyAccepted: true, structurabilityAccepted: true, reasons: ["All filters pass"], evidenceStatementIDs: ["stmt-1"], evidenceSpanIDs: ["span-1"])
        ],
        warnings: [GraphStructuredExtractionWarning(id: "warn-1", code: "review", message: "reviewed")],
        confidence: 0.9,
        metadata: ["stage": "l1_unified_projection"]
    )

    let data = try JSONEncoder().encode(output)
    let decoded = try JSONDecoder().decode(MemoryOSL1UnifiedProjectionOutput.self, from: data)

    #expect(decoded == output)
    #expect(decoded.operationalStatements.first?.explicitID == "stmt-1")
    #expect(decoded.knowledgeCandidates.first?.evidenceStatementIDs == ["stmt-1"])
    #expect(decoded.conceptEntities.first?.localID == "concept-1")
    #expect(decoded.promotionDecisions.first?.accepted == true)
}
