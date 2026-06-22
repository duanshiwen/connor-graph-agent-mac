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

@Test func memoryOSStatementValidatorRequiresEvidenceForObservedStatements() {
    let statement = MemoryOSStatement(subjectID: "n1", predicate: "states", text: "No evidence", status: .observed)

    let issues = MemoryOSStatementValidator().validate(statement)

    #expect(issues.contains { $0.code == "missing_evidence" })
}

@Test func memoryOSProjectionServiceRanksConfirmedStatementsFirst() {
    let now = Date(timeIntervalSince1970: 1_000)
    let observed = MemoryOSStatement(id: "observed", subjectID: "n", predicate: "p", text: "observed", status: .observed, confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: ["s"])
    let confirmed = MemoryOSStatement(id: "confirmed", subjectID: "n", predicate: "p", text: "confirmed", status: .confirmed, confidence: 0.7, validAt: now, committedAt: now, evidenceSpanIDs: ["s"])

    let projection = MemoryOSProjectionService().currentProjection(statements: [observed, confirmed])

    #expect(projection.first?.id == "confirmed")
}

@Test func memoryOSBeliefValidatorRequiresEvidenceForConfirmedBeliefs() {
    let belief = MemoryOSBelief(topic: "memory", statement: "Memory is production-grade", status: .userConfirmed, confidence: 0.9)

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
