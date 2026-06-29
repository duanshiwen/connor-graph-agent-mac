import Foundation
import Testing
import ConnorGraphStore

@Test func memoryOSContextPackageCodableRoundTripsCommercialContract() throws {
    let generatedAt = Date(timeIntervalSince1970: 10_000)
    let validAt = Date(timeIntervalSince1970: 9_000)
    let package = MemoryOSContextPackage(
        id: "ctx-1",
        query: "How should Memory OS return graph relationships to an LLM?",
        taskIntent: .explainRelationship,
        generatedAt: generatedAt,
        referenceTime: generatedAt,
        executiveSummary: "Memory OS should deliver evidence-bound graph context, not raw hits only.",
        contextText: "Entity Connor Memory OS relates to L4 through stable entity context.",
        blocks: [
            MemoryOSContextBlock(
                id: "block-1",
                role: .relation,
                layer: .l4,
                priority: 10,
                text: "Connor Memory OS uses L4 as the stable entity and concept layer.",
                recordIDs: ["relation-1"],
                entityIDs: ["entity-memory-os", "entity-l4"],
                relationIDs: ["relation-1"],
                evidenceRefs: ["span-1"],
                provenanceRefs: ["object-1"],
                confidence: 0.91,
                validAt: validAt,
                uncertainty: .low
            )
        ],
        entities: [
            MemoryOSEntityContextCard(
                id: "card-entity-memory-os",
                entityID: "entity-memory-os",
                name: "Connor Memory OS",
                kind: "system",
                summary: "Background memory infrastructure.",
                aliases: ["Memory OS"],
                attributes: [MemoryOSAttributeSentence(text: "It stores L0-L4 memory layers.", recordIDs: ["entity-memory-os"], evidenceRefs: [])],
                outgoingRelations: ["relation-1"],
                incomingRelations: [],
                evidenceRefs: ["span-1"],
                provenanceRefs: ["object-1"],
                sourceRecordIDs: ["entity-memory-os"]
            )
        ],
        relations: [
            MemoryOSRelationContextCard(
                id: "relation-1",
                sourceID: "entity-memory-os",
                sourceName: "Connor Memory OS",
                predicate: "HAS_PART",
                predicateLabel: "has part",
                targetID: "entity-l4",
                targetName: "L4 Stable Entity / Concept Layer",
                sentence: "Connor Memory OS contains L4 Stable Entity / Concept Layer.",
                confidence: 0.91,
                validAt: validAt,
                invalidAt: nil,
                evidenceRefs: ["span-1"],
                provenanceRefs: ["object-1"]
            )
        ],
        evidence: [
            MemoryOSEvidenceContextCard(id: "evidence-1", evidenceRef: "span-1", provenanceRef: "object-1", snippet: "L4 stores stable entities.", sourceTitle: "README", quality: 0.9)
        ],
        diagnostics: [
            MemoryOSContextDiagnostic(id: "diag-1", severity: .info, kind: .budgetTruncated, message: "Context was budgeted.", affectedRecordIDs: [], suggestedAction: nil)
        ],
        rawRetrieval: MemoryOSRawRetrievalTrace(initialHitCount: 3, expandedRelationCount: 1, tracedEvidenceCount: 1, retrievalMethods: ["fts", "graph"]),
        suggestedNextActions: [
            MemoryOSContextNextAction(toolName: "memory_os_read_provenance", reason: "Verify relation evidence.", arguments: ["spanIDs": ["span-1"]])
        ],
        budgetReport: MemoryOSContextBudgetReport(maxContextCharacters: 6_000, actualContextCharacters: 120, truncatedBlockCount: 0, truncatedRelationCount: 0),
        qualitySignals: MemoryOSContextQualitySignals(relevanceScore: 0.9, evidenceCoverage: 1.0, relationCoverage: 1.0, redundancyRate: 0.0, staleLeakRate: 0.0, conflictSurfacingRate: 0.0, budgetCompliance: 1.0)
    )

    let data = try JSONEncoder().encode(package)
    let decoded = try JSONDecoder().decode(MemoryOSContextPackage.self, from: data)

    #expect(decoded == package)
    #expect(decoded.blocks.first?.layer == .l4)
    #expect(decoded.relations.first?.sentence.contains("contains L4") == true)
    #expect(decoded.suggestedNextActions.first?.arguments["spanIDs"]?.arrayValue?.first?.stringValue == "span-1")
}

@Test func memoryOSContextBudgetDefaultsAreCommercialSafe() {
    let budget = MemoryOSContextBudget.commercialDefault

    #expect(budget.maxContextCharacters >= 6_000)
    #expect(budget.maxBlocks >= 12)
    #expect(budget.maxEntityCards >= 8)
    #expect(budget.maxRelationCards >= 20)
    #expect(budget.maxEvidenceCards >= 6)
}
