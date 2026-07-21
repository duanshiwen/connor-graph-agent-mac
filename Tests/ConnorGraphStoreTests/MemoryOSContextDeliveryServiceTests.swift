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

@Test func recentContextReturnsOnlyL1AndL2OperationalMemory() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSContextDeliveryDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 42_000)
    try store.upsert(node: MemoryOSNode(id: "project-node", stableKey: "project:atlas", nodeType: "project", name: "Project Atlas"))
    try store.upsert(statement: MemoryOSStatement(id: "recent-state", subjectID: "project-node", predicate: "status", text: "Project Atlas is preparing its current release.", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: []))
    try store.upsert(belief: MemoryOSBelief(id: "knowledge-state", statement: "Project Atlas demonstrates reusable release governance.", domain: "engineering", relatedObjectNames: "Project Atlas", createdAt: now, updatedAt: now))
    try store.upsert(entity: MemoryOSEntity(id: "atlas-entity", stableKey: "project:atlas-stable", entityType: "project", name: "Project Atlas", summary: "Stable project knowledge", confidence: 0.9))

    let results = try MemoryOSContextDeliveryService(store: store).recentContext(terms: ["Project Atlas"])

    #expect(results.contains { $0.contains("preparing its current release") })
    #expect(!results.contains { $0.contains("reusable release governance") })
    #expect(!results.contains { $0.contains("Stable project knowledge") })
}

@Test func knowledgeContextDefaultsToOneHopAndHonorsExplicitDeeperTraversal() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSContextDeliveryDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 43_000)
    try store.upsert(node: MemoryOSNode(id: "operational-node", stableKey: "operational:seed", nodeType: "project", name: "Knowledge Seed"))
    try store.upsert(statement: MemoryOSStatement(id: "operational-state", subjectID: "operational-node", predicate: "status", text: "Knowledge Seed has a transient operational status.", confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: []))
    try store.upsert(belief: MemoryOSBelief(id: "knowledge-belief", statement: "Knowledge Seed supports durable graph reasoning.", domain: "knowledge", relatedObjectNames: "Knowledge Seed", createdAt: now, updatedAt: now))

    for index in 0...6 {
        try store.upsert(entity: MemoryOSEntity(id: "hop-\(index)", stableKey: "hop:\(index)", entityType: "concept", name: index == 0 ? "Knowledge Seed" : "Hop \(index)", summary: index == 0 ? "Durable graph seed" : "Entity at hop \(index)", confidence: 0.9))
    }
    for index in 0..<6 {
        try store.upsert(entityStatement: MemoryOSEntityStatement(id: "edge-\(index)", entityID: "hop-\(index)", predicate: .dependsOn, objectEntityID: "hop-\(index + 1)", text: "Hop \(index) depends on Hop \(index + 1).", assertionKind: .summarized, confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: []))
    }
    let service = MemoryOSContextDeliveryService(store: store)
    let defaultResults = try service.knowledgeContext(terms: ["Knowledge Seed"])
    let deeperResults = try service.knowledgeContext(terms: ["Knowledge Seed"], l4Depth: 5)

    #expect(defaultResults.contains { $0.contains("durable graph reasoning") })
    #expect(!defaultResults.contains { $0.contains("Hop 1") && $0.contains("Hop 2") })
    #expect(deeperResults.contains { $0.contains("Hop 4") && $0.contains("Hop 5") })
    #expect(!deeperResults.contains { $0.contains("Hop 5") && $0.contains("Hop 6") })
    #expect(!deeperResults.contains { $0.contains("transient operational status") })
    #expect(deeperResults.allSatisfy { !$0.hasPrefix("「") && !$0.hasPrefix("{") })
    #expect(Set(deeperResults).count == deeperResults.count)
}

private func temporaryMemoryOSContextDeliveryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-context-delivery-\(UUID().uuidString).sqlite")
}
