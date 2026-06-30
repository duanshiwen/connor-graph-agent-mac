import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func memoryOSUnifiedRetrievalSearchesAcrossAllLayersAndRanksHits() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSUnifiedRetrievalDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 4_000)
    let object = MemoryOSProvenanceObject(sourceType: .manual, sourceID: "source-1", title: "Elasticity note", content: "Supply demand elasticity changes with price sensitivity.", occurredAt: now)
    try store.upsert(provenance: object)
    let span = MemoryOSProvenanceSpan(id: "span-1", provenanceObjectID: object.id, text: object.content)
    try store.upsert(span: span)
    try store.upsert(captureEvent: MemoryOSCaptureEvent(id: "capture-1", provenanceObjectID: object.id, eventType: "manual", occurredAt: now, tokenEstimate: 10, metadata: ["span_id": span.id]))
    let node = MemoryOSNode(id: "node-1", stableKey: "knowledge:concept:elasticity-node", nodeType: "concept", name: "Elasticity", summary: "Operational fact node")
    try store.upsert(node: node)
    try store.upsert(statement: MemoryOSStatement(id: "statement-1", subjectID: node.id, predicate: "varies_with", text: "Elasticity varies with price sensitivity.", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: [span.id]))
    try store.upsert(belief: MemoryOSBelief(id: "knowledge-1", statement: "Elasticity is a reusable lens for price-response analysis.", domain: "economics", relatedObjectNames: "Elasticity", createdAt: now, updatedAt: now))
    try store.upsert(entity: MemoryOSEntity(id: "entity-1", stableKey: "economics:concept:elasticity", entityType: "concept", name: "Elasticity", aliases: ["price elasticity"], summary: "A concept for price-response analysis", confidence: 0.9))

    let service = SQLiteMemoryOSUnifiedRetrievalService(store: store)
    let hits = try service.search(MemoryOSRetrievalQuery(text: "elasticity", layers: MemoryOSRetrievalLayer.allCases, limit: 10))

    #expect(Set(hits.map(\.layer)).isSuperset(of: Set([.l0, .l1, .l2, .l3, .l4])))
    #expect(hits.first?.score ?? 0 >= hits.last?.score ?? 0)
    #expect(hits.contains { $0.recordID == "statement-1" && $0.evidenceRefs == ["span-1"] })
}

@Test func memoryOSUnifiedRetrievalExpandsL4ConceptDepth() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSUnifiedRetrievalDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 4_000)
    try store.upsert(entity: MemoryOSEntity(id: "entity-elasticity", stableKey: "economics:concept:elasticity", entityType: "concept", name: "Elasticity", summary: "Elasticity concept", confidence: 0.9))
    try store.upsert(entity: MemoryOSEntity(id: "entity-price", stableKey: "economics:parameter:price", entityType: "parameter", name: "Price", summary: "Price parameter", confidence: 0.9))
    try store.upsert(entity: MemoryOSEntity(id: "entity-market", stableKey: "economics:concept:market", entityType: "concept", name: "Market", summary: "Market concept", confidence: 0.9))
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "relation-1", entityID: "entity-elasticity", predicate: .influences, objectEntityID: "entity-price", text: "Elasticity varies with price.", assertionKind: .summarized, confidence: 0.88, validAt: now, committedAt: now))
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "relation-2", entityID: "entity-elasticity", predicate: .sameAs, objectEntityID: "entity-market", text: "Elasticity is treated as the same as this market concept in a fixture.", assertionKind: .summarized, confidence: 0.88, validAt: now, committedAt: now))

    let service = SQLiteMemoryOSUnifiedRetrievalService(store: store)
    let expansion = try service.expandL4(entityName: "Elasticity", depth: 1, limit: 10)

    #expect(expansion.map(\.recordID).contains("relation-1"))
    #expect(expansion.map(\.recordID).contains("relation-2"))
    #expect(expansion.first?.depth == 1)
    #expect(expansion.first?.recordID == "relation-2")
    #expect((expansion.first?.score ?? 0) > (expansion.first(where: { $0.recordID == "relation-1" })?.score ?? 0))
}

private func temporaryMemoryOSUnifiedRetrievalDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-unified-retrieval-\(UUID().uuidString).sqlite")
}
