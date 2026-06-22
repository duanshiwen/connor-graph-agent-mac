import Foundation
import Testing
import ConnorGraphCore

@Test func memoryOSProductionDomainRepresentsAllLayers() {
    let now = Date(timeIntervalSince1970: 1_000)
    let l0 = MemoryOSProvenanceObject(sourceType: .manual, title: "L0", content: "evidence", occurredAt: now)
    let l1 = MemoryOSCaptureEvent(provenanceObjectID: l0.id, eventType: "manual", occurredAt: now)
    let l2 = MemoryOSStatement(subjectID: "node", predicate: "states", text: "statement", validAt: now, committedAt: now)
    let l3 = MemoryOSBelief(topic: "topic", statement: "belief")
    let l4 = MemoryOSEntity(stableKey: "default:concept:entity", entityType: "concept", name: "Entity")

    #expect(l0.sourceType == .manual)
    #expect(l1.processingState == .pending)
    #expect(l2.assertionKind == .observed)
    #expect(l3.projectionKind == .observed)
    #expect(l4.stableKey == "default:concept:entity")
}
