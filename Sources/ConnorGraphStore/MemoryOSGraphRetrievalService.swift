import Foundation
import ConnorGraphCore

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

public enum MemoryOSGraphQueryIntent: String, Sendable, Codable, Equatable, CaseIterable {
    case auto
    case l2Statements
    case l3Beliefs
    case l4Entity
    case l4Neighbors
    case l4Instances
    case evidence
}

public struct MemoryOSGraphQuery: Sendable, Codable, Equatable {
    public var text: String
    public var intent: MemoryOSGraphQueryIntent
    public var entityID: String?
    public var classEntityIDs: [String]
    public var predicates: [String]
    public var direction: MemoryOSGraphDirection
    public var includeEvidence: Bool
    public var limit: Int

    public init(text: String = "", intent: MemoryOSGraphQueryIntent = .auto, entityID: String? = nil, classEntityIDs: [String] = [], predicates: [String] = [], direction: MemoryOSGraphDirection = .both, includeEvidence: Bool = false, limit: Int = 50) {
        self.text = text
        self.intent = intent
        self.entityID = entityID
        self.classEntityIDs = classEntityIDs
        self.predicates = predicates
        self.direction = direction
        self.includeEvidence = includeEvidence
        self.limit = limit
    }
}

public struct MemoryOSEvidenceTraceQuery: Sendable, Codable, Equatable {
    public var spanIDs: [String]
    public var statementIDs: [String]
    public var beliefIDs: [String]
    public var limit: Int

    public init(spanIDs: [String] = [], statementIDs: [String] = [], beliefIDs: [String] = [], limit: Int = 100) {
        self.spanIDs = spanIDs
        self.statementIDs = statementIDs
        self.beliefIDs = beliefIDs
        self.limit = limit
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

public struct MemoryOSL3BeliefExpandQuery: Sendable, Codable, Equatable {
    public var beliefID: String?
    public var topic: String?
    public var text: String?
    public var limit: Int

    public init(beliefID: String? = nil, topic: String? = nil, text: String? = nil, limit: Int = 20) {
        self.beliefID = beliefID
        self.topic = topic
        self.text = text
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

    public init(classEntityIDs: [String], predicates: [String] = [MemoryOSL4RelationPredicate.instanceOf.rawValue], limit: Int = 100) {
        self.classEntityIDs = classEntityIDs
        self.predicates = predicates.isEmpty ? [MemoryOSL4RelationPredicate.instanceOf.rawValue] : predicates
        self.limit = limit
    }
}

public struct SQLiteMemoryOSGraphRetrievalService: Sendable {
    public var store: SQLiteMemoryOSStore

    public init(store: SQLiteMemoryOSStore) {
        self.store = store
    }

    public func queryGraph(_ query: MemoryOSGraphQuery) throws -> MemoryOSGraphSubgraph {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = min(max(query.limit, 1), 500)
        let predicates = query.predicates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var subgraphs: [MemoryOSGraphSubgraph] = []

        switch query.intent {
        case .l2Statements:
            subgraphs.append(try l2FindStatements(MemoryOSL2StatementFindQuery(text: text, predicates: predicates, limit: limit)))
        case .l3Beliefs:
            subgraphs.append(try l3ExpandBelief(MemoryOSL3BeliefExpandQuery(text: text, limit: min(limit, 100))))
        case .l4Entity:
            if !text.isEmpty { subgraphs.append(try l4FindEntity(MemoryOSL4EntityFindQuery(text: text, limit: min(limit, 100)))) }
        case .l4Neighbors:
            let entityID = try resolvedEntityID(explicit: query.entityID, text: text)
            if let entityID {
                subgraphs.append(try l4Neighbors(MemoryOSL4NeighborsQuery(entityID: entityID, direction: query.direction, predicates: predicates, limit: limit)))
            }
        case .l4Instances:
            var classIDs = query.classEntityIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if classIDs.isEmpty, !text.isEmpty {
                let resolved = try l4FindEntity(MemoryOSL4EntityFindQuery(text: text, limit: 5))
                subgraphs.append(resolved)
                classIDs = resolved.nodes.map(\.id)
            }
            if !classIDs.isEmpty {
                subgraphs.append(try l4Instances(MemoryOSL4InstanceQuery(classEntityIDs: classIDs, predicates: predicates.isEmpty ? [MemoryOSL4RelationPredicate.instanceOf.rawValue] : predicates, limit: limit)))
            }
        case .evidence:
            if !text.isEmpty {
                let statements = try l2FindStatements(MemoryOSL2StatementFindQuery(text: text, predicates: predicates, limit: limit))
                subgraphs.append(statements)
            }
        case .auto:
            if !text.isEmpty {
                subgraphs.append(try l4FindEntity(MemoryOSL4EntityFindQuery(text: text, limit: min(10, limit))))
                subgraphs.append(try l2FindStatements(MemoryOSL2StatementFindQuery(text: text, predicates: predicates, limit: min(50, limit))))
                subgraphs.append(try l3ExpandBelief(MemoryOSL3BeliefExpandQuery(text: text, limit: min(20, limit))))
            }
        }

        var merged = mergeSubgraphs(subgraphs, explanationPrefix: "Memory OS query_graph intent \(query.intent.rawValue)")
        if query.includeEvidence || query.intent == .evidence {
            let statementIDs = Set(merged.edges.filter { $0.layer == .l2 }.map(\.id) + merged.nodes.filter { $0.layer == .l2 }.map(\.id))
            let beliefIDs = Set(merged.nodes.filter { $0.layer == .l3 }.map(\.id))
            let trace = try traceEvidence(MemoryOSEvidenceTraceQuery(spanIDs: merged.evidenceRefs, statementIDs: Array(statementIDs), beliefIDs: Array(beliefIDs), limit: limit))
            merged = mergeSubgraphs([merged, trace], explanationPrefix: "Memory OS query_graph intent \(query.intent.rawValue) with evidence trace")
        }
        if merged.nodes.isEmpty && merged.edges.isEmpty {
            merged.explanation = "Memory OS query_graph intent \(query.intent.rawValue) returned no graph results."
        }
        return merged
    }

    public func traceEvidence(_ query: MemoryOSEvidenceTraceQuery) throws -> MemoryOSGraphSubgraph {
        let limit = min(max(query.limit, 1), 500)
        var spanIDs = Set(query.spanIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let statementIDs = Set(query.statementIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let beliefIDs = Set(query.beliefIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !spanIDs.isEmpty || !statementIDs.isEmpty || !beliefIDs.isEmpty else {
            return MemoryOSGraphSubgraph(explanation: "No span, statement, or belief ids were provided for evidence tracing.")
        }
        var nodes: [MemoryOSGraphNode] = []
        var edges: [MemoryOSGraphEdge] = []
        if !beliefIDs.isEmpty {
            let quoted = beliefIDs.map(store.quote).joined(separator: ",")
            let rows = try store.query(sql: """
            SELECT id, statement, domain, related_object_names, created_at, updated_at
            FROM memory_l3_beliefs
            WHERE id IN (\(quoted))
            LIMIT \(limit)
            """)
            for row in rows {
                nodes.append(MemoryOSGraphNode(
                    id: row[0],
                    layer: .l3,
                    kind: "statement",
                    title: row[1],
                    summary: row[1],
                    metadata: ["domain": row[2], "related_object_names": row[3], "created_at": row[4], "updated_at": row[5]]
                ))
            }
        }
        let allStatementIDs = statementIDs
        if !allStatementIDs.isEmpty {
            let quoted = allStatementIDs.map(store.quote).joined(separator: ",")
            let rows = try store.query(sql: """
            SELECT id, subject_id, predicate, COALESCE(object_id, ''), text, assertion_kind, evidence_span_ids_json
            FROM memory_l2_statements
            WHERE id IN (\(quoted))
            LIMIT \(limit)
            """)
            for row in rows {
                nodes.append(MemoryOSGraphNode(id: row[0], layer: .l2, kind: row[5], title: row[2], summary: row[4], metadata: ["subject_id": row[1], "object_id": row[3]]))
                let ids = (try? store.decode([String].self, row[6])) ?? []
                for spanID in ids where !spanID.isEmpty {
                    spanIDs.insert(spanID)
                    edges.append(MemoryOSGraphEdge(id: "\(row[0])->\(spanID)", layer: .l2, sourceID: row[0], targetID: spanID, predicate: "evidenced_by"))
                }
            }
        }
        var provenanceRefs: [String] = []
        if !spanIDs.isEmpty {
            let quoted = Array(spanIDs).prefix(limit).map(store.quote).joined(separator: ",")
            let rows = try store.query(sql: """
            SELECT sp.id, sp.provenance_object_id, sp.text, COALESCE(sp.start_offset, ''), COALESCE(sp.end_offset, ''), o.title, o.source_type, COALESCE(o.source_id, ''), o.occurred_at, o.confidentiality, substr(o.content, 1, 500)
            FROM memory_l0_provenance_spans sp
            JOIN memory_l0_provenance_objects o ON o.id = sp.provenance_object_id
            WHERE sp.id IN (\(quoted))
            ORDER BY o.occurred_at DESC, sp.id ASC
            LIMIT \(limit)
            """)
            for row in rows {
                provenanceRefs.append(row[1])
                nodes.append(MemoryOSGraphNode(id: row[0], layer: .l0, kind: "provenance_span", title: row[5], summary: row[2], metadata: ["provenance_object_id": row[1], "start_offset": row[3], "end_offset": row[4]]))
                nodes.append(MemoryOSGraphNode(id: row[1], layer: .l0, kind: row[6], title: row[5], summary: row[10], metadata: ["source_id": row[7], "occurred_at": row[8], "confidentiality": row[9]]))
                edges.append(MemoryOSGraphEdge(id: "\(row[0])->\(row[1])", layer: .l0, sourceID: row[0], targetID: row[1], predicate: "span_of"))
            }
        }
        var seen = Set<String>()
        let dedupedNodes = nodes.filter { seen.insert("\($0.layer.rawValue):\($0.id)").inserted }
        return MemoryOSGraphSubgraph(
            nodes: dedupedNodes,
            edges: edges,
            evidenceRefs: Array(spanIDs).sorted(),
            provenanceRefs: Array(Set(provenanceRefs)).sorted(),
            explanation: "Evidence trace returned \(dedupedNodes.count) node(s), \(edges.count) edge(s), \(spanIDs.count) span reference(s)."
        )
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

    public func l3ExpandBelief(_ query: MemoryOSL3BeliefExpandQuery) throws -> MemoryOSGraphSubgraph {
        let beliefID = query.beliefID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = query.topic?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = query.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(beliefID?.isEmpty ?? true) || !(domain?.isEmpty ?? true) || !(text?.isEmpty ?? true) else {
            return MemoryOSGraphSubgraph(explanation: "No L3 belief id, domain, or text query was provided.")
        }
        let limit = min(max(query.limit, 1), 100)
        var clauses: [String] = []
        if let beliefID, !beliefID.isEmpty { clauses.append("b.id = \(store.quote(beliefID))") }
        if let domain, !domain.isEmpty { clauses.append("b.domain = \(store.quote(MemoryOSBelief.normalizedDisciplineDomain(domain)))") }
        if let text, !text.isEmpty { clauses.append("b.statement LIKE \(store.quote("%\(text)%"))") }
        let beliefRows = try store.query(sql: """
        SELECT b.id, b.statement, b.domain, b.related_object_names, b.created_at, b.updated_at
        FROM memory_l3_beliefs b
        WHERE \(clauses.joined(separator: " AND "))
        ORDER BY b.updated_at DESC, b.id ASC
        LIMIT \(limit)
        """)
        let nodes = beliefRows.map { row in
            MemoryOSGraphNode(
                id: row[0],
                layer: .l3,
                kind: "statement",
                title: row[1],
                summary: row[1],
                metadata: ["domain": row[2], "related_object_names": row[3], "created_at": row[4], "updated_at": row[5]]
            )
        }
        return MemoryOSGraphSubgraph(
            nodes: nodes,
            edges: [],
            evidenceRefs: [],
            provenanceRefs: [],
            explanation: "L3 belief expansion returned \(beliefRows.count) statement node(s). L3 no longer stores supporting L2 evidence edges."
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
            let relationMetadata = l4RelationMetadata(predicate: row[2])
            return MemoryOSGraphEdge(
                id: row[0],
                layer: .l4,
                sourceID: row[1],
                targetID: row[3].isEmpty ? row[1] : row[3],
                predicate: row[2],
                evidenceRefs: evidence,
                confidence: Double(row[6]),
                validAt: row[7].isEmpty ? nil : row[7],
                metadata: ["statement_text": row[4], "direction": row[8]].merging(relationMetadata) { current, _ in current }
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
                metadata: ["statement_text": row[7]].merging(l4RelationMetadata(predicate: row[5])) { current, _ in current }
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

    private func resolvedEntityID(explicit: String?, text: String) throws -> String? {
        let explicitID = explicit?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitID, !explicitID.isEmpty { return explicitID }
        guard !text.isEmpty else { return nil }
        return try l4FindEntity(MemoryOSL4EntityFindQuery(text: text, limit: 1)).nodes.first?.id
    }

    private func mergeSubgraphs(_ subgraphs: [MemoryOSGraphSubgraph], explanationPrefix: String) -> MemoryOSGraphSubgraph {
        var nodesByKey: [String: MemoryOSGraphNode] = [:]
        var edgesByID: [String: MemoryOSGraphEdge] = [:]
        var evidenceRefs = Set<String>()
        var provenanceRefs = Set<String>()
        var explanations: [String] = []
        for subgraph in subgraphs {
            for node in subgraph.nodes { nodesByKey["\(node.layer.rawValue):\(node.id)"] = node }
            for edge in subgraph.edges { edgesByID[edge.id] = edge }
            evidenceRefs.formUnion(subgraph.evidenceRefs)
            provenanceRefs.formUnion(subgraph.provenanceRefs)
            if !subgraph.explanation.isEmpty { explanations.append(subgraph.explanation) }
        }
        let nodes = nodesByKey.values.sorted { lhs, rhs in
            if lhs.layer.rawValue != rhs.layer.rawValue { return lhs.layer.rawValue < rhs.layer.rawValue }
            return lhs.id < rhs.id
        }
        let edges = edgesByID.values.sorted { lhs, rhs in
            if lhs.layer.rawValue != rhs.layer.rawValue { return lhs.layer.rawValue < rhs.layer.rawValue }
            return lhs.id < rhs.id
        }
        let suffix = explanations.isEmpty ? "" : " " + explanations.joined(separator: " ")
        return MemoryOSGraphSubgraph(
            nodes: nodes,
            edges: edges,
            evidenceRefs: Array(evidenceRefs).sorted(),
            provenanceRefs: Array(provenanceRefs).sorted(),
            explanation: "\(explanationPrefix) returned \(nodes.count) node(s), \(edges.count) edge(s).\(suffix)"
        )
    }

    private func l4RelationMetadata(predicate rawValue: String) -> [String: String] {
        guard let predicate = MemoryOSL4RelationPredicate(rawValue: rawValue) else {
            return ["relation_category": "unknown", "retrieval_weight": "1.0"]
        }
        return [
            "relation_category": predicate.category.rawValue,
            "retrieval_weight": String(predicate.retrievalWeight),
            "relation_strict": String(predicate.isStrict)
        ]
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
