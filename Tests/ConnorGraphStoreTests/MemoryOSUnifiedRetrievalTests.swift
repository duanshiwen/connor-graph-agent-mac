import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func memoryOSRetrievalDefaultsToDepthOneAndAllowsConfiguredDepthSix() {
    #expect(MemoryOSRetrievalQuery(text: "memory").depth == 1)
    #expect(MemoryOSGraphExpansionPolicy(maxDepth: 6).maxDepth == 6)
}

@Test func memoryOSRetrievalSortsByEffectiveTimeThenScoreAndStableID() {
    let hits = [
        MemoryOSRetrievalHit(layer: .l2, recordID: "missing", title: "missing", score: 100),
        MemoryOSRetrievalHit(layer: .l2, recordID: "b", title: "b", score: 2, metadata: ["effective_updated_at": "2026-07-20T10:00:00Z"]),
        MemoryOSRetrievalHit(layer: .l2, recordID: "a", title: "a", score: 2, metadata: ["effective_updated_at": "2026-07-20T10:00:00Z"]),
        MemoryOSRetrievalHit(layer: .l2, recordID: "older", title: "older", score: 50, metadata: ["effective_updated_at": "2026-07-19T10:00:00Z"]),
        MemoryOSRetrievalHit(layer: .l2, recordID: "higher", title: "higher", score: 3, metadata: ["effective_updated_at": "2026-07-20T10:00:00Z"])
    ]

    let sorted = hits.sorted(by: SQLiteMemoryOSUnifiedRetrievalService.isOrderedBefore)

    #expect(sorted.map(\.recordID) == ["higher", "a", "b", "older", "missing"])
}

@Test func memoryOSRetrievalExposesTemporalStatusSemantics() {
    let conflicted = MemoryOSRetrievalHit(layer: .l3, recordID: "conflict", title: "conflict", metadata: ["status": "conflicted"])
    let unspecified = MemoryOSRetrievalHit(layer: .l3, recordID: "active", title: "active")
    #expect(conflicted.temporalStatus == .conflicted)
    #expect(unspecified.temporalStatus == .active)
}

@Test func memoryOSUnifiedRetrievalSearchesAcrossAllLayersAndRanksHits() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSUnifiedRetrievalDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 4_000)
    let object = MemoryOSProvenanceObject(sourceType: .manual, sourceID: "source-1", title: "Elasticity note", content: "Supply demand elasticity changes with price sensitivity.", occurredAt: now, ingestedAt: now)
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
    #expect(hits.contains { $0.layer == .l0 && $0.metadata["updated_at"] == iso8601(now) })
    #expect(hits.contains { $0.layer == .l1 && $0.metadata["updated_at"] == iso8601(now) })
    #expect(hits.contains { $0.recordID == "statement-1" && $0.metadata["updated_at"] == iso8601(now) })
    #expect(hits.contains { $0.recordID == "knowledge-1" && $0.metadata["updated_at"] == iso8601(now) })
    #expect(hits.contains { $0.recordID == "entity-1" && $0.metadata["updated_at"]?.isEmpty == false })
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
    #expect(expansion.first(where: { $0.recordID == "relation-1" })?.updatedAt == iso8601(now))
}

@Test func memoryOSL4ExpansionPreservesCompletePathOrderAtIndirectDepth() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSUnifiedRetrievalDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 4_500)
    for index in 0...2 {
        try store.upsert(entity: MemoryOSEntity(id: "path-entity-\(index)", stableKey: "path:\(index)", entityType: "concept", name: index == 0 ? "Path Seed" : "Path Entity \(index)", confidence: 0.9))
    }
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "path-edge-1", entityID: "path-entity-0", predicate: .dependsOn, objectEntityID: "path-entity-1", text: "Path Seed depends on Path Entity 1.", assertionKind: .summarized, confidence: 0.9, validAt: now, committedAt: now))
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "path-edge-2", entityID: "path-entity-1", predicate: .dependsOn, objectEntityID: "path-entity-2", text: "Path Entity 1 depends on Path Entity 2.", assertionKind: .summarized, confidence: 0.9, validAt: now, committedAt: now))

    let expansion = try SQLiteMemoryOSUnifiedRetrievalService(store: store).expandL4(entityName: "Path Seed", depth: 2, limit: 10)
    let indirect = try #require(expansion.first { $0.recordID == "path-edge-2" })

    #expect(indirect.depth == 2)
    #expect(indirect.pathRecordIDs == ["path-edge-1", "path-edge-2"])
}

@Test func memoryOSUnifiedRetrievalReturnsUpdatedAtForL4StatementHits() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSUnifiedRetrievalDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 4_000)
    try store.upsert(entity: MemoryOSEntity(id: "entity-elasticity", stableKey: "economics:concept:elasticity", entityType: "concept", name: "Elasticity", summary: "Elasticity concept", confidence: 0.9))
    try store.upsert(entity: MemoryOSEntity(id: "entity-price", stableKey: "economics:parameter:price", entityType: "parameter", name: "Price", summary: "Price parameter", confidence: 0.9))
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "relation-1", entityID: "entity-elasticity", predicate: .influences, objectEntityID: "entity-price", text: "Elasticity updated-at relation varies with price.", assertionKind: .summarized, confidence: 0.88, validAt: now, committedAt: now))

    let service = SQLiteMemoryOSUnifiedRetrievalService(store: store)
    let hits = try service.search(MemoryOSRetrievalQuery(text: "updated-at", layers: [.l4], limit: 10))

    #expect(hits.contains { $0.recordID == "relation-1" && $0.metadata["updated_at"] == iso8601(now) })
}

@Test(arguments: [
    "Annie Friend",
    "Annie,Friend",
    "Annie，Friend",
    "Annie;Friend",
    "Annie；Friend",
    "Annie、Friend",
    "Annie|Friend",
    "Annie｜Friend",
    "Annie\nFriend"
])
func memoryOSUnifiedRetrievalL1UsesBroadTermsAcrossSeparators(_ query: String) throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSUnifiedRetrievalDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 5_000)
    let object = MemoryOSProvenanceObject(
        id: "annie-source",
        sourceType: .manual,
        sourceID: "source-annie",
        title: "Invitation note",
        content: "Annie received the product invitation.",
        occurredAt: now,
        ingestedAt: now
    )
    try store.upsert(provenance: object)
    try store.upsert(captureEvent: MemoryOSCaptureEvent(
        id: "annie-capture",
        provenanceObjectID: object.id,
        eventType: "manual",
        occurredAt: now,
        tokenEstimate: 8
    ))

    let hits = try SQLiteMemoryOSUnifiedRetrievalService(store: store).search(
        MemoryOSRetrievalQuery(text: query, layers: [.l1], limit: 10)
    )

    #expect(hits.contains { $0.recordID == "annie-capture" })
}

@Test func memoryOSUnifiedRetrievalL1DoesNotRequireEveryExpansionTerm() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSUnifiedRetrievalDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 5_100)
    let object = MemoryOSProvenanceObject(
        id: "annie-multilingual-source",
        sourceType: .manual,
        sourceID: "source-annie-multilingual",
        title: "Annie note",
        content: "A product invitation was prepared.",
        occurredAt: now,
        ingestedAt: now
    )
    try store.upsert(provenance: object)
    try store.upsert(captureEvent: MemoryOSCaptureEvent(
        id: "annie-multilingual-capture",
        provenanceObjectID: object.id,
        eventType: "manual",
        occurredAt: now,
        tokenEstimate: 8
    ))

    let hits = try SQLiteMemoryOSUnifiedRetrievalService(store: store).search(
        MemoryOSRetrievalQuery(text: "Annie 朋友 friend", layers: [.l1], limit: 10)
    )

    #expect(hits.contains { $0.recordID == "annie-multilingual-capture" })
}

private func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func temporaryMemoryOSUnifiedRetrievalDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-unified-retrieval-\(UUID().uuidString).sqlite")
}
