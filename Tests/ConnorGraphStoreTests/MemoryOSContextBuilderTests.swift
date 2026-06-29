import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Test func memoryOSContextBuilderCreatesEntityRelationAndEvidenceBoundText() throws {
    let now = Date(timeIntervalSince1970: 20_000)
    let query = MemoryOSContextRequest(
        query: "Explain Connor Memory OS L4 relationships",
        taskIntent: .explainRelationship,
        layers: [.l2, .l3, .l4],
        budget: MemoryOSContextBudget(maxContextCharacters: 4_000, maxBlocks: 8, maxEntityCards: 4, maxRelationCards: 8, maxEvidenceCards: 4, maxEvidenceRefsPerBlock: 2),
        referenceTime: now,
        language: .en
    )
    let hits = [
        MemoryOSRetrievalHit(layer: .l4, recordID: "entity-memory-os", title: "Connor Memory OS", summary: "Background memory infrastructure", matchedText: "Connor Memory OS Background memory infrastructure", score: 2.0, evidenceRefs: ["span-entity"], provenanceRefs: ["object-entity"], entityRefs: ["entity-memory-os"], canReadRaw: false, canExpandDepth: true, metadata: ["entity_type": "system"]),
        MemoryOSRetrievalHit(layer: .l2, recordID: "statement-l2", title: "uses_layer", summary: "Connor Memory OS uses L4 for stable entities.", matchedText: "Connor Memory OS uses L4 for stable entities.", score: 1.7, evidenceRefs: ["span-l2"], provenanceRefs: ["object-l2"], entityRefs: ["entity-memory-os", "entity-l4"], metadata: ["confidence": "0.93"]),
        MemoryOSRetrievalHit(layer: .l3, recordID: "belief-l3", title: "memory-context-delivery", summary: "Graph memory should be delivered as evidence-bound context packages.", matchedText: "Graph memory should be delivered as evidence-bound context packages.", score: 1.4, evidenceRefs: ["statement-l2"], provenanceRefs: [], entityRefs: ["entity-memory-os"])
    ]
    let expansions = [
        "entity-memory-os": [
            MemoryOSL4ExpansionHit(recordID: "relation-1", sourceEntityID: "entity-memory-os", relatedEntityID: "entity-l4", predicate: MemoryOSL4RelationPredicate.hasPart.rawValue, text: "Connor Memory OS contains L4 Stable Entity / Concept Layer.", depth: 1, score: 1.0)
        ]
    ]

    let package = MemoryOSContextBuilder().build(request: query, hits: hits, expansions: expansions, generatedAt: now)

    #expect(package.taskIntent == .explainRelationship)
    #expect(package.rawRetrieval.initialHitCount == 3)
    #expect(package.rawRetrieval.expandedRelationCount == 1)
    #expect(package.entities.contains { $0.entityID == "entity-memory-os" && $0.kind == "system" })
    #expect(package.relations.contains { $0.id == "relation-1" && $0.sentence.contains("contains L4") })
    #expect(package.blocks.contains { $0.recordIDs.contains("statement-l2") && $0.evidenceRefs.contains("span-l2") })
    #expect(package.evidence.contains { $0.evidenceRef == "span-l2" })
    #expect(package.contextText.contains("Connor Memory OS"))
    #expect(package.contextText.contains("Evidence"))
    #expect(package.budgetReport.actualContextCharacters == package.contextText.count)
    #expect(package.qualitySignals.evidenceCoverage > 0)
}

@Test func memoryOSContextBuilderRespectsBudgetAndEmitsDiagnostic() throws {
    let request = MemoryOSContextRequest(
        query: "budget test",
        budget: MemoryOSContextBudget(maxContextCharacters: 160, maxBlocks: 2, maxEntityCards: 1, maxRelationCards: 1, maxEvidenceCards: 1, maxEvidenceRefsPerBlock: 1),
        referenceTime: Date(timeIntervalSince1970: 30_000),
        language: .en
    )
    let hits = (0..<5).map { index in
        MemoryOSRetrievalHit(layer: .l2, recordID: "statement-\(index)", title: "fact", summary: "A long operational fact number \(index) that should be budgeted.", matchedText: "A long operational fact number \(index) that should be budgeted and not all blocks should fit.", score: Double(10 - index), evidenceRefs: ["span-\(index)"], provenanceRefs: [], entityRefs: ["entity-\(index)"])
    }

    let package = MemoryOSContextBuilder().build(request: request, hits: hits, generatedAt: request.referenceTime)

    #expect(package.blocks.count <= 2)
    #expect(package.contextText.count > 160) // No text truncation — full content is preserved
    #expect(package.diagnostics.contains { $0.kind == .budgetTruncated })
    #expect(package.budgetReport.truncatedBlockCount > 0)
}

@Test func buildFlatStringsFiltersSelfReferencingRelations() throws {
    let hits: [MemoryOSRetrievalHit] = [
        MemoryOSRetrievalHit(layer: .l4, recordID: "entity-a", title: "社会技术系统", summary: "A sociotechnical system.", matchedText: "", score: 1.0, entityRefs: ["entity-a"], metadata: ["entity_type": "concept"])
    ]
    let expansions: [String: [MemoryOSL4ExpansionHit]] = [
        "entity-a": [
            MemoryOSL4ExpansionHit(recordID: "self-ref", sourceEntityID: "entity-a", relatedEntityID: "entity-a", predicate: MemoryOSL4RelationPredicate.subclassOf.rawValue, text: "", depth: 1, score: 1.0),
            MemoryOSL4ExpansionHit(recordID: "valid", sourceEntityID: "entity-a", relatedEntityID: "entity-b", predicate: MemoryOSL4RelationPredicate.hasPart.rawValue, text: "", depth: 1, score: 1.0)
        ]
    ]

    let result = MemoryOSContextBuilder().buildFlatStrings(hits: hits, expansions: expansions, extraEntityNames: ["entity-b": "信息系统"])

    #expect(result.contains { $0.contains("has part") && $0.contains("信息系统") })
    #expect(!result.contains { $0.contains("subclass of") && $0.components(separatedBy: "社会技术系统").count > 2 })
}

@Test func buildFlatStringsFiltersNilTargetRelations() throws {
    let hits: [MemoryOSRetrievalHit] = [
        MemoryOSRetrievalHit(layer: .l4, recordID: "entity-c", title: "宇宙（系统）", summary: "", matchedText: "", score: 1.0, entityRefs: ["entity-c"], metadata: ["entity_type": "concept"])
    ]
    let expansions: [String: [MemoryOSL4ExpansionHit]] = [
        "entity-c": [
            MemoryOSL4ExpansionHit(recordID: "nil-target", sourceEntityID: "entity-c", relatedEntityID: nil, predicate: MemoryOSL4RelationPredicate.relatedTo.rawValue, text: "", depth: 1, score: 1.0),
            MemoryOSL4ExpansionHit(recordID: "valid-2", sourceEntityID: "entity-c", relatedEntityID: "entity-d", predicate: MemoryOSL4RelationPredicate.about.rawValue, text: "", depth: 1, score: 1.0)
        ]
    ]

    let result = MemoryOSContextBuilder().buildFlatStrings(hits: hits, expansions: expansions, extraEntityNames: ["entity-d": "模型"])

    #expect(!result.contains { $0.contains("unknown") })
    #expect(result.contains { $0.contains("relates to") && $0.contains("模型") })
}
