import Foundation
import ConnorGraphCore
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

    public init(text: String, layers: [MemoryOSRetrievalLayer] = MemoryOSRetrievalLayer.allCases, limit: Int = 10, depth: Int = 0) {
        self.text = text
        self.layers = layers
        self.limit = limit
        self.depth = depth
    }
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

    public init(recordID: String, sourceEntityID: String, relatedEntityID: String?, predicate: String, text: String, depth: Int, score: Double = 1.0) {
        self.recordID = recordID
        self.sourceEntityID = sourceEntityID
        self.relatedEntityID = relatedEntityID
        self.predicate = predicate
        self.text = text
        self.depth = depth
        self.score = score
    }
}

public struct SQLiteMemoryOSUnifiedRetrievalService: Sendable {
    public var store: SQLiteMemoryOSStore

    public init(store: SQLiteMemoryOSStore) {
        self.store = store
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
        return Array(hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.layer.rawValue != rhs.layer.rawValue { return lhs.layer.rawValue < rhs.layer.rawValue }
            return lhs.recordID < rhs.recordID
        }.prefix(max(0, query.limit)))
    }

    public func expandL4(entityID: String, depth: Int = 1, limit: Int = 20) throws -> [MemoryOSL4ExpansionHit] {
        guard depth > 0, limit > 0 else { return [] }
        var results: [MemoryOSL4ExpansionHit] = []
        var frontier: Set<String> = [entityID]
        var visited: Set<String> = [entityID]

        for currentDepth in 1...depth {
            guard !frontier.isEmpty, results.count < limit else { break }
            let quoted = frontier.map { store.quote($0) }.joined(separator: ",")
            let rows = try store.query(sql: """
            SELECT id, entity_id, predicate, object_entity_id, text
            FROM memory_l4_entity_statements
            WHERE entity_id IN (\(quoted)) OR (object_entity_id IS NOT NULL AND object_entity_id IN (\(quoted)))
            ORDER BY committed_at DESC
            LIMIT \(limit - results.count)
            """)
            var nextFrontier: Set<String> = []
            for row in rows {
                let source = row[1]
                let object = row[3].isEmpty ? nil : row[3]
                let related = source == entityID || frontier.contains(source) ? object : source
                let score = l4ExpansionScore(predicate: row[2], depth: currentDepth)
                results.append(MemoryOSL4ExpansionHit(recordID: row[0], sourceEntityID: source, relatedEntityID: related, predicate: row[2], text: row[4], depth: currentDepth, score: score))
                if let related, !visited.contains(related) {
                    visited.insert(related)
                    nextFrontier.insert(related)
                }
            }
            frontier = nextFrontier
        }
        return Array(results.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.recordID < rhs.recordID
        }.prefix(limit))
    }

    private func l4ExpansionScore(predicate rawValue: String, depth: Int) -> Double {
        let relationWeight = MemoryOSL4RelationPredicate(rawValue: rawValue)?.retrievalWeight ?? 1.0
        let depthDecay = 1.0 / Double(max(depth, 1))
        return relationWeight * depthDecay
    }

    private func searchL0(_ text: String, limit: Int) throws -> [MemoryOSRetrievalHit] {
        try store.query(sql: """
        SELECT object_id, title, content, bm25(memory_l0_provenance_fts) AS rank
        FROM memory_l0_provenance_fts
        WHERE memory_l0_provenance_fts MATCH \(store.quote(ftsQuery(text)))
        ORDER BY rank
        LIMIT \(limit)
        """).map { row in
            MemoryOSRetrievalHit(layer: .l0, recordID: row[0], title: row[1], summary: row[2], matchedText: row[2], score: score(fromFTSRank: row[3]), provenanceRefs: [row[0]], canReadRaw: true)
        }
    }

    private func searchL1(_ text: String, limit: Int) throws -> [MemoryOSRetrievalHit] {
        let like = "%\(text.replacingOccurrences(of: "'", with: "''"))%"
        return try store.query(sql: """
        SELECT c.id, c.event_type, c.provenance_object_id, c.metadata_json, o.title, o.content
        FROM memory_l1_capture_events c
        JOIN memory_l0_provenance_objects o ON o.id = c.provenance_object_id
        WHERE o.title LIKE '\(like)' OR o.content LIKE '\(like)' OR c.event_type LIKE '\(like)'
        ORDER BY c.occurred_at DESC
        LIMIT \(limit)
        """).map { row in
            let metadata = (try? store.decode([String: String].self, row[3])) ?? [:]
            return MemoryOSRetrievalHit(layer: .l1, recordID: row[0], title: row[1], summary: row[4], matchedText: row[5], score: lexicalScore(text, haystack: row[4] + " " + row[5]), evidenceRefs: metadata["span_id"].map { [$0] } ?? [], provenanceRefs: [row[2]], canReadRaw: true, metadata: metadata)
        }
    }

    private func searchL2(_ text: String, limit: Int) throws -> [MemoryOSRetrievalHit] {
        try store.query(sql: """
        SELECT f.statement_id, f.predicate, f.text, s.evidence_span_ids_json, s.subject_id, bm25(memory_l2_statements_fts) AS rank, COALESCE(s.committed_at, '')
        FROM memory_l2_statements_fts f
        JOIN memory_l2_statements s ON s.id = f.statement_id
        WHERE memory_l2_statements_fts MATCH \(store.quote(ftsQuery(text)))
        ORDER BY rank
        LIMIT \(limit)
        """).map { row in
            let evidence = (try? store.decode([String].self, row[3])) ?? []
            return MemoryOSRetrievalHit(layer: .l2, recordID: row[0], title: row[1], summary: row[2], matchedText: row[2], score: score(fromFTSRank: row[5]), evidenceRefs: evidence, entityRefs: [row[4]], metadata: ["committed_at": row[6]])
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
                    "updated_at": row[5]
                ]
            )
        }
    }

    private func searchL4(_ text: String, limit: Int) throws -> [MemoryOSRetrievalHit] {
        var hits = try store.query(sql: """
        SELECT f.entity_id, f.entity_type, f.name, f.summary, bm25(memory_l4_entities_fts) AS rank, COALESCE(e.created_at, '')
        FROM memory_l4_entities_fts f
        LEFT JOIN memory_l4_entities e ON e.id = f.entity_id
        WHERE memory_l4_entities_fts MATCH \(store.quote(ftsQuery(text)))
        ORDER BY rank
        LIMIT \(limit)
        """).map { row in
            MemoryOSRetrievalHit(layer: .l4, recordID: row[0], title: row[2], summary: row[3], matchedText: row[2] + " " + row[3], score: score(fromFTSRank: row[4]), entityRefs: [row[0]], canExpandDepth: true, metadata: ["entity_type": row[1], "created_at": row[5]])
        }
        if hits.count < limit {
            hits += try store.query(sql: """
            SELECT f.statement_id, f.predicate, f.text, s.evidence_span_ids_json, s.entity_id, s.object_entity_id, bm25(memory_l4_statements_fts) AS rank, COALESCE(s.committed_at, '')
            FROM memory_l4_statements_fts f
            JOIN memory_l4_entity_statements s ON s.id = f.statement_id
            WHERE memory_l4_statements_fts MATCH \(store.quote(ftsQuery(text)))
            ORDER BY rank
            LIMIT \(limit - hits.count)
            """).map { row in
                let evidence = (try? store.decode([String].self, row[3])) ?? []
                return MemoryOSRetrievalHit(layer: .l4, recordID: row[0], title: row[1], summary: row[2], matchedText: row[2], score: score(fromFTSRank: row[6]), evidenceRefs: evidence, entityRefs: [row[4], row[5]].filter { !$0.isEmpty }, canExpandDepth: true, metadata: ["committed_at": row[7]])
            }
        }
        return hits
    }

    private func ftsQuery(_ text: String) -> String {
        let normalized = normalizedFTSTerms(text)
        return normalized.isEmpty ? text : normalized.joined(separator: " OR ")
    }

    private func normalizedFTSTerms(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let weakChinesePhrases = ["有哪些", "所有", "全部", "列出", "关于", "相关", "哪些", "什么", "请问", "一下"]
        var simplified = trimmed
        for phrase in weakChinesePhrases {
            simplified = simplified.replacingOccurrences(of: phrase, with: " ")
        }
        simplified = simplified.replacingOccurrences(of: "的", with: " ")

        var terms = simplified
            .split { $0.isWhitespace || $0.isPunctuation }
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let compact = trimmed.filter { !$0.isWhitespace && !$0.isPunctuation }
        let domainExpansions: [(String, [String])] = [
            ("国家", ["国家", "country", "主权国家", "主權國家"]),
            ("中國", ["中国", "中國", "中华人民共和国", "中華人民共和國", "China", "PRC"]),
            ("中国", ["中国", "中國", "中华人民共和国", "中華人民共和國", "China", "PRC"])
        ]
        for (needle, expansions) in domainExpansions where compact.contains(needle) || simplified.contains(needle) {
            terms.append(contentsOf: expansions)
        }

        if terms.isEmpty, !compact.isEmpty {
            terms.append(compact)
        }
        return Array(NSOrderedSet(array: terms).compactMap { $0 as? String })
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
