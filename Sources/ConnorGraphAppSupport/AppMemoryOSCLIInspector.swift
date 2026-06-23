import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct AppMemoryOSCLIInspector: Sendable {
    public var store: SQLiteMemoryOSStore
    public var databasePath: String

    public init(store: SQLiteMemoryOSStore, databasePath: String = "memory-os.sqlite") {
        self.store = store
        self.databasePath = databasePath
    }

    public func status(now: Date = Date()) throws -> MemoryOSCLIStatus {
        let health = try store.schemaHealthReport(now: now)
        let queue = try store.queueOperationalSnapshot(now: now)
        let layers = try layerCounts()
        return MemoryOSCLIStatus(
            databasePath: databasePath,
            schema: MemoryOSCLISchemaStatus(
                expectedVersion: health.expectedVersion,
                actualVersion: health.actualVersion,
                health: health.status.rawValue,
                missingTables: health.missingTables,
                missingIndexes: health.missingIndexes
            ),
            layers: MemoryOSCLIStatusLayerCounts(
                l0ProvenanceObjects: layers.l0.objects,
                l0ProvenanceSpans: layers.l0.spans,
                l1CaptureEvents: layers.l1.captureEvents,
                l1PendingCaptureEvents: layers.l1.pending,
                l1QueueItems: layers.l1.queueItems,
                l2Nodes: layers.l2.nodes,
                l2Statements: layers.l2.statements,
                l2PendingKnowledge: layers.l2.knowledgePending,
                l3Beliefs: layers.l3.beliefs,
                l4Entities: layers.l4.entities,
                l4EntityStatements: layers.l4.entityStatements
            ),
            queue: MemoryOSCLIQueueCounts(
                pending: queue.pending,
                leased: queue.leased,
                processing: queue.processing,
                retryScheduled: queue.retryScheduled,
                succeeded: queue.succeeded,
                failed: queue.failed,
                deadLetter: queue.deadLetter,
                expiredLeases: queue.expiredLeases
            )
        )
    }

    public func stats() throws -> MemoryOSCLIStats {
        var tables: [String: Int] = [:]
        for table in MemoryOSCLIInspectorTable.defaultTables {
            tables[table] = try count(table)
        }
        return MemoryOSCLIStats(tables: tables)
    }

    public func layers() throws -> MemoryOSCLILayerSummary {
        try layerCounts()
    }

    private func layerCounts() throws -> MemoryOSCLILayerSummary {
        MemoryOSCLILayerSummary(
            l0: MemoryOSCLIL0Counts(
                objects: try count("memory_l0_provenance_objects"),
                spans: try count("memory_l0_provenance_spans")
            ),
            l1: MemoryOSCLIL1Counts(
                captureEvents: try count("memory_l1_capture_events"),
                pending: try count("memory_l1_capture_events", where: "processing_state IN ('pending', 'queued')"),
                queueItems: try count("memory_l1_processing_queue"),
                deadLetters: try count("memory_l1_dead_letter_queue")
            ),
            l2: MemoryOSCLIL2Counts(
                nodes: try count("memory_l2_nodes"),
                statements: try count("memory_l2_statements"),
                knowledgePending: try count("memory_l2_statement_processing_state", where: "processing_kind = 'knowledge_synthesis' AND status = 'pending'"),
                processingStates: try count("memory_l2_statement_processing_state")
            ),
            l3: MemoryOSCLIL3Counts(
                beliefs: try count("memory_l3_beliefs")
            ),
            l4: MemoryOSCLIL4Counts(
                entities: try count("memory_l4_entities"),
                entityStatements: try count("memory_l4_entity_statements")
            )
        )
    }

    private func count(_ table: String, where predicate: String? = nil) throws -> Int {
        let whereClause = predicate.map { " WHERE \($0)" } ?? ""
        return Int(try store.query(sql: "SELECT COUNT(*) FROM \(table)\(whereClause);").first?.first ?? "0") ?? 0
    }
}

private enum MemoryOSCLIInspectorTable {
    static let defaultTables = [
        "memory_l0_provenance_objects",
        "memory_l0_provenance_spans",
        "memory_l1_capture_events",
        "memory_l1_processing_queue",
        "memory_l1_dead_letter_queue",
        "memory_l2_nodes",
        "memory_l2_statements",
        "memory_l2_statement_processing_state",
        "memory_l3_beliefs",
        "memory_l4_entities",
        "memory_l4_entity_statements"
    ]
}

public struct MemoryOSCLIStatus: Codable, Sendable, Equatable {
    public var databasePath: String
    public var schema: MemoryOSCLISchemaStatus
    public var layers: MemoryOSCLIStatusLayerCounts
    public var queue: MemoryOSCLIQueueCounts

    enum CodingKeys: String, CodingKey {
        case databasePath = "database_path"
        case schema
        case layers
        case queue
    }
}

public struct MemoryOSCLISchemaStatus: Codable, Sendable, Equatable {
    public var expectedVersion: Int
    public var actualVersion: Int
    public var health: String
    public var missingTables: [String]
    public var missingIndexes: [String]

    enum CodingKeys: String, CodingKey {
        case expectedVersion = "expected_version"
        case actualVersion = "actual_version"
        case health
        case missingTables = "missing_tables"
        case missingIndexes = "missing_indexes"
    }
}

public struct MemoryOSCLIStatusLayerCounts: Codable, Sendable, Equatable {
    public var l0ProvenanceObjects: Int
    public var l0ProvenanceSpans: Int
    public var l1CaptureEvents: Int
    public var l1PendingCaptureEvents: Int
    public var l1QueueItems: Int
    public var l2Nodes: Int
    public var l2Statements: Int
    public var l2PendingKnowledge: Int
    public var l3Beliefs: Int
    public var l4Entities: Int
    public var l4EntityStatements: Int

    enum CodingKeys: String, CodingKey {
        case l0ProvenanceObjects = "l0_provenance_objects"
        case l0ProvenanceSpans = "l0_provenance_spans"
        case l1CaptureEvents = "l1_capture_events"
        case l1PendingCaptureEvents = "l1_pending_capture_events"
        case l1QueueItems = "l1_queue_items"
        case l2Nodes = "l2_nodes"
        case l2Statements = "l2_statements"
        case l2PendingKnowledge = "l2_pending_knowledge"
        case l3Beliefs = "l3_beliefs"
        case l4Entities = "l4_entities"
        case l4EntityStatements = "l4_entity_statements"
    }
}

public struct MemoryOSCLIQueueCounts: Codable, Sendable, Equatable {
    public var pending: Int
    public var leased: Int
    public var processing: Int
    public var retryScheduled: Int
    public var succeeded: Int
    public var failed: Int
    public var deadLetter: Int
    public var expiredLeases: Int

    enum CodingKeys: String, CodingKey {
        case pending
        case leased
        case processing
        case retryScheduled = "retry_scheduled"
        case succeeded
        case failed
        case deadLetter = "dead_letter"
        case expiredLeases = "expired_leases"
    }
}

public struct MemoryOSCLIStats: Codable, Sendable, Equatable {
    public var tables: [String: Int]
}

public struct MemoryOSCLILayerSummary: Codable, Sendable, Equatable {
    public var l0: MemoryOSCLIL0Counts
    public var l1: MemoryOSCLIL1Counts
    public var l2: MemoryOSCLIL2Counts
    public var l3: MemoryOSCLIL3Counts
    public var l4: MemoryOSCLIL4Counts

    enum CodingKeys: String, CodingKey {
        case l0 = "L0"
        case l1 = "L1"
        case l2 = "L2"
        case l3 = "L3"
        case l4 = "L4"
    }
}

public struct MemoryOSCLIL0Counts: Codable, Sendable, Equatable {
    public var objects: Int
    public var spans: Int
}

public struct MemoryOSCLIL1Counts: Codable, Sendable, Equatable {
    public var captureEvents: Int
    public var pending: Int
    public var queueItems: Int
    public var deadLetters: Int

    enum CodingKeys: String, CodingKey {
        case captureEvents = "capture_events"
        case pending
        case queueItems = "queue_items"
        case deadLetters = "dead_letters"
    }
}

public struct MemoryOSCLIL2Counts: Codable, Sendable, Equatable {
    public var nodes: Int
    public var statements: Int
    public var knowledgePending: Int
    public var processingStates: Int

    enum CodingKeys: String, CodingKey {
        case nodes
        case statements
        case knowledgePending = "knowledge_pending"
        case processingStates = "processing_states"
    }
}

public struct MemoryOSCLIL3Counts: Codable, Sendable, Equatable {
    public var beliefs: Int
}

public struct MemoryOSCLIL4Counts: Codable, Sendable, Equatable {
    public var entities: Int
    public var entityStatements: Int

    enum CodingKeys: String, CodingKey {
        case entities
        case entityStatements = "entity_statements"
    }
}
