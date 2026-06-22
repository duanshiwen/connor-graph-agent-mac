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
