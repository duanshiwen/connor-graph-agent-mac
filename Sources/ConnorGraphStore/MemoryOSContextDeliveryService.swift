import Foundation

public struct MemoryOSContextDeliveryService: Sendable {
    public var store: SQLiteMemoryOSStore
    public var builder: MemoryOSContextBuilder

    public init(store: SQLiteMemoryOSStore, builder: MemoryOSContextBuilder = MemoryOSContextBuilder()) {
        self.store = store
        self.builder = builder
    }

    public func context(_ request: MemoryOSContextRequest, generatedAt: Date = Date()) throws -> MemoryOSContextPackage {
        let retrieval = SQLiteMemoryOSUnifiedRetrievalService(store: store)
        let hits = try retrieval.search(MemoryOSRetrievalQuery(
            text: request.query,
            layers: request.layers,
            limit: request.retrievalPolicy.maxInitialHits,
            depth: request.graphPolicy.maxDepth
        ))
        var expansions: [String: [MemoryOSL4ExpansionHit]] = [:]
        var diagnostics: [MemoryOSContextDiagnostic] = []

        if request.graphPolicy.enabled && request.graphPolicy.maxDepth > 0 && request.graphPolicy.expansionStrategy != .none {
            for hit in hits where hit.layer == .l4 && hit.canExpandDepth {
                guard let entityID = hit.entityRefs.first ?? Optional(hit.recordID) else { continue }
                let expanded = try retrieval.expandL4(
                    entityID: entityID,
                    depth: request.graphPolicy.maxDepth,
                    limit: request.graphPolicy.maxEdgesPerSeed
                )
                let filtered = filter(expanded, policy: request.graphPolicy)
                if !filtered.isEmpty { expansions[entityID] = filtered }
            }
        } else {
            diagnostics.append(MemoryOSContextDiagnostic(
                id: "graph-expansion-skipped",
                severity: .info,
                kind: .expansionSkipped,
                message: "Graph expansion was skipped by request policy.",
                affectedRecordIDs: hits.filter { $0.layer == .l4 }.map(\.recordID),
                suggestedAction: "Enable graphPolicy.enabled and set maxDepth above 0 when relationship context is needed."
            ))
        }

        var package = builder.build(request: request, hits: hits, expansions: expansions, generatedAt: generatedAt)
        if !diagnostics.isEmpty {
            package.diagnostics.append(contentsOf: diagnostics)
        }
        return package
    }

    private func filter(_ hits: [MemoryOSL4ExpansionHit], policy: MemoryOSGraphExpansionPolicy) -> [MemoryOSL4ExpansionHit] {
        hits.filter { hit in
            if !policy.allowedPredicates.isEmpty && !policy.allowedPredicates.contains(hit.predicate) { return false }
            if policy.blockedPredicates.contains(hit.predicate) { return false }
            return true
        }
    }
}
