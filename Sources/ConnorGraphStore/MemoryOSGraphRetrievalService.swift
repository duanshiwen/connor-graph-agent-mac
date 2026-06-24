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
}
