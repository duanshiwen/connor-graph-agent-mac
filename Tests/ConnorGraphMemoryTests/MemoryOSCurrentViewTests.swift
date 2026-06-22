import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func memoryOSCurrentViewSelectsLatestTemporalStatementWithoutMutatingHistory() {
    let older = Date(timeIntervalSince1970: 1_000)
    let newer = Date(timeIntervalSince1970: 2_000)
    let old = MemoryOSStatement(id: "stmt-old", subjectID: "entity-shiwen", predicate: "current_direction", text: "心理咨询", confidence: 0.99, validAt: older, committedAt: older, evidenceSpanIDs: ["span-old"])
    let new = MemoryOSStatement(id: "stmt-new", subjectID: "entity-shiwen", predicate: "current_direction", text: "AI / Agent OS", confidence: 0.8, validAt: newer, committedAt: newer, evidenceSpanIDs: ["span-new"])

    let records = MemoryOSCurrentViewService().currentStatements([old, new], now: newer)

    #expect(records.count == 1)
    #expect(records.first?.selectedRecordID == "stmt-new")
    #expect(records.first?.value == "AI / Agent OS")
    #expect(records.first?.alternativeRecordIDs == ["stmt-old"])
    #expect(old.text == "心理咨询")
}

@Test func memoryOSCurrentViewReturnsDiagnosticOnlyForAmbiguousTemporalCandidates() {
    let now = Date(timeIntervalSince1970: 3_000)
    let first = MemoryOSBelief(id: "belief-a", topic: "product_route", statement: "B2B", confidence: 0.82, evidenceStatementIDs: ["stmt-a"], validAt: now, projectedAt: now)
    let second = MemoryOSBelief(id: "belief-b", topic: "product_route", statement: "consumer", confidence: 0.85, evidenceStatementIDs: ["stmt-b"], validAt: now.addingTimeInterval(60), projectedAt: now.addingTimeInterval(60))

    let records = MemoryOSCurrentViewService().currentBeliefs([first, second], now: now)

    #expect(records.count == 1)
    #expect(records.first?.selectedRecordID == "belief-b")
    #expect(records.first?.diagnostics.first?.kind == "ambiguous_current_value")
    #expect(records.first?.alternativeRecordIDs == ["belief-a"])
}

@Test func memoryOSCurrentEntityProfileIsDerivedFromTemporalEntityStatements() {
    let older = Date(timeIntervalSince1970: 1_000)
    let newer = Date(timeIntervalSince1970: 2_000)
    let old = MemoryOSEntityStatement(id: "entity-stmt-old", entityID: "entity-shiwen", predicate: "current_work", text: "心理咨询", confidence: 0.9, validAt: older, committedAt: older, evidenceSpanIDs: ["span-old"])
    let new = MemoryOSEntityStatement(id: "entity-stmt-new", entityID: "entity-shiwen", predicate: "current_work", text: "Agent OS", confidence: 0.8, validAt: newer, committedAt: newer, evidenceSpanIDs: ["span-new"])

    let profile = MemoryOSCurrentViewService().currentEntityProfile(entityID: "entity-shiwen", statements: [old, new], now: newer)

    #expect(profile.entityID == "entity-shiwen")
    #expect(profile.records.first?.selectedRecordID == "entity-stmt-new")
    #expect(profile.records.first?.value == "Agent OS")
}
