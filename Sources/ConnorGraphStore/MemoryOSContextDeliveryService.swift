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
                let entityRef = hit.title.isEmpty ? (hit.entityRefs.first ?? hit.recordID) : hit.title
                let expanded = try retrieval.expandL4(
                    entityName: entityRef,
                    depth: request.graphPolicy.maxDepth,
                    limit: request.graphPolicy.maxEdgesPerSeed
                )
                let filtered = filter(expanded, policy: request.graphPolicy)
                if !filtered.isEmpty { expansions[hit.recordID] = filtered }
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

    /// Search Memory OS L1-L4 with multiple search terms in parallel, merge and deduplicate results.
    /// - Parameter terms: Search terms extracted by the LLM (pre-split by semicolons).
    /// - Returns: Deduplicated array of natural-language memory items.
    public func flatContext(terms: [String]) throws -> [String] {
        let layers: [MemoryOSRetrievalLayer] = [.l1, .l2, .l3, .l4]
        let retrieval = SQLiteMemoryOSUnifiedRetrievalService(store: store)

        var allHits: [MemoryOSRetrievalHit] = []
        var allExpansions: [String: [MemoryOSL4ExpansionHit]] = [:]

        for term in terms {
            let hits = try retrieval.search(MemoryOSRetrievalQuery(
                text: term, layers: layers, limit: 50, depth: 5
            ))
            allHits.append(contentsOf: hits)

            for hit in hits where hit.layer == .l4 && hit.canExpandDepth {
                if allExpansions[hit.recordID] != nil { continue }
                let entityRef = hit.title.isEmpty ? (hit.entityRefs.first ?? hit.recordID) : hit.title
                let expanded = try retrieval.expandL4(entityName: entityRef, depth: 5, limit: 8)
                if !expanded.isEmpty { allExpansions[hit.recordID] = expanded }
            }
        }

        return builder.buildFlatStrings(hits: allHits, expansions: allExpansions, extraEntityNames: try resolveEntityNames(from: allExpansions))
    }

    private func resolveEntityNames(from expansions: [String: [MemoryOSL4ExpansionHit]]) throws -> [String: String] {
        var ids = Set<String>()
        for (_, relations) in expansions {
            for r in relations {
                ids.insert(r.sourceEntityID)
                if let obj = r.relatedEntityID { ids.insert(obj) }
            }
        }
        guard !ids.isEmpty else { return [:] }
        let quoted = ids.map { store.quote($0) }.joined(separator: ",")
        let rows = try store.query(sql: """
        SELECT id, name FROM memory_l4_entities WHERE id IN (\(quoted))
        """)
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            row[1].isEmpty ? nil : (row[0], row[1])
        })
    }

    private func filter(_ hits: [MemoryOSL4ExpansionHit], policy: MemoryOSGraphExpansionPolicy) -> [MemoryOSL4ExpansionHit] {
        hits.filter { hit in
            if !policy.allowedPredicates.isEmpty && !policy.allowedPredicates.contains(hit.predicate) { return false }
            if policy.blockedPredicates.contains(hit.predicate) { return false }
            return true
        }
    }
}
