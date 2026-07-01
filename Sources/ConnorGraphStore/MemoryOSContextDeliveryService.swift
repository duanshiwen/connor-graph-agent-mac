import Foundation
import ConnorGraphSearch

public struct MemoryOSContextDeliveryService: Sendable {
    public var store: SQLiteMemoryOSStore
    public var builder: MemoryOSContextBuilder
    public var searchKernel: MemoryOSSearchKernel?

    public init(store: SQLiteMemoryOSStore, builder: MemoryOSContextBuilder = MemoryOSContextBuilder(), searchKernel: MemoryOSSearchKernel? = nil) {
        self.store = store
        self.builder = builder
        self.searchKernel = searchKernel
    }

    public func context(_ request: MemoryOSContextRequest, generatedAt: Date = Date()) throws -> MemoryOSContextPackage {
        let hits: [MemoryOSRetrievalHit]
        let retrieval = SQLiteMemoryOSUnifiedRetrievalService(store: store)

        if let searchKernel, !request.layers.isEmpty {
            // Use Rust/Tantivy search kernel for full-text retrieval
            let response = try searchKernel.search(MemoryOSSearchKernelRequest(
                query: request.query,
                layers: request.layers.compactMap { MemoryOSSearchKernelLayer(rawValue: $0.rawValue) },
                limit: request.retrievalPolicy.maxInitialHits
            ))
            hits = response.hits.map { MemoryOSContextDeliveryService.hitFromKernel($0) }
        } else {
            hits = try retrieval.search(MemoryOSRetrievalQuery(
                text: request.query,
                layers: request.layers,
                limit: request.retrievalPolicy.maxInitialHits,
                depth: request.graphPolicy.maxDepth
            ))
        }

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
        var allHits: [MemoryOSRetrievalHit] = []
        var allExpansions: [String: [MemoryOSL4ExpansionHit]] = [:]

        if let searchKernel, !terms.isEmpty {
            // Use Rust/Tantivy search kernel: combine all terms into a single query.
            // Jieba tokenization + OR logic handles multi-term better than per-term FTS5.
            let combinedQuery = terms.joined(separator: ";")
            let response = try searchKernel.search(MemoryOSSearchKernelRequest(
                query: combinedQuery,
                layers: [.l0, .l1, .l2, .l3, .l4],
                limit: 200
            ))
            allHits = response.hits.map { Self.hitFromKernel($0) }
        } else {
            // Fallback: SQLite FTS5 per-term search
            let retrieval = SQLiteMemoryOSUnifiedRetrievalService(store: store)
            for term in terms {
                let hits = try retrieval.search(MemoryOSRetrievalQuery(
                    text: term, layers: layers, limit: 50, depth: 5
                ))
                allHits.append(contentsOf: hits)
            }
        }

        // L4 graph expansion always uses SQLite (graph traversal, not full-text search)
        for hit in allHits where hit.layer == .l4 && hit.canExpandDepth {
            if allExpansions[hit.recordID] != nil { continue }
            let entityRef = hit.title.isEmpty ? (hit.entityRefs.first ?? hit.recordID) : hit.title
            let expanded = try SQLiteMemoryOSUnifiedRetrievalService(store: store)
                .expandL4(entityName: entityRef, depth: 5, limit: 8)
            if !expanded.isEmpty { allExpansions[hit.recordID] = expanded }
        }

        return builder.buildFlatStrings(hits: allHits, expansions: allExpansions, extraEntityNames: try resolveEntityNames(from: allExpansions))
    }

    // MARK: - Search Kernel Bridge

    /// Convert a Rust/Tantivy search kernel hit to the SQLite retrieval hit format
    /// used by MemoryOSContextBuilder.
    private static func hitFromKernel(_ hit: MemoryOSSearchKernelHit) -> MemoryOSRetrievalHit {
        let layer = MemoryOSRetrievalLayer(rawValue: hit.layer.rawValue) ?? .l4
        let isEntity = hit.recordKind == "Entity"
        let metadata: [String: String]
        if let data = hit.metadataJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            metadata = obj
        } else {
            metadata = [:]
        }
        return MemoryOSRetrievalHit(
            layer: layer,
            recordID: hit.recordID,
            title: hit.title,
            summary: hit.snippet,
            matchedText: hit.snippet,
            score: hit.score,
            evidenceRefs: [],
            entityRefs: isEntity ? [hit.recordID] : [],
            canExpandDepth: layer == .l4 && isEntity,
            metadata: metadata
        )
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
