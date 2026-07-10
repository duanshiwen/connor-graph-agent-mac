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
                relatedEntityNames: ["供需弹性", "某参数"]
            )
        ],
        conceptEntities: [
            MemoryOSExtractedConceptEntity(name: "供需弹性", conceptType: "concept", domain: "economics", summary: "供给与需求变化敏感性的概念。", aliases: ["供需弹性空间"]),
            MemoryOSExtractedConceptEntity(name: "某参数", conceptType: "parameter", domain: "economics", summary: "影响供需弹性空间变化的参数。")
        ],
        conceptRelations: [
            MemoryOSExtractedConceptRelation(subjectName: "供需弹性", predicate: .influences, objectName: "某参数", text: "供需弹性空间会随着某参数变化而改变。", metadata: ["causal_basis": "Evidence states the elasticity space changes with the parameter."])
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
    #expect(batch.beliefs.first?.domain == "economics")
    #expect(batch.beliefs.first?.statement.contains("供需弹性") == true)
    #expect(batch.entities.contains { $0.entityType == "concept" && $0.name == "供需弹性" })
    #expect(batch.entities.contains { $0.entityType == "metric" && $0.name == "某参数" })
    #expect(batch.entities.contains { $0.stableKey.contains(":metric:") && $0.name == "某参数" })
    #expect(!batch.entities.contains { $0.entityType == "parameter" })
}

@Test func memoryOSProjectionServiceGracefullyDropsNoiseKnowledgeCandidate() throws {
    let output = MemoryOSKnowledgeExtractionOutput(
        knowledgeCandidates: [
            MemoryOSKnowledgeCandidate(
                id: "noise-candidate-1",
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

    #expect(result.accepted)
    #expect(result.validation.acceptanceModeKind == .degradedAccepted)
    #expect(result.validation.droppedRecordCount == 1)
    #expect(result.validation.issues.contains { $0.code == "knowledge_promotion_rejected" })
    #expect(result.batch?.beliefs.isEmpty == true)
}
