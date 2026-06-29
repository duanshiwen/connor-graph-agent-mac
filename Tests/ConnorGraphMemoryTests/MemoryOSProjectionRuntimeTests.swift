import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryOSProjectionServiceBuildsL2AndL4BatchFromAcceptedFactArtifactWithoutL3Promotion() throws {
    let now = Date(timeIntervalSince1970: 2_000)
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "person-1", name: "诗闻", entityKind: .personObject, scope: .personal, aliases: ["Shiwen"], summary: "Current user", confidence: 0.95, evidenceSpanIDs: ["span-1"]),
            GraphStructuredExtractedEntity(localID: "project-1", name: "Connor Memory OS", entityKind: .workObject, scope: .project, summary: "Memory operating system", confidence: 0.93, evidenceSpanIDs: ["span-1"])
        ],
        statements: [
            GraphStructuredExtractedStatement(explicitID: "stmt-1", subjectLocalID: "person-1", predicate: .relatedTo, objectLocalID: "project-1", statementText: "诗闻正在推进 Connor Memory OS H4 projection runtime。", confidence: 0.94, evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "诗闻正在推进 Connor Memory OS H4 projection runtime。")]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let raw = String(data: try encoder.encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, modelID: "test-model", processingRunID: "run-1")
    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    let result = MemoryOSProjectionService().projectionBatch(from: artifact, validation: validation, now: now)

    guard result.accepted, let batch = result.batch else {
        Issue.record("Expected accepted projection batch")
        return
    }
    #expect(batch.artifactID == artifact.id)
    #expect(batch.nodes.count == 2)
    #expect(batch.statements.count == 1)
    #expect(batch.entities.count == 2)
    #expect(batch.entityStatements.count == 1)
    #expect(batch.beliefs.isEmpty)
    #expect(batch.statements.first?.evidenceSpanIDs == ["span-1"])
    #expect(batch.statements.first?.sourceArtifactID == artifact.id)
    #expect(batch.entities.contains { $0.stableKey == "personal:person_object:诗闻" })
}

@Test func memoryOSProjectionServiceDoesNotProjectRejectedArtifact() throws {
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: "{\"not\":\"a graph extraction artifact\"}", modelID: "test-model")
    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    let result = MemoryOSProjectionService().projectionBatch(from: artifact, validation: validation)

    let rejected = result.validation
    #expect(!result.accepted)
    #expect(!rejected.accepted)
    #expect(!rejected.issues.isEmpty)
}

@Test func memoryOSProjectionServiceBuildsL2L3AndL4BatchFromL1UnifiedProjectionArtifact() throws {
    let now = Date(timeIntervalSince1970: 2_000)
    let output = MemoryOSL1UnifiedProjectionOutput(
        operationalEntities: [
            GraphStructuredExtractedEntity(localID: "project", name: "Connor Memory OS", entityKind: .workObject, scope: .project, aliases: ["Memory OS"], summary: "Local-first memory system", evidenceSpanIDs: ["span-1"])
        ],
        operationalStatements: [
            GraphStructuredExtractedStatement(explicitID: "stmt-1", subjectLocalID: "project", predicate: .hasGoal, objectLocalID: "project", statementText: "Connor Memory OS should project L1 into durable memory layers.", confidence: 0.92, evidenceSpanIDs: ["span-1"])
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
                relatedEntityNames: ["concept-1"]
            )
        ],
        conceptEntities: [
            MemoryOSExtractedConceptEntity(name: "L1 unified projection", conceptType: "memory_architecture_pattern", domain: "software-engineering", summary: "A single L1 extraction pass that can emit L2, L3, and L4 records.")
        ],
        conceptRelations: [
            MemoryOSExtractedConceptRelation(subjectName: "L1 unified projection", predicate: .relatedTo, objectName: "L1 unified projection", text: "L1 unified projection relates to layered memory records.", metadata: ["reason": "The concept describes layered memory projection discipline."])
        ],
        promotionDecisions: [MemoryOSL1PromotionDecision(candidateID: "knowledge-1", accepted: true, signalQualityAccepted: true, reuseScopeAccepted: true, noveltyAccepted: true, structurabilityAccepted: true, evidenceStatementIDs: ["stmt-1"], evidenceSpanIDs: ["span-1"])]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let raw = String(data: try encoder.encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, artifactType: "memory_os_l1_unified_projection", schemaName: "MemoryOSL1UnifiedProjectionOutput", modelID: "test-model", processingRunID: "run-1")
    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    let result = MemoryOSProjectionService().projectionBatch(from: artifact, validation: validation, now: now)

    guard result.accepted, let batch = result.batch else {
        Issue.record("Expected accepted L1 unified projection batch")
        return
    }
    #expect(batch.nodes.count == 1)
    #expect(batch.statements.count == 1)
    #expect(batch.entities.count == 2)
    #expect(batch.entityStatements.count == 1)
    #expect(batch.beliefs.count == 1)
    #expect(batch.beliefs.contains { $0.domain == "software-engineering" })
    #expect(batch.entities.contains { $0.name == "Connor Memory OS" })
    #expect(batch.entities.contains { $0.name == "L1 unified projection" })
}
