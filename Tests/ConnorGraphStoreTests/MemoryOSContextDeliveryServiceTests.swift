import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func memoryOSContextDeliverySearchesAndExpandsL4ForContextPackage() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSContextDeliveryDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 40_000)
    let object = MemoryOSProvenanceObject(sourceType: .manual, sourceID: "source-context", title: "Memory OS design", content: "Connor Memory OS uses L4 stable entities and context delivery packages.", occurredAt: now)
    try store.upsert(provenance: object)
    let span = MemoryOSProvenanceSpan(id: "span-context", provenanceObjectID: object.id, text: object.content)
    try store.upsert(span: span)
    try store.upsert(entity: MemoryOSEntity(id: "entity-memory-os", stableKey: "system:connor-memory-os", entityType: "system", name: "Connor Memory OS", summary: "Background memory infrastructure", confidence: 0.95))
    try store.upsert(entity: MemoryOSEntity(id: "entity-l4", stableKey: "layer:l4", entityType: "memory_layer", name: "L4 Stable Entity / Concept Layer", summary: "Stores stable entities and concepts", confidence: 0.95))
    try store.upsert(entityStatement: MemoryOSEntityStatement(id: "relation-l4", entityID: "entity-memory-os", predicate: .hasPart, objectEntityID: "entity-l4", text: "Connor Memory OS contains L4 Stable Entity / Concept Layer.", assertionKind: .summarized, confidence: 0.92, validAt: now, committedAt: now, evidenceSpanIDs: [span.id]))

    let service = MemoryOSContextDeliveryService(store: store)
    let package = try service.context(MemoryOSContextRequest(
        query: "Connor Memory OS L4 stable entities",
        taskIntent: .explainRelationship,
        layers: [.l4],
        graphPolicy: MemoryOSGraphExpansionPolicy(enabled: true, maxDepth: 1, maxEdgesPerSeed: 5, expansionStrategy: .entityNeighborhood),
        budget: MemoryOSContextBudget(maxContextCharacters: 4_000, maxBlocks: 8, maxEntityCards: 4, maxRelationCards: 8, maxEvidenceCards: 4, maxEvidenceRefsPerBlock: 2),
        referenceTime: now,
        language: .en
    ), generatedAt: now)

    #expect(package.rawRetrieval.initialHitCount >= 1)
    #expect(package.rawRetrieval.expandedRelationCount >= 1)
    #expect(package.entities.contains { $0.entityID == "entity-memory-os" })
    #expect(package.relations.contains { $0.id == "relation-l4" })
    #expect(package.contextText.contains("L4 Stable Entity"))
}

@Test func memoryOSContextDeliverySkipsGraphExpansionWhenPolicyDisabled() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSContextDeliveryDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 41_000)
    try store.upsert(entity: MemoryOSEntity(id: "entity-memory-os", stableKey: "system:connor-memory-os", entityType: "system", name: "Connor Memory OS", summary: "Background memory infrastructure", confidence: 0.95))

    let service = MemoryOSContextDeliveryService(store: store)
    let package = try service.context(MemoryOSContextRequest(
        query: "Connor Memory OS",
        taskIntent: .answerQuestion,
        layers: [.l4],
        graphPolicy: MemoryOSGraphExpansionPolicy(enabled: false, maxDepth: 0, maxEdgesPerSeed: 0, expansionStrategy: .none),
        referenceTime: now,
        language: .en
    ), generatedAt: now)

    #expect(package.rawRetrieval.initialHitCount >= 1)
    #expect(package.rawRetrieval.expandedRelationCount == 0)
    #expect(package.diagnostics.contains { $0.kind == .expansionSkipped })
}

@Test func flatContextFallsBackToSQLiteWhenSearchKernelNil() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSContextDeliveryDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 42_000)
    try store.upsert(entity: MemoryOSEntity(id: "entity-fallback", stableKey: "test:fallback", entityType: "system", name: "Fallback Test Entity", summary: "Tests SQLite fallback", confidence: 0.9))

    // Without searchKernel → should use SQLite FTS5 and still return results
    let service = MemoryOSContextDeliveryService(store: store, searchKernel: nil)
    let results = try service.flatContext(terms: ["Fallback Test Entity"])
    #expect(!results.isEmpty)
    #expect(results.contains { $0.contains("Fallback Test Entity") })
}

@Test func flatContextAcceptsSearchKernelParameter() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSContextDeliveryDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 43_000)
    try store.upsert(entity: MemoryOSEntity(id: "entity-kernel", stableKey: "test:kernel", entityType: "concept", name: "Kernel Integration", summary: "Tests Tantivy search kernel", confidence: 0.95))

    // Verify that searchKernel parameter is accepted (nil = fallback to SQLite)
    let serviceWithKernel = MemoryOSContextDeliveryService(store: store, searchKernel: nil)
    let results = try serviceWithKernel.flatContext(terms: ["Kernel Integration"])
    #expect(!results.isEmpty)
    #expect(results.contains { $0.contains("Kernel Integration") })

    // Verify default init still works (backward compatibility)
    let serviceDefault = MemoryOSContextDeliveryService(store: store)
    let resultsDefault = try serviceDefault.flatContext(terms: ["Kernel Integration"])
    #expect(!resultsDefault.isEmpty)
}

private func temporaryMemoryOSContextDeliveryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-context-delivery-\(UUID().uuidString).sqlite")
}
