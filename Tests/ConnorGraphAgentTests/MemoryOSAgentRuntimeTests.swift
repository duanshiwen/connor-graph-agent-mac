import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore

@Test func memoryOSContextCompilerRanksItemsAndRespectsBudget() {
    let now = Date(timeIntervalSince1970: 1_000)
    let statement = MemoryOSStatement(id: "stmt", subjectID: "n", predicate: "requires", text: "Memory OS requires evidence-backed statements.", assertionKind: .observed, confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: ["span"])
    let belief = MemoryOSBelief(id: "belief", statement: "Production memory must be auditable.", domain: "knowledge-management", relatedObjectNames: "Semantic memory", createdAt: now, updatedAt: now)
    let entity = MemoryOSEntity(id: "entity", stableKey: "default:project:memory-os", entityType: "project", name: "Memory OS", summary: "Production memory architecture", confidence: 0.8)

    let contract = MemoryOSContextCompiler(tokenBudget: 100).compile(query: "memory", statements: [statement], beliefs: [belief], entities: [entity], now: now)

    #expect(contract.items.first?.id == "belief")
    #expect(contract.renderedText.contains("Production memory must be auditable."))
    #expect(contract.tokenEstimate <= 100)
}

@Test func memoryOSReadToolsRenderEntityProfile() {
    let entity = MemoryOSEntity(stableKey: "default:project:memory-os", entityType: "project", name: "Memory OS", aliases: ["MemoryOS"], summary: "Stable memory system")

    let text = MemoryOSReadTools().renderEntityProfile(entity)

    #expect(text.contains("Memory OS"))
    #expect(text.contains("MemoryOS"))
}

@Test func memoryOSWriteToolsCreateEvidenceBackedObservation() {
    let now = Date(timeIntervalSince1970: 1_000)
    let statement = MemoryOSWriteTools().makeObservation(subjectID: "node", predicate: "requires", text: "Evidence is required.", evidenceSpanIDs: ["span"], now: now)

    #expect(statement.assertionKind == .observed)
    #expect(statement.evidenceSpanIDs == ["span"])
    #expect(statement.validAt == now)
}

@Test func memoryOSWriteToolsCreateProposedBelief() {
    let belief = MemoryOSWriteTools().proposeBelief(topic: "memory", statement: "Memory needs governance.", evidenceStatementIDs: ["stmt"])

    #expect(belief.domain == "memory")
    #expect(belief.statement == "Memory needs governance.")
}
