import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryOSProjectionServiceBuildsL2L3L4BatchFromAcceptedArtifact() throws {
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
    #expect(batch.beliefs.count == 1)
    #expect(batch.statements.first?.evidenceSpanIDs == ["span-1"])
    #expect(batch.beliefs.first?.status == .observed)
    #expect(batch.entities.contains { $0.stableKey == "personal:person_object:诗闻" })
}

@Test func memoryOSProjectionServiceDoesNotProjectRejectedArtifact() throws {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "a", name: "A"),
            GraphStructuredExtractedEntity(localID: "b", name: "B")
        ],
        statements: [
            GraphStructuredExtractedStatement(subjectLocalID: "a", predicate: .relatedTo, objectLocalID: "b", statementText: "No evidence.")
        ]
    )
    let raw = String(data: try JSONEncoder().encode(output), encoding: .utf8)!
    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, modelID: "test-model")
    let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    let result = MemoryOSProjectionService().projectionBatch(from: artifact, validation: validation)

    let rejected = result.validation
    #expect(!result.accepted)
    #expect(!rejected.accepted)
    #expect(rejected.issues.contains { $0.code == "schema_validation_failed" })
}
