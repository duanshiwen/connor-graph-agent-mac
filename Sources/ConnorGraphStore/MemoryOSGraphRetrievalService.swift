import Foundation

public enum MemoryOSGraphLayer: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case l0 = "L0"
    case l1 = "L1"
    case l2 = "L2"
    case l3 = "L3"
    case l4 = "L4"
}

public enum MemoryOSGraphDirection: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case outgoing
    case incoming
    case both
}

public struct MemoryOSGraphNode: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var layer: MemoryOSGraphLayer
    public var kind: String
    public var title: String
    public var summary: String
    public var metadata: [String: String]

    public init(id: String, layer: MemoryOSGraphLayer, kind: String, title: String, summary: String = "", metadata: [String: String] = [:]) {
        self.id = id
        self.layer = layer
        self.kind = kind
        self.title = title
        self.summary = summary
        self.metadata = metadata
    }
}

public struct MemoryOSGraphEdge: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var layer: MemoryOSGraphLayer
    public var sourceID: String
    public var targetID: String
    public var predicate: String
    public var evidenceRefs: [String]
    public var confidence: Double?
    public var validAt: String?
    public var metadata: [String: String]

    public init(id: String, layer: MemoryOSGraphLayer, sourceID: String, targetID: String, predicate: String, evidenceRefs: [String] = [], confidence: Double? = nil, validAt: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.layer = layer
        self.sourceID = sourceID
        self.targetID = targetID
        self.predicate = predicate
        self.evidenceRefs = evidenceRefs
        self.confidence = confidence
        self.validAt = validAt
        self.metadata = metadata
    }
}

public struct MemoryOSGraphSubgraph: Sendable, Codable, Equatable {
    public var nodes: [MemoryOSGraphNode]
    public var edges: [MemoryOSGraphEdge]
    public var evidenceRefs: [String]
    public var provenanceRefs: [String]
    public var explanation: String

    public init(nodes: [MemoryOSGraphNode] = [], edges: [MemoryOSGraphEdge] = [], evidenceRefs: [String] = [], provenanceRefs: [String] = [], explanation: String = "") {
        self.nodes = nodes
        self.edges = edges
        self.evidenceRefs = evidenceRefs
        self.provenanceRefs = provenanceRefs
        self.explanation = explanation
    }
}

public struct MemoryOSL2StatementFindQuery: Sendable, Codable, Equatable {
    public var text: String
    public var subjectID: String?
    public var predicates: [String]
    public var limit: Int

    public init(text: String = "", subjectID: String? = nil, predicates: [String] = [], limit: Int = 50) {
        self.text = text
        self.subjectID = subjectID
        self.predicates = predicates
        self.limit = limit
    }
}

public struct MemoryOSL4EntityFindQuery: Sendable, Codable, Equatable {
    public var text: String
    public var limit: Int

    public init(text: String, limit: Int = 20) {
        self.text = text
        self.limit = limit
    }
}

public struct MemoryOSL4NeighborsQuery: Sendable, Codable, Equatable {
    public var entityID: String
    public var direction: MemoryOSGraphDirection
    public var predicates: [String]
    public var limit: Int

    public init(entityID: String, direction: MemoryOSGraphDirection = .both, predicates: [String] = [], limit: Int = 100) {
        self.entityID = entityID
        self.direction = direction
        self.predicates = predicates
        self.limit = limit
    }
}

public struct MemoryOSL4InstanceQuery: Sendable, Codable, Equatable {
    public var classEntityIDs: [String]
    public var predicates: [String]
    public var limit: Int

    public init(classEntityIDs: [String], predicates: [String] = ["P31"], limit: Int = 100) {
        self.classEntityIDs = classEntityIDs
        self.predicates = predicates.isEmpty ? ["P31"] : predicates
        self.limit = limit
    }
}

public struct SQLiteMemoryOSGraphRetrievalService: Sendable {
    public var store: SQLiteMemoryOSStore

    public init(store: SQLiteMemoryOSStore) {
        self.store = store
    }

    public func l2FindStatements(_ query: MemoryOSL2StatementFindQuery) throws -> MemoryOSGraphSubgraph {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectID = query.subjectID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicates = query.predicates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !text.isEmpty || !(subjectID?.isEmpty ?? true) || !predicates.isEmpty else {
            return MemoryOSGraphSubgraph(explanation: "No L2 statement query, subject id, or predicate filter was provided.")
        }
        let limit = min(max(query.limit, 1), 500)
        var clauses: [String] = []
        if let subjectID, !subjectID.isEmpty { clauses.append("s.subject_id = \(store.quote(subjectID))") }
        if !predicates.isEmpty { clauses.append("s.predicate IN (\(predicates.map(store.quote).joined(separator: ",")))") }
        if !text.isEmpty {
            let like = store.quote("%\(text)%")
            clauses.append("(s.text LIKE \(like) OR s.subject_id LIKE \(like) OR s.object_id LIKE \(like) OR s.predicate LIKE \(like))")
        }
        let rows = try store.query(sql: """
        SELECT s.id, s.subject_id, s.predicate, COALESCE(s.object_id, ''), s.text, s.assertion_kind, s.confidence, s.valid_at, s.evidence_span_ids_json, COALESCE(n.node_type, ''), COALESCE(n.name, '')
        FROM memory_l2_statements s
        LEFT JOIN memory_l2_nodes n ON n.id = s.subject_id
        WHERE \(clauses.joined(separator: " AND "))
        ORDER BY s.valid_at DESC, s.confidence DESC, s.committed_at DESC, s.id ASC
        LIMIT \(limit)
        """)
        var nodesByID: [String: MemoryOSGraphNode] = [:]
        var evidenceRefs: [String] = []
        let edges = rows.map { row in
            let subjectTitle = row[10].isEmpty ? row[1] : row[10]
            nodesByID[row[1]] = MemoryOSGraphNode(id: row[1], layer: .l2, kind: row[9].isEmpty ? "l2_subject" : row[9], title: subjectTitle)
            if !row[3].isEmpty {
                nodesByID[row[3]] = MemoryOSGraphNode(id: row[3], layer: .l2, kind: "l2_object", title: row[3])
            }
            let evidence = (try? store.decode([String].self, row[8])) ?? []
            evidenceRefs.append(contentsOf: evidence)
            return MemoryOSGraphEdge(
                id: row[0],
                layer: .l2,
                sourceID: row[1],
                targetID: row[3].isEmpty ? row[1] : row[3],
                predicate: row[2],
                evidenceRefs: evidence,
                confidence: Double(row[6]),
                validAt: row[7],
                metadata: ["statement_text": row[4], "assertion_kind": row[5]]
            )
        }
        return MemoryOSGraphSubgraph(
            nodes: Array(nodesByID.values).sorted { $0.id < $1.id },
            edges: edges,
            evidenceRefs: Array(Set(evidenceRefs)).sorted(),
            provenanceRefs: [],
            explanation: "L2 statement query returned \(edges.count) statement edge(s)."
        )
    }

    public func l4FindEntity(_ query: MemoryOSL4EntityFindQuery) throws -> MemoryOSGraphSubgraph {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return MemoryOSGraphSubgraph(explanation: "No entity search text was provided.") }
        let limit = min(max(query.limit, 1), 100)
        let quoted = store.quote(text)
        let like = store.quote("%\(text)%")
        let rows = try store.query(sql: """
        SELECT DISTINCT e.id, e.entity_type, e.name, e.summary,
               CASE
                 WHEN e.id = \(quoted) THEN 100
                 WHEN e.stable_key = \(quoted) THEN 95
                 WHEN e.name = \(quoted) THEN 90
                 WHEN EXISTS (SELECT 1 FROM memory_l4_entity_aliases a WHERE a.entity_id = e.id AND a.alias = \(quoted)) THEN 85
                 WHEN e.name LIKE \(like) THEN 50
                 ELSE 25
               END AS rank_score
        FROM memory_l4_entities e
        LEFT JOIN memory_l4_entity_aliases a ON a.entity_id = e.id
        WHERE e.id = \(quoted)
           OR e.stable_key = \(quoted)
           OR e.name = \(quoted)
           OR e.name LIKE \(like)
           OR a.alias = \(quoted)
           OR a.alias LIKE \(like)
        ORDER BY rank_score DESC, e.name ASC, e.id ASC
        LIMIT \(limit)
        """)
        let nodes = rows.map { row in
            MemoryOSGraphNode(id: row[0], layer: .l4, kind: row[1], title: row[2], summary: row[3], metadata: ["rank_score": row[4]])
        }
        return MemoryOSGraphSubgraph(nodes: nodes, explanation: "L4 entity find query: \(text); returned \(nodes.count) entity node(s).")
    }

    public func l4Neighbors(_ query: MemoryOSL4NeighborsQuery) throws -> MemoryOSGraphSubgraph {
        let entityID = query.entityID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entityID.isEmpty else { return MemoryOSGraphSubgraph(explanation: "No entity id was provided.") }
        let limit = min(max(query.limit, 1), 1_000)
        let predicateClause = query.predicates.isEmpty ? "" : " AND s.predicate IN (\(query.predicates.map(store.quote).joined(separator: ",")))"
        var statements: [[String]] = []
        if query.direction == .outgoing || query.direction == .both {
            statements += try store.query(sql: """
            SELECT s.id, s.entity_id, s.predicate, COALESCE(s.object_entity_id, ''), s.text, s.evidence_span_ids_json, s.confidence, s.valid_at, 'outgoing'
            FROM memory_l4_entity_statements s
            WHERE s.entity_id = \(store.quote(entityID))\(predicateClause)
            ORDER BY s.committed_at DESC, s.id ASC
            LIMIT \(limit)
            """)
        }
        if query.direction == .incoming || query.direction == .both {
            statements += try store.query(sql: """
            SELECT s.id, s.entity_id, s.predicate, COALESCE(s.object_entity_id, ''), s.text, s.evidence_span_ids_json, s.confidence, s.valid_at, 'incoming'
            FROM memory_l4_entity_statements s
            WHERE s.object_entity_id = \(store.quote(entityID))\(predicateClause)
            ORDER BY s.committed_at DESC, s.id ASC
            LIMIT \(limit)
            """)
        }
        statements = Array(statements.prefix(limit))

        var nodeIDs = Set([entityID])
        for row in statements {
            nodeIDs.insert(row[1])
            if !row[3].isEmpty { nodeIDs.insert(row[3]) }
        }
        let nodes = try l4Nodes(ids: Array(nodeIDs))
        var evidenceRefs: [String] = []
        let edges = statements.map { row in
            let evidence = (try? store.decode([String].self, row[5])) ?? []
            evidenceRefs.append(contentsOf: evidence)
            return MemoryOSGraphEdge(
                id: row[0],
                layer: .l4,
                sourceID: row[1],
                targetID: row[3].isEmpty ? row[1] : row[3],
                predicate: row[2],
                evidenceRefs: evidence,
                confidence: Double(row[6]),
                validAt: row[7].isEmpty ? nil : row[7],
                metadata: ["statement_text": row[4], "direction": row[8]]
            )
        }
        return MemoryOSGraphSubgraph(nodes: nodes, edges: edges, evidenceRefs: Array(Set(evidenceRefs)).sorted(), provenanceRefs: [], explanation: "L4 neighbors query: entity \(entityID), direction \(query.direction.rawValue); returned \(edges.count) edge(s).")
    }

    public func l4Instances(_ query: MemoryOSL4InstanceQuery) throws -> MemoryOSGraphSubgraph {
        let classIDs = query.classEntityIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !classIDs.isEmpty else {
            return MemoryOSGraphSubgraph(explanation: "No class entity ids were provided.")
        }
        let predicates = query.predicates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let quotedClassIDs = classIDs.map(store.quote).joined(separator: ",")
        let quotedPredicates = predicates.map(store.quote).joined(separator: ",")
        let limit = min(max(query.limit, 1), 1_000)

        let classRows = try store.query(sql: """
        SELECT id, entity_type, name, summary
        FROM memory_l4_entities
        WHERE id IN (\(quotedClassIDs))
        ORDER BY id ASC
        """)
        let classNodes = classRows.map { row in
            MemoryOSGraphNode(id: row[0], layer: .l4, kind: row[1].isEmpty ? "class" : row[1], title: row[2], summary: row[3], metadata: ["role": "class"])
        }

        let rows = try store.query(sql: """
        SELECT e.id, e.entity_type, e.name, e.summary, s.id, s.predicate, s.object_entity_id, s.text, s.evidence_span_ids_json, s.confidence, s.valid_at
        FROM memory_l4_entity_statements s
        JOIN memory_l4_entities e ON e.id = s.entity_id
        WHERE s.predicate IN (\(quotedPredicates))
          AND s.object_entity_id IN (\(quotedClassIDs))
        ORDER BY e.name ASC, e.id ASC
        LIMIT \(limit)
        """)

        var nodes = classNodes
        var edges: [MemoryOSGraphEdge] = []
        var evidenceRefs: [String] = []
        var seenNodes = Set(nodes.map(\.id))

        for row in rows {
            let entityID = row[0]
            if seenNodes.insert(entityID).inserted {
                nodes.append(MemoryOSGraphNode(id: entityID, layer: .l4, kind: row[1], title: row[2], summary: row[3], metadata: ["role": "instance"]))
            }
            let evidence = (try? store.decode([String].self, row[8])) ?? []
            evidenceRefs.append(contentsOf: evidence)
            edges.append(MemoryOSGraphEdge(
                id: row[4],
                layer: .l4,
                sourceID: entityID,
                targetID: row[6],
                predicate: row[5],
                evidenceRefs: evidence,
                confidence: Double(row[9]),
                validAt: row[10].isEmpty ? nil : row[10],
                metadata: ["statement_text": row[7]]
            ))
        }

        return MemoryOSGraphSubgraph(
            nodes: nodes,
            edges: edges,
            evidenceRefs: Array(Set(evidenceRefs)).sorted(),
            provenanceRefs: [],
            explanation: "L4 instances query: predicates \(predicates.joined(separator: ",")) -> classes \(classIDs.joined(separator: ",")); returned \(rows.count) instance edge(s)."
        )
    }

    private func l4Nodes(ids: [String]) throws -> [MemoryOSGraphNode] {
        let cleanIDs = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleanIDs.isEmpty else { return [] }
        let quoted = cleanIDs.map(store.quote).joined(separator: ",")
        let rows = try store.query(sql: """
        SELECT id, entity_type, name, summary
        FROM memory_l4_entities
        WHERE id IN (\(quoted))
        ORDER BY name ASC, id ASC
        """)
        var nodes = rows.map { row in MemoryOSGraphNode(id: row[0], layer: .l4, kind: row[1], title: row[2], summary: row[3]) }
        let known = Set(nodes.map(\.id))
        for missing in cleanIDs where !known.contains(missing) {
            nodes.append(MemoryOSGraphNode(id: missing, layer: .l4, kind: "external_or_literal", title: missing))
        }
        return nodes
    }
}
