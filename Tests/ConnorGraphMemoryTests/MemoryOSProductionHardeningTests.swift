import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryOSLLMArtifactValidatorAcceptsEvidenceBackedStructuredOutput() throws {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "person-1", name: "诗闻", evidenceSpanIDs: ["span-1"]),
            GraphStructuredExtractedEntity(localID: "project-1", name: "Connor Memory OS", evidenceSpanIDs: ["span-1"])
        ],
        statements: [
            GraphStructuredExtractedStatement(subjectLocalID: "person-1", predicate: .relatedTo, objectLocalID: "project-1", statementText: "诗闻正在推进 Connor Memory OS H3。", evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "诗闻正在推进 Connor Memory OS H3。")]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let raw = String(data: try encoder.encode(output), encoding: .utf8)!

    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, modelID: "test-model", queueItemID: "queue-1")
    let result = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    #expect(result.accepted)
    #expect(result.normalizedRecordCount == 3)
    #expect(result.issues.isEmpty)
    #expect(!artifact.contentHash.isEmpty)
}

@Test func memoryOSLLMArtifactValidatorAcceptsOperationalProjectionWithoutEvidence() throws {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "person-1", name: "诗闻"),
            GraphStructuredExtractedEntity(localID: "project-1", name: "Connor Memory OS")
        ],
        statements: [
            GraphStructuredExtractedStatement(subjectLocalID: "person-1", predicate: .relatedTo, objectLocalID: "project-1", statementText: "L2 working memory no longer requires evidence spans.")
        ],
        evidenceSpans: []
    )
    let raw = String(data: try JSONEncoder().encode(output), encoding: .utf8)!

    let artifact = MemoryOSArtifactEnvelopeService().envelope(rawContent: raw, modelID: "test-model")
    let result = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(artifact)

    #expect(result.accepted)
    #expect(result.issues.isEmpty)
}

@Test func memoryOSQueueTransitionRetriesThenDeadLettersWithBackoff() {
    let now = Date(timeIntervalSince1970: 1_000)
    let item = MemoryOSQueueItem(id: "queue-1", kind: "extract", attemptCount: 0, maxAttempts: 2, nextRunAt: now)
    let service = MemoryOSQueueTransitionService()

    let retry = service.markFailed(item, errorCode: "llm_schema_error", errorMessage: "Invalid JSON", now: now)
    #expect(retry.status == .retryScheduled)
    #expect(retry.attemptCount == 1)
    #expect(retry.nextRunAt > now)

    let dead = service.markFailed(retry, errorCode: "llm_schema_error", errorMessage: "Still invalid", now: now.addingTimeInterval(10))
    #expect(dead.status == .deadLetter)
    #expect(dead.attemptCount == 2)
    #expect(dead.lockedBy == nil)
    #expect(dead.leaseExpiresAt == nil)
}
