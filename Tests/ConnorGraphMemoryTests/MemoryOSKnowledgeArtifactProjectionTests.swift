import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryOSProjectionServiceProjectsAcceptedKnowledgeArtifactToL3AndL4Concepts() throws {
    let now = Date(timeIntervalSince1970: 20)
    let output = MemoryOSKnowledgeExtractionOutput(
        knowledgeCandidates: [
            MemoryOSKnowledgeCandidate(
                id: "candidate-elasticity-1",
                title: "供需弹性空间与参数变化关系",
                claim: "在特定约束下，供需弹性空间会随着某参数变化而改变。",
                category: "economics",
                knowledgeType: "theory",
                scope: "general",
                domain: "economics",
                workObjectID: "economics-knowledge-base",
                signalAssessment: MemoryOSKnowledgeSignalAssessment(
                    signalQualityAccepted: true,
                    reuseScopeAccepted: true,
                    noveltyAccepted: true,
                    structurabilityAccepted: true,
                    reasons: ["Reusable theory claim."
                    ]
                ),
                confidence: 0.86,
                evidenceStatementIDs: ["stmt-theory-1"],
                evidenceSpanIDs: ["span-theory-1"],
                relatedEntityIDs: ["concept-elasticity", "parameter-x"]
            )
        ],
        conceptEntities: [
            MemoryOSExtractedConceptEntity(localID: "concept-elasticity", name: "供需弹性", conceptType: "concept", domain: "economics", summary: "供给与需求变化敏感性的概念。", aliases: ["供需弹性空间"], confidence: 0.91, evidenceSpanIDs: ["span-theory-1"]),
            MemoryOSExtractedConceptEntity(localID: "parameter-x", name: "某参数", conceptType: "parameter", domain: "economics", summary: "影响供需弹性空间变化的参数。", confidence: 0.82, evidenceSpanIDs: ["span-theory-1"])
        ],
        conceptRelations: [
            MemoryOSExtractedConceptRelation(subjectLocalID: "concept-elasticity", predicate: "varies_with", objectLocalID: "parameter-x", text: "供需弹性空间会随着某参数变化而改变。", confidence: 0.84, evidenceSpanIDs: ["span-theory-1"])
        ],
        evidenceSpans: [MemoryOSKnowledgeEvidenceSpan(id: "span-theory-1", text: "供需弹性空间会随着某参数变化。")]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let raw = String(data: try encoder.encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(
        rawContent: raw,
        artifactType: "memory_os_knowledge_extraction",
        schemaName: "MemoryOSKnowledgeExtractionOutput",
        modelID: "test-model"
    )
    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    let result = MemoryOSProjectionService().projectionBatch(from: artifact, validation: validation, now: now)

    guard result.accepted, let batch = result.batch else {
        Issue.record("Expected accepted knowledge projection batch")
        return
    }
    #expect(batch.beliefs.count == 1)
    #expect(batch.entities.count == 2)
    #expect(batch.entityStatements.count == 1)
    #expect(batch.statements.isEmpty)
    #expect(batch.beliefs.first?.topic == "economics:theory")
    #expect(batch.beliefs.first?.metadata["projection_reason"] == "knowledge_promotion_policy_accepted")
    #expect(batch.entities.contains { $0.entityType == "concept" && $0.name == "供需弹性" })
    #expect(batch.entities.contains { $0.entityType == "parameter" && $0.name == "某参数" })
}

@Test func memoryOSProjectionServiceRejectsKnowledgeArtifactWithNoiseCandidate() throws {
    let output = MemoryOSKnowledgeExtractionOutput(
        knowledgeCandidates: [
            MemoryOSKnowledgeCandidate(
                title: "张三喜欢吃杨梅",
                claim: "张三喜欢吃杨梅。",
                category: "personal",
                knowledgeType: "fact",
                scope: "personal",
                domain: "preference",
                signalAssessment: MemoryOSKnowledgeSignalAssessment(signalQualityAccepted: false, reuseScopeAccepted: false, noveltyAccepted: true, structurabilityAccepted: true),
                confidence: 0.99,
                evidenceStatementIDs: ["stmt-fact-1"]
            )
        ]
    )
    let raw = String(data: try JSONEncoder().encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, artifactType: "memory_os_knowledge_extraction", schemaName: "MemoryOSKnowledgeExtractionOutput", modelID: "test-model")
    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    let result = MemoryOSProjectionService().projectionBatch(from: artifact, validation: validation)

    #expect(!result.accepted)
    #expect(result.validation.issues.contains { $0.code == "knowledge_promotion_rejected" })
}
