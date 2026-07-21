import Foundation
import ConnorGraphCore

public enum MemoryOSRetrievalLayer: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case l0 = "L0"
    case l1 = "L1"
    case l2 = "L2"
    case l3 = "L3"
    case l4 = "L4"
}

public struct MemoryOSRetrievalQuery: Sendable, Codable, Equatable {
    public var text: String
    public var layers: [MemoryOSRetrievalLayer]
    public var limit: Int
    public var depth: Int

    public init(text: String, layers: [MemoryOSRetrievalLayer] = MemoryOSRetrievalLayer.allCases, limit: Int = 10, depth: Int = 1) {
        self.text = text
        self.layers = layers
        self.limit = limit
        self.depth = depth
    }
}

public enum MemoryOSRecordTemporalStatus: String, Sendable, Codable, Equatable, CaseIterable {
    case active
    case historical
    case superseded
    case uncertain
    case conflicted
}

public struct MemoryOSRetrievalHit: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(layer.rawValue):\(recordID)" }
    public var layer: MemoryOSRetrievalLayer
    public var recordID: String
    public var title: String
    public var summary: String
    public var matchedText: String
    public var score: Double
    public var evidenceRefs: [String]
    public var provenanceRefs: [String]
    public var entityRefs: [String]
    public var canReadRaw: Bool
    public var canExpandDepth: Bool
    public var metadata: [String: String]

    public var effectiveUpdatedAt: String? {
        let value = metadata["effective_updated_at"] ?? metadata["updated_at"]
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    public var temporalStatus: MemoryOSRecordTemporalStatus {
        MemoryOSRecordTemporalStatus(rawValue: metadata["status"] ?? "") ?? .active
    }

    public init(layer: MemoryOSRetrievalLayer, recordID: String, title: String, summary: String = "", matchedText: String = "", score: Double = 0, evidenceRefs: [String] = [], provenanceRefs: [String] = [], entityRefs: [String] = [], canReadRaw: Bool = false, canExpandDepth: Bool = false, metadata: [String: String] = [:]) {
        self.layer = layer
        self.recordID = recordID
        self.title = title
        self.summary = summary
        self.matchedText = matchedText
        self.score = score
        self.evidenceRefs = evidenceRefs
        self.provenanceRefs = provenanceRefs
        self.entityRefs = entityRefs
        self.canReadRaw = canReadRaw
        self.canExpandDepth = canExpandDepth
        self.metadata = metadata
    }
}

public struct MemoryOSL4ExpansionHit: Sendable, Codable, Equatable, Identifiable {
    public var id: String { recordID }
    public var recordID: String
    public var sourceEntityID: String
    public var relatedEntityID: String?
    public var predicate: String
    public var text: String
    public var depth: Int
    public var score: Double
    public var updatedAt: String?
    public var pathRecordIDs: [String]

    public init(recordID: String, sourceEntityID: String, relatedEntityID: String?, predicate: String, text: String, depth: Int, score: Double = 1.0, updatedAt: String? = nil, pathRecordIDs: [String] = []) {
        self.recordID = recordID
        self.sourceEntityID = sourceEntityID
        self.relatedEntityID = relatedEntityID
        self.predicate = predicate
        self.text = text
        self.depth = depth
        self.score = score
        self.updatedAt = updatedAt
        self.pathRecordIDs = pathRecordIDs.isEmpty ? [recordID] : pathRecordIDs
    }
}

public struct SQLiteMemoryOSUnifiedRetrievalService: Sendable {
    public var store: SQLiteMemoryOSStore
    public var minimumRelevanceScore: Double

    public init(store: SQLiteMemoryOSStore, minimumRelevanceScore: Double = 0.01) {
        self.store = store
        self.minimumRelevanceScore = max(0, minimumRelevanceScore)
    }

    public func search(_ query: MemoryOSRetrievalQuery) throws -> [MemoryOSRetrievalHit] {
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var hits: [MemoryOSRetrievalHit] = []
        let layers = Set(query.layers)
        if layers.contains(.l0) { hits += try searchL0(trimmed, limit: query.limit) }
        if layers.contains(.l1) { hits += try searchL1(trimmed, limit: query.limit) }
        if layers.contains(.l2) { hits += try searchL2(trimmed, limit: query.limit) }
        if layers.contains(.l3) { hits += try searchL3(trimmed, limit: query.limit) }
        if layers.contains(.l4) { hits += try searchL4(trimmed, limit: query.limit) }
        return Array(hits
            .filter { $0.score >= minimumRelevanceScore }
            .sorted(by: Self.isOrderedBefore)
            .prefix(max(0, query.limit)))
    }

    public static func isOrderedBefore(_ lhs: MemoryOSRetrievalHit, _ rhs: MemoryOSRetrievalHit) -> Bool {
        switch (lhs.effectiveUpdatedAt, rhs.effectiveUpdatedAt) {
        case let (left?, right?) where left != right: return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.recordID < rhs.recordID
    }

    public func expandL4(entityName: String, depth: Int = 5, limit: Int = 200) throws -> [MemoryOSL4ExpansionHit] {
        guard depth > 0, limit > 0 else { return [] }
        let trimmed = entityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Check cache first
        let cache = MemoryOSQueryCache.shared
        if let cached = cache.getCachedEntityExpansion(entityName: trimmed, depth: depth, limit: limit) {
            return cached
        }

        // Step 1: Try FTS5 for fast entity name lookup
        var entityID: String?
        let ftsResults = try store.searchEntitiesFTS(query: trimmed, limit: 5)
        if let firstFTS = ftsResults.first {
            entityID = firstFTS
        } else {
            // Step 2: Fallback to exact match on id/stable_key/name, then LIKE for aliases
            let quoted = store.quote(trimmed)
            let like = store.quote("%\(trimmed)%")
            let resolved = try store.query(sql: """
                SELECT e.id FROM memory_l4_entities e
                LEFT JOIN memory_l4_entity_aliases a ON a.entity_id = e.id
                WHERE e.id = \(quoted) OR e.stable_key = \(quoted) OR e.name = \(quoted)
                   OR a.alias = \(quoted) OR a.alias LIKE \(like)
                ORDER BY CASE
                  WHEN e.id = \(quoted) THEN 100
                  WHEN e.stable_key = \(quoted) THEN 95
                  WHEN e.name = \(quoted) THEN 90
                  WHEN EXISTS (SELECT 1 FROM memory_l4_entity_aliases a2 WHERE a2.entity_id = e.id AND a2.alias = \(quoted)) THEN 85
                  ELSE 25
                END DESC
                LIMIT 1
                """)
            entityID = resolved.first?.first
        }
        guard let entityID, !entityID.isEmpty else { return [] }

        var results: [MemoryOSL4ExpansionHit] = []
        var frontier: Set<String> = [entityID]
        var visited: Set<String> = [entityID]
        var pathByEntity: [String: [String]] = [entityID: []]

        for currentDepth in 1...depth {
            guard !frontier.isEmpty, results.count < limit else { break }
            let quoted = frontier.map { store.quote($0) }.joined(separator: ",")
            let rows = try store.query(sql: """
            SELECT id, entity_id, predicate, object_entity_id, text, COALESCE(committed_at, ''), COALESCE(valid_at, '')
            FROM memory_l4_entity_statements
            WHERE entity_id IN (\(quoted)) OR (object_entity_id IS NOT NULL AND object_entity_id IN (\(quoted)))
            ORDER BY committed_at DESC
            LIMIT \(limit - results.count)
            """)
            var nextFrontier: Set<String> = []
            for row in rows {
                let source = row[1]
                let object = row[3].isEmpty ? nil : row[3]
                let baseEntity = frontier.contains(source) ? source : (object.flatMap { frontier.contains($0) ? $0 : nil } ?? source)
                let related = baseEntity == source ? object : source
                let score = l4ExpansionScore(predicate: row[2], depth: currentDepth)
                let path = (pathByEntity[baseEntity] ?? []) + [row[0]]
                results.append(MemoryOSL4ExpansionHit(recordID: row[0], sourceEntityID: source, relatedEntityID: related, predicate: row[2], text: row[4], depth: currentDepth, score: score, updatedAt: firstNonEmpty(row[5], row[6]), pathRecordIDs: path))
                if let related, !visited.contains(related) {
                    visited.insert(related)
                    nextFrontier.insert(related)
                    pathByEntity[related] = path
                }
            }
            frontier = nextFrontier
        }
        let sorted = Array(results.sorted { lhs, rhs in
            switch (lhs.updatedAt, rhs.updatedAt) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.recordID < rhs.recordID
        }.prefix(limit))
        
        // Cache the result
        MemoryOSQueryCache.shared.setCachedEntityExpansion(sorted, entityName: trimmed, depth: depth, limit: limit)
        
        return sorted
    }

    private func l4ExpansionScore(predicate rawValue: String, depth: Int) -> Double {
        let relationWeight = MemoryOSL4RelationPredicate(rawValue: rawValue)?.retrievalWeight ?? 1.0
        let depthDecay = 1.0 / Double(max(depth, 1))
        return relationWeight * depthDecay
    }

    private func searchL0(_ text: String, limit: Int) throws -> [MemoryOSRetrievalHit] {
        try store.query(sql: """
        SELECT f.object_id, f.title, f.content, bm25(memory_l0_provenance_fts) AS rank, COALESCE(o.ingested_at, ''), COALESCE(o.occurred_at, ''), COALESCE(o.status, 'active')
        FROM memory_l0_provenance_fts f
        LEFT JOIN memory_l0_provenance_objects o ON o.id = f.object_id
        WHERE memory_l0_provenance_fts MATCH \(store.quote(ftsQuery(text)))
        ORDER BY rank
        LIMIT \(limit)
        """).map { row in
            let effective = firstNonEmpty(row[4], row[5])
            return MemoryOSRetrievalHit(layer: .l0, recordID: row[0], title: row[1], summary: row[2], matchedText: row[2], score: score(fromFTSRank: row[3]), provenanceRefs: [row[0]], canReadRaw: true, metadata: ["ingested_at": row[4], "occurred_at": row[5], "updated_at": effective, "effective_updated_at": effective, "status": normalizedStatus(row[6])])
        }
    }

    private func searchL1(_ text: String, limit: Int) throws -> [MemoryOSRetrievalHit] {
        let terms = expandedSearchTerms(text)
        let eventTypeClauses = terms.map { term in
            "c.event_type LIKE \(store.quote("%\(term)%"))"
        }
        let eventTypePredicate = eventTypeClauses.isEmpty ? "0" : eventTypeClauses.joined(separator: " OR ")
        return try store.query(sql: """
        WITH matched_objects AS (
            SELECT object_id
            FROM memory_l0_provenance_fts
            WHERE memory_l0_provenance_fts MATCH \(store.quote(ftsQuery(text)))
        )
        SELECT c.id, c.event_type, c.provenance_object_id, c.metadata_json, o.title, o.content, COALESCE(c.occurred_at, '')
        FROM memory_l1_capture_events c
        JOIN memory_l0_provenance_objects o ON o.id = c.provenance_object_id
        WHERE c.provenance_object_id IN (SELECT object_id FROM matched_objects)
           OR \(eventTypePredicate)
        ORDER BY c.occurred_at DESC
        LIMIT \(limit)
        """).map { row in
            var metadata = (try? store.decode([String: String].self, row[3])) ?? [:]
            metadata["occurred_at"] = row[6]
            metadata["updated_at"] = row[6]
            metadata["effective_updated_at"] = row[6]
            metadata["status"] = normalizedStatus(metadata["status"])
            return MemoryOSRetrievalHit(layer: .l1, recordID: row[0], title: row[1], summary: row[4], matchedText: row[5], score: lexicalScore(terms.joined(separator: " "), haystack: row[4] + " " + row[5]), evidenceRefs: metadata["span_id"].map { [$0] } ?? [], provenanceRefs: [row[2]], canReadRaw: true, metadata: metadata)
        }
    }

    private func searchL2(_ text: String, limit: Int) throws -> [MemoryOSRetrievalHit] {
        try store.query(sql: """
        SELECT f.statement_id, f.predicate, f.text, s.evidence_span_ids_json, s.subject_id, bm25(memory_l2_statements_fts) AS rank, COALESCE(s.committed_at, ''), COALESCE(s.valid_at, ''), s.confidence, s.metadata_json
        FROM memory_l2_statements_fts f
        JOIN memory_l2_statements s ON s.id = f.statement_id
        WHERE memory_l2_statements_fts MATCH \(store.quote(ftsQuery(text)))
        ORDER BY rank
        LIMIT \(limit)
        """).map { row in
            let evidence = (try? store.decode([String].self, row[3])) ?? []
            var metadata = (try? store.decode([String: String].self, row[9])) ?? [:]
            let effective = firstNonEmpty(row[6], row[7])
            metadata.merge(["committed_at": row[6], "valid_at": row[7], "confidence": row[8], "updated_at": effective, "effective_updated_at": effective, "status": normalizedStatus(metadata["status"])]) { _, new in new }
            return MemoryOSRetrievalHit(layer: .l2, recordID: row[0], title: row[1], summary: row[2], matchedText: row[2], score: score(fromFTSRank: row[5]), evidenceRefs: evidence, entityRefs: [row[4]], metadata: metadata)
        }
    }

    private func searchL3(_ text: String, limit: Int) throws -> [MemoryOSRetrievalHit] {
        try store.query(sql: """
        SELECT f.belief_id, b.statement, b.domain, b.related_object_names, b.created_at, b.updated_at, bm25(memory_l3_beliefs_fts) AS rank
        FROM memory_l3_beliefs_fts f
        JOIN memory_l3_beliefs b ON b.id = f.belief_id
        WHERE memory_l3_beliefs_fts MATCH \(store.quote(ftsQuery(text)))
        ORDER BY rank
        LIMIT \(limit)
        """).map { row in
            let statement = row[1]
            return MemoryOSRetrievalHit(
                layer: .l3,
                recordID: row[0],
                title: statement,
                summary: statement,
                matchedText: statement,
                score: score(fromFTSRank: row[6]),
                metadata: [
                    "domain": row[2],
                    "related_object_names": row[3],
                    "created_at": row[4],
                    "updated_at": firstNonEmpty(row[5], row[4]),
                    "effective_updated_at": firstNonEmpty(row[5], row[4]),
                    "status": MemoryOSRecordTemporalStatus.active.rawValue
                ]
            )
        }
    }

    private func searchL4(_ text: String, limit: Int) throws -> [MemoryOSRetrievalHit] {
        var hits = try store.query(sql: """
        SELECT f.entity_id, f.entity_type, f.name, f.summary, bm25(memory_l4_entities_fts) AS rank, COALESCE(e.updated_at, ''), COALESCE(e.created_at, ''), COALESCE(e.valid_from, ''), e.confidence, e.metadata_json
        FROM memory_l4_entities_fts f
        LEFT JOIN memory_l4_entities e ON e.id = f.entity_id
        WHERE memory_l4_entities_fts MATCH \(store.quote(ftsQuery(text)))
        ORDER BY rank
        LIMIT \(limit)
        """).map { row in
            var metadata = (try? store.decode([String: String].self, row[9])) ?? [:]
            let effective = firstNonEmpty(row[5], row[6], row[7])
            metadata.merge(["entity_type": row[1], "updated_at": effective, "effective_updated_at": effective, "created_at": row[6], "valid_from": row[7], "confidence": row[8], "status": normalizedStatus(metadata["status"])]) { _, new in new }
            return MemoryOSRetrievalHit(layer: .l4, recordID: row[0], title: row[2], summary: row[3], matchedText: row[2] + " " + row[3], score: score(fromFTSRank: row[4]), entityRefs: [row[0]], canExpandDepth: true, metadata: metadata)
        }
        if hits.count < limit {
            hits += try store.query(sql: """
            SELECT f.statement_id, f.predicate, f.text, s.evidence_span_ids_json, s.entity_id, s.object_entity_id, bm25(memory_l4_statements_fts) AS rank, COALESCE(s.committed_at, ''), COALESCE(s.valid_at, ''), s.confidence, s.metadata_json
            FROM memory_l4_statements_fts f
            JOIN memory_l4_entity_statements s ON s.id = f.statement_id
            WHERE memory_l4_statements_fts MATCH \(store.quote(ftsQuery(text)))
            ORDER BY rank
            LIMIT \(limit - hits.count)
            """).map { row in
                let evidence = (try? store.decode([String].self, row[3])) ?? []
                var metadata = (try? store.decode([String: String].self, row[10])) ?? [:]
                let effective = firstNonEmpty(row[7], row[8])
                metadata.merge(["committed_at": row[7], "valid_at": row[8], "confidence": row[9], "updated_at": effective, "effective_updated_at": effective, "status": normalizedStatus(metadata["status"])]) { _, new in new }
                return MemoryOSRetrievalHit(layer: .l4, recordID: row[0], title: row[1], summary: row[2], matchedText: row[2], score: score(fromFTSRank: row[6]), evidenceRefs: evidence, entityRefs: [row[4], row[5]].filter { !$0.isEmpty }, canExpandDepth: true, metadata: metadata)
            }
        }
        return hits
    }

    private func ftsQuery(_ text: String) -> String {
        let terms = expandedSearchTerms(text)
        return FTS5QuerySanitizer.sanitizeTerms(terms)
    }

    /// Expand search text into terms with domain-specific synonyms.
    /// All output terms are plain strings; FTS5 quoting is handled by FTS5QuerySanitizer.
    private func expandedSearchTerms(_ text: String) -> [String] {
        let plan = MemorySearchQueryParser.parse(text)
        guard !plan.normalizedText.isEmpty else { return [] }

        let weakChinesePhrases = ["有哪些", "所有", "全部", "列出", "关于", "相关", "哪些", "什么", "请问", "一下"]
        var terms = plan.retrievalTerms.compactMap { rawTerm -> String? in
            var simplified = rawTerm
            for phrase in weakChinesePhrases {
                simplified = simplified.replacingOccurrences(of: phrase, with: " ")
            }
            simplified = simplified.replacingOccurrences(of: "的", with: " ")
            let normalized = simplified.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }

        let compact = plan.normalizedText.filter { !$0.isWhitespace && !$0.isPunctuation }
        let domainExpansions: [(String, [String])] = [
            ("国家", ["国家", "country", "主权国家", "主權國家"]),
            ("中國", ["中国", "中國", "中华人民共和国", "中華人民共和國", "China", "PRC"]),
            ("中国", ["中国", "中國", "中华人民共和国", "中華人民共和國", "China", "PRC"])
        ]
        for (needle, expansions) in domainExpansions where compact.contains(needle) {
            terms.append(contentsOf: expansions)
        }

        if terms.isEmpty, !compact.isEmpty {
            terms.append(compact)
        }
        return Array(NSOrderedSet(array: terms).compactMap { $0 as? String })
    }

    private func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }

    private func normalizedStatus(_ rawValue: String?) -> String {
        let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if MemoryOSRecordTemporalStatus(rawValue: normalized) != nil { return normalized }
        if ["inactive", "archived", "deleted"].contains(normalized) { return MemoryOSRecordTemporalStatus.historical.rawValue }
        return MemoryOSRecordTemporalStatus.active.rawValue
    }

    private func score(fromFTSRank rank: String) -> Double {
        let value = Double(rank) ?? 0
        // SQLite FTS5 bm25() returns smaller values for better matches and commonly returns negative values.
        // Preserve that ordering by mapping more-negative ranks to scores above 1 instead of clamping all
        // negative ranks to the same score.
        if value < 0 { return 1.0 + min(100.0, -value) }
        return 1.0 / (1.0 + value)
    }

    private func lexicalScore(_ query: String, haystack: String) -> Double {
        let terms = Set(query.lowercased().split { $0.isWhitespace || $0.isPunctuation }.map(String.init))
        guard !terms.isEmpty else { return 0 }
        let lower = haystack.lowercased()
        let matched = terms.filter { lower.contains($0) }.count
        return Double(matched) / Double(terms.count)
    }

}
