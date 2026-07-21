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

    /// Search volatile operational memory only. L1/L2 results describe recent captures and
    /// current working state; no durable knowledge or graph expansion is included.
    public func recentContext(terms: [String]) throws -> [String] {
        let hits = try searchTerms(terms, layers: [.l1, .l2])
        return builder.buildRecentContextStrings(hits: hits)
    }

    /// Search reusable knowledge and stable graph memory only. Every matching L4 entity is
    /// expanded through five relationship hops by default and rendered into natural language.
    public func knowledgeContext(terms: [String], l4Depth: Int = 5) throws -> [String] {
        let depth = max(1, min(l4Depth, 5))
        let hits = try searchTerms(terms, layers: [.l3, .l4])
        var expansions: [String: [MemoryOSL4ExpansionHit]] = [:]
        let retrieval = SQLiteMemoryOSUnifiedRetrievalService(store: store)

        for hit in hits where hit.layer == .l4 && hit.canExpandDepth {
            guard expansions[hit.recordID] == nil else { continue }
            let entityRef = hit.title.isEmpty ? (hit.entityRefs.first ?? hit.recordID) : hit.title
            let expanded = try retrieval.expandL4(entityName: entityRef, depth: depth, limit: 200)
            if !expanded.isEmpty { expansions[hit.recordID] = expanded }
        }

        return builder.buildKnowledgeContextStrings(
            hits: hits,
            expansions: expansions,
            extraEntityNames: try resolveEntityNames(from: expansions)
        )
    }

    private func searchTerms(_ terms: [String], layers: [MemoryOSRetrievalLayer]) throws -> [MemoryOSRetrievalHit] {
        let normalizedTerms = terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !normalizedTerms.isEmpty else { return [] }

        let hits: [MemoryOSRetrievalHit]
        if let searchKernel {
            let kernelLayers = layers.compactMap { MemoryOSSearchKernelLayer(rawValue: $0.rawValue) }
            let response = try searchKernel.search(MemoryOSSearchKernelRequest(
                query: normalizedTerms.joined(separator: ";"),
                queries: normalizedTerms,
                layers: kernelLayers,
                limit: 200
            ))
            hits = response.hits.map(Self.hitFromKernel)
        } else {
            let retrieval = SQLiteMemoryOSUnifiedRetrievalService(store: store)
            hits = try normalizedTerms.flatMap { term in
                try retrieval.search(MemoryOSRetrievalQuery(text: term, layers: layers, limit: 50))
            }
        }

        var seen = Set<String>()
        return hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.id < rhs.id
        }.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Search Kernel Bridge

    /// Convert a Rust/Tantivy search kernel hit to the SQLite retrieval hit format
    /// used by MemoryOSContextBuilder.
    private static func hitFromKernel(_ hit: MemoryOSSearchKernelHit) -> MemoryOSRetrievalHit {
        let layer = MemoryOSRetrievalLayer(rawValue: hit.layer.rawValue) ?? .l4
        let isEntity = hit.recordKind == "Entity"
        var metadata: [String: String]
        if let data = hit.metadataJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            metadata = obj
        } else {
            metadata = [:]
        }
        if metadata["updated_at"] == nil, let updatedAt = hit.updatedAt, !updatedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["updated_at"] = updatedAt
        }
        if metadata["effective_updated_at"] == nil, let updatedAt = metadata["updated_at"] {
            metadata["effective_updated_at"] = updatedAt
        }
        if metadata["status"] == nil { metadata["status"] = MemoryOSRecordTemporalStatus.active.rawValue }
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
