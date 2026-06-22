import Foundation
import SQLite3
import ConnorGraphCore

public enum SQLiteMemoryOSStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case decodeFailed(String)
    case missingRecord(String)

    public var description: String {
        switch self {
        case .openFailed(let message): "openFailed: \(message)"
        case .executeFailed(let message): "executeFailed: \(message)"
        case .prepareFailed(let message): "prepareFailed: \(message)"
        case .stepFailed(let message): "stepFailed: \(message)"
        case .decodeFailed(let message): "decodeFailed: \(message)"
        case .missingRecord(let message): "missingRecord: \(message)"
        }
    }
}

public final class SQLiteMemoryOSStore: @unchecked Sendable {
    public static let currentSchemaVersion = 3

    public static let requiredSchemaTables: Set<String> = [
        "memory_schema_migrations", "memory_legacy_import_runs", "memory_store_health_checks",
        "memory_audit_events", "memory_processing_metrics", "memory_error_events", "memory_recovery_actions",
        "memory_discard_events",
        "memory_l0_provenance_objects", "memory_l0_provenance_spans", "memory_l0_derivations", "memory_l0_content_hashes",
        "memory_l1_capture_events", "memory_l1_time_blocks", "memory_l1_time_block_events", "memory_l1_processing_queue", "memory_l1_queue_attempts", "memory_l1_dead_letter_queue",
        "memory_l2_nodes", "memory_l2_edges", "memory_l2_statements", "memory_l2_statement_evidence", "memory_l2_statement_processing_state", "memory_l2_episodes", "memory_l2_processing_runs", "memory_l2_processing_artifacts", "memory_l2_projections", "memory_l2_projection_items",
        "memory_l3_beliefs", "memory_l3_belief_evidence", "memory_l3_belief_relations", "memory_l3_promotion_records",
        "memory_l4_entities", "memory_l4_entity_aliases", "memory_l4_entity_statements", "memory_l4_entity_statement_evidence", "memory_l4_archive_runs", "memory_l4_archive_statement_links", "memory_l4_merge_events", "memory_l4_split_events",
        "memory_l0_provenance_fts", "memory_l2_nodes_fts", "memory_l2_statements_fts", "memory_l3_beliefs_fts", "memory_l4_entities_fts", "memory_l4_statements_fts"
    ]

    public static let requiredSchemaIndexes: Set<String> = [
        "idx_memory_l0_provenance_source", "idx_memory_l0_provenance_time", "idx_memory_l0_spans_object",
        "idx_memory_l1_capture_state", "idx_memory_l1_time_blocks_status", "idx_memory_l1_queue_runnable", "idx_memory_l1_queue_idempotency",
        "idx_memory_l2_nodes_key", "idx_memory_l2_statements_subject", "idx_memory_l2_statements_temporal", "idx_memory_l2_statement_evidence_statement", "idx_memory_l2_processing_state",
        "idx_memory_l3_beliefs_topic", "idx_memory_l3_beliefs_temporal", "idx_memory_l3_belief_evidence_belief",
        "idx_memory_l4_entities_key", "idx_memory_l4_aliases_entity", "idx_memory_l4_statements_entity", "idx_memory_l4_statement_evidence_statement",
        "idx_memory_audit_events_time", "idx_memory_error_events_time"
    ]

    private var db: OpaquePointer?
    private let databaseLock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(path: String) throws {
        encoder.outputFormatting = [.sortedKeys]
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw SQLiteMemoryOSStoreError.openFailed(Self.message(db))
        }
        try configurePragmas()
    }

    deinit {
        databaseLock.lock()
        sqlite3_close(db)
        db = nil
        databaseLock.unlock()
    }

    public func configurePragmas() throws {
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try execute("PRAGMA busy_timeout = 5000;")
        try execute("PRAGMA temp_store = MEMORY;")
    }

    public func migrate() throws {
        try configurePragmas()
        try execute(Self.schemaSQL)
        try execute("PRAGMA user_version = \(Self.currentSchemaVersion);")
        try execute("""
        INSERT OR REPLACE INTO memory_schema_migrations(version, name, applied_at, metadata_json)
        VALUES (\(Self.currentSchemaVersion), 'memory_os_background_pipeline_schema', \(quote(iso(Date()))), '{}')
        """)
    }

    public func schemaUserVersion() throws -> Int {
        Int(try query(sql: "PRAGMA user_version;").first?.first ?? "0") ?? 0
    }

    public func tableNames() throws -> Set<String> {
        Set(try queryStrings(sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"))
    }

    public func indexNames() throws -> Set<String> {
        Set(try queryStrings(sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
    }

    public func schemaHealthReport(now: Date = Date()) throws -> MemoryOSStoreHealthReport {
        let actualVersion = try schemaUserVersion()
        let tables = try tableNames()
        let indexes = try indexNames()
        let missingTables = Self.requiredSchemaTables.subtracting(tables).sorted()
        let missingIndexes = Self.requiredSchemaIndexes.subtracting(indexes).sorted()
        let status: MemoryOSHealthStatus
        if actualVersion < Self.currentSchemaVersion {
            status = .migrationRequired
        } else if missingTables.isEmpty && missingIndexes.isEmpty {
            status = .healthy
        } else {
            status = .warning
        }
        return MemoryOSStoreHealthReport(expectedVersion: Self.currentSchemaVersion, actualVersion: actualVersion, status: status, missingTables: missingTables, missingIndexes: missingIndexes, checkedAt: now)
    }

    public func pragmaValue(_ name: String) throws -> String? {
        try query(sql: "PRAGMA \(name);").first?.first
    }

    // MARK: - L0

    public func upsert(provenance object: MemoryOSProvenanceObject) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l0_provenance_objects
        (id, source_type, source_id, title, content, content_hash, occurred_at, ingested_at, session_id, work_object_id, confidentiality, status, metadata_json)
        VALUES (\(quote(object.id)), \(quote(object.sourceType.rawValue)), \(quote(object.sourceID)), \(quote(object.title)), \(quote(object.content)), \(quote(object.contentHash)), \(quote(iso(object.occurredAt))), \(quote(iso(object.ingestedAt))), \(quote(object.sessionID)), \(quote(object.workObjectID)), \(quote(object.confidentiality.rawValue)), \(quote(object.status.rawValue)), \(quote(json(object.metadata))))
        """)
        try execute("DELETE FROM memory_l0_provenance_fts WHERE object_id = \(quote(object.id));")
        try execute("""
        INSERT INTO memory_l0_provenance_fts(object_id, source_type, title, content)
        VALUES (\(quote(object.id)), \(quote(object.sourceType.rawValue)), \(quote(object.title)), \(quote(object.content)))
        """)
    }

    public func provenanceObject(id: String) throws -> MemoryOSProvenanceObject? {
        try query(sql: """
        SELECT id, source_type, source_id, title, content, content_hash, occurred_at, ingested_at, session_id, work_object_id, confidentiality, status, metadata_json
        FROM memory_l0_provenance_objects WHERE id = \(quote(id)) LIMIT 1
        """).map(decodeProvenanceObject).first
    }

    public func upsert(span: MemoryOSProvenanceSpan) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l0_provenance_spans
        (id, provenance_object_id, start_offset, end_offset, text, metadata_json)
        VALUES (\(quote(span.id)), \(quote(span.provenanceObjectID)), \(quote(span.startOffset.map(String.init))), \(quote(span.endOffset.map(String.init))), \(quote(span.text)), \(quote(json(span.metadata))))
        """)
    }

    // MARK: - L1

    public func upsert(captureEvent event: MemoryOSCaptureEvent) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l1_capture_events
        (id, provenance_object_id, event_type, occurred_at, token_estimate, processing_state, metadata_json)
        VALUES (\(quote(event.id)), \(quote(event.provenanceObjectID)), \(quote(event.eventType)), \(quote(iso(event.occurredAt))), \(event.tokenEstimate), \(quote(event.processingState.rawValue)), \(quote(json(event.metadata))))
        """)
    }

    public func upsert(timeBlock block: MemoryOSTimeBlock) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l1_time_blocks
        (id, title, started_at, ended_at, token_estimate, status, metadata_json)
        VALUES (\(quote(block.id)), \(quote(block.title)), \(quote(iso(block.startedAt))), \(quote(iso(block.endedAt))), \(block.tokenEstimate), \(quote(block.status.rawValue)), \(quote(json(block.metadata))))
        """)
    }

    public func enqueue(_ item: MemoryOSQueueItem) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l1_processing_queue
        (id, kind, status, priority, payload_json, attempt_count, max_attempts, next_run_at, locked_at, locked_by, lease_expires_at, idempotency_key, payload_hash, created_at, updated_at, error_code, error_message)
        VALUES (\(quote(item.id)), \(quote(item.kind)), \(quote(item.status.rawValue)), \(item.priority), \(quote(item.payloadJSON)), \(item.attemptCount), \(item.maxAttempts), \(quote(iso(item.nextRunAt))), \(quote(item.lockedAt.map(iso))), \(quote(item.lockedBy)), \(quote(item.leaseExpiresAt.map(iso))), \(quote(item.idempotencyKey)), \(quote(item.payloadHash)), \(quote(iso(item.createdAt))), \(quote(iso(item.updatedAt))), \(quote(item.errorCode)), \(quote(item.errorMessage)))
        """)
    }

    public func saveQueueAttempt(queueItemID: String, attemptNumber: Int, status: MemoryOSQueueStatus, startedAt: Date, finishedAt: Date? = nil, errorCode: String? = nil, errorMessage: String? = nil, metadata: [String: String] = [:]) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l1_queue_attempts
        (id, queue_item_id, attempt_number, status, started_at, finished_at, error_code, error_message, metadata_json)
        VALUES (\(quote("\(queueItemID):attempt:\(attemptNumber)")), \(quote(queueItemID)), \(attemptNumber), \(quote(status.rawValue)), \(quote(iso(startedAt))), \(quote(finishedAt.map(iso))), \(quote(errorCode)), \(quote(errorMessage)), \(quote(json(metadata))))
        """)
    }

    public func saveDeadLetter(queueItem item: MemoryOSQueueItem, now: Date = Date(), metadata: [String: String] = [:]) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l1_dead_letter_queue
        (id, queue_item_id, failed_payload_json, error_code, error_message, created_at, metadata_json)
        VALUES (\(quote("dead:\(item.id)")), \(quote(item.id)), \(quote(item.payloadJSON)), \(quote(item.errorCode ?? "unknown_error")), \(quote(item.errorMessage ?? "Unknown Memory OS processing error")), \(quote(iso(now))), \(quote(json(metadata))))
        """)
    }

    public func queueItem(id: String) throws -> MemoryOSQueueItem? {
        try query(sql: """
        SELECT id, kind, status, priority, payload_json, attempt_count, max_attempts, next_run_at, locked_at, locked_by, lease_expires_at, idempotency_key, payload_hash, created_at, updated_at, error_code, error_message
        FROM memory_l1_processing_queue WHERE id = \(quote(id)) LIMIT 1
        """).map(decodeQueueItem).first
    }

    public func runnableQueueItems(kind: String? = nil, limit: Int = 10, now: Date = Date()) throws -> [MemoryOSQueueItem] {
        let kindClause = kind.map { " AND kind = \(quote($0))" } ?? ""
        return try query(sql: """
        SELECT id, kind, status, priority, payload_json, attempt_count, max_attempts, next_run_at, locked_at, locked_by, lease_expires_at, idempotency_key, payload_hash, created_at, updated_at, error_code, error_message
        FROM memory_l1_processing_queue
        WHERE status IN ('pending', 'retry_scheduled') AND next_run_at <= \(quote(iso(now)))\(kindClause)
        ORDER BY priority DESC, next_run_at ASC
        LIMIT \(limit)
        """).map(decodeQueueItem)
    }

    public func leaseQueueItem(id: String, workerID: String, now: Date = Date(), leaseDuration: TimeInterval = 300) throws -> MemoryOSQueueItem? {
        guard var item = try queueItem(id: id) else { return nil }
        guard [.pending, .retryScheduled].contains(item.status), item.nextRunAt <= now else { return nil }
        item.status = .processing
        item.lockedAt = now
        item.lockedBy = workerID
        item.leaseExpiresAt = now.addingTimeInterval(leaseDuration)
        item.updatedAt = now
        try enqueue(item)
        return item
    }

    // MARK: - L2

    public func upsert(node: MemoryOSNode) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l2_nodes
        (id, stable_key, node_type, name, summary, created_at, updated_at, metadata_json)
        VALUES (\(quote(node.id)), \(quote(node.stableKey)), \(quote(node.nodeType)), \(quote(node.name)), \(quote(node.summary)), \(quote(iso(node.createdAt))), \(quote(iso(node.updatedAt))), \(quote(json(node.metadata))))
        """)
        try execute("DELETE FROM memory_l2_nodes_fts WHERE node_id = \(quote(node.id));")
        try execute("INSERT INTO memory_l2_nodes_fts(node_id, node_type, name, summary) VALUES (\(quote(node.id)), \(quote(node.nodeType)), \(quote(node.name)), \(quote(node.summary)))")
    }

    public func upsert(statement: MemoryOSStatement) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l2_statements
        (id, subject_id, predicate, object_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json)
        VALUES (\(quote(statement.id)), \(quote(statement.subjectID)), \(quote(statement.predicate)), \(quote(statement.objectID)), \(quote(statement.text)), \(quote(statement.assertionKind.rawValue)), \(statement.confidence), \(quote(iso(statement.validAt))), \(quote(iso(statement.committedAt))), \(quote(json(statement.evidenceSpanIDs))), \(quote(statement.sourceArtifactID)), \(quote(json(statement.metadata))))
        """)
        try execute("DELETE FROM memory_l2_statement_evidence WHERE statement_id = \(quote(statement.id));")
        for spanID in statement.evidenceSpanIDs {
            try execute("""
            INSERT INTO memory_l2_statement_evidence(statement_id, span_id, strength)
            SELECT \(quote(statement.id)), \(quote(spanID)), 1.0
            WHERE EXISTS (SELECT 1 FROM memory_l0_provenance_spans WHERE id = \(quote(spanID)))
            """)
        }
        try execute("DELETE FROM memory_l2_statements_fts WHERE statement_id = \(quote(statement.id));")
        try execute("INSERT INTO memory_l2_statements_fts(statement_id, predicate, text) VALUES (\(quote(statement.id)), \(quote(statement.predicate)), \(quote(statement.text)))")
    }

    public func saveProjectionBatch(_ batch: MemoryOSProjectionBatch) throws {
        for node in batch.nodes { try upsert(node: node) }
        for statement in batch.statements { try upsert(statement: statement) }
        for entity in batch.entities { try upsert(entity: entity) }
        for entityStatement in batch.entityStatements { try upsert(entityStatement: entityStatement) }
        for belief in batch.beliefs { try upsert(belief: belief) }
        try execute("""
        INSERT OR REPLACE INTO memory_l2_projections(id, projection_key, title, content, refreshed_at, metadata_json)
        VALUES (\(quote("projection:\(batch.artifactID)")), \(quote("artifact:\(batch.artifactID)")), 'Artifact projection', \(quote(json(batch))), \(quote(iso(Date()))), \(quote(json([
            "artifact_id": batch.artifactID,
            "node_count": String(batch.nodes.count),
            "statement_count": String(batch.statements.count),
            "entity_count": String(batch.entities.count),
            "belief_count": String(batch.beliefs.count)
        ]))))
        """)
    }

    public func searchStatementsFTS(query: String, limit: Int = 20) throws -> [String] {
        try queryStrings(sql: "SELECT statement_id FROM memory_l2_statements_fts WHERE memory_l2_statements_fts MATCH \(quote(query)) LIMIT \(limit)")
    }

    // MARK: - L3

    public func upsert(belief: MemoryOSBelief) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l3_beliefs
        (id, topic, statement, projection_kind, confidence, evidence_statement_ids_json, valid_at, projected_at, source_artifact_id, metadata_json)
        VALUES (\(quote(belief.id)), \(quote(belief.topic)), \(quote(belief.statement)), \(quote(belief.projectionKind.rawValue)), \(belief.confidence), \(quote(json(belief.evidenceStatementIDs))), \(quote(iso(belief.validAt))), \(quote(iso(belief.projectedAt))), \(quote(belief.sourceArtifactID)), \(quote(json(belief.metadata))))
        """)
        try execute("DELETE FROM memory_l3_beliefs_fts WHERE belief_id = \(quote(belief.id));")
        try execute("INSERT INTO memory_l3_beliefs_fts(belief_id, topic, statement) VALUES (\(quote(belief.id)), \(quote(belief.topic)), \(quote(belief.statement)))")
    }

    // MARK: - L4

    public func upsert(entity: MemoryOSEntity) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l4_entities
        (id, stable_key, entity_type, name, aliases_json, summary, confidence, created_at, updated_at, valid_from, metadata_json)
        VALUES (\(quote(entity.id)), \(quote(entity.stableKey)), \(quote(entity.entityType)), \(quote(entity.name)), \(quote(json(entity.aliases))), \(quote(entity.summary)), \(entity.confidence), \(quote(iso(entity.createdAt))), \(quote(iso(entity.updatedAt))), \(quote(entity.validFrom.map(iso))), \(quote(json(entity.metadata))))
        """)
        for alias in entity.aliases {
            try execute("""
            INSERT OR REPLACE INTO memory_l4_entity_aliases(id, entity_id, alias, normalized_alias, created_at, metadata_json)
            VALUES (\(quote("\(entity.id):alias:\(alias)")), \(quote(entity.id)), \(quote(alias)), \(quote(alias.lowercased())), \(quote(iso(Date()))), '{}')
            """)
        }
        try execute("DELETE FROM memory_l4_entities_fts WHERE entity_id = \(quote(entity.id));")
        try execute("INSERT INTO memory_l4_entities_fts(entity_id, entity_type, name, aliases, summary) VALUES (\(quote(entity.id)), \(quote(entity.entityType)), \(quote(entity.name)), \(quote(entity.aliases.joined(separator: " "))), \(quote(entity.summary)))")
    }

    public func entity(id: String) throws -> MemoryOSEntity? {
        try query(sql: """
        SELECT id, stable_key, entity_type, name, aliases_json, summary, confidence, created_at, updated_at, valid_from, metadata_json
        FROM memory_l4_entities WHERE id = \(quote(id)) LIMIT 1
        """).map(decodeEntity).first
    }

    public func upsert(entityStatement statement: MemoryOSEntityStatement) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l4_entity_statements
        (id, entity_id, predicate, object_entity_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json)
        VALUES (\(quote(statement.id)), \(quote(statement.entityID)), \(quote(statement.predicate)), \(quote(statement.objectEntityID)), \(quote(statement.text)), \(quote(statement.assertionKind.rawValue)), \(statement.confidence), \(quote(iso(statement.validAt))), \(quote(iso(statement.committedAt))), \(quote(json(statement.evidenceSpanIDs))), \(quote(statement.sourceArtifactID)), \(quote(json(statement.metadata))))
        """)
        try execute("DELETE FROM memory_l4_entity_statement_evidence WHERE statement_id = \(quote(statement.id));")
        for spanID in statement.evidenceSpanIDs {
            try execute("""
            INSERT INTO memory_l4_entity_statement_evidence(statement_id, span_id, strength)
            SELECT \(quote(statement.id)), \(quote(spanID)), 1.0
            WHERE EXISTS (SELECT 1 FROM memory_l0_provenance_spans WHERE id = \(quote(spanID)))
            """)
        }
        try execute("DELETE FROM memory_l4_statements_fts WHERE statement_id = \(quote(statement.id));")
        try execute("INSERT INTO memory_l4_statements_fts(statement_id, predicate, text) VALUES (\(quote(statement.id)), \(quote(statement.predicate)), \(quote(statement.text)))")
    }

    public func searchEntitiesFTS(query: String, limit: Int = 20) throws -> [String] {
        try queryStrings(sql: "SELECT entity_id FROM memory_l4_entities_fts WHERE memory_l4_entities_fts MATCH \(quote(query)) LIMIT \(limit)")
    }

    // MARK: - Production operations

    public func save(artifact: MemoryOSLLMArtifactEnvelope) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l2_processing_artifacts
        (id, processing_run_id, artifact_type, content, created_at, metadata_json)
        VALUES (\(quote(artifact.id)), \(quote(artifact.processingRunID ?? artifact.queueItemID ?? "unassigned")), \(quote(artifact.artifactType)), \(quote(artifact.rawContent)), \(quote(iso(artifact.createdAt))), \(quote(json([
            "schema_name": artifact.schemaName,
            "schema_version": String(artifact.schemaVersion),
            "model_id": artifact.modelID,
            "content_hash": artifact.contentHash,
            "queue_item_id": artifact.queueItemID ?? ""
        ].merging(artifact.metadata) { _, new in new }))))
        """)
    }

    public func save(audit event: MemoryOSAuditEvent) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_audit_events
        (id, event_type, actor, subject_id, payload_json, created_at)
        VALUES (\(quote(event.id)), \(quote(event.eventType)), \(quote(event.actor)), \(quote(event.subjectID)), \(quote(json(event.payload))), \(quote(iso(event.createdAt))))
        """)
    }

    public func save(metric: MemoryOSProcessingMetric) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_processing_metrics
        (id, metric_name, metric_value, dimensions_json, created_at)
        VALUES (\(quote(metric.id)), \(quote(metric.name)), \(metric.value), \(quote(json(metric.dimensions))), \(quote(iso(metric.createdAt))))
        """)
    }

    public func saveHealthReport(_ report: MemoryOSStoreHealthReport) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_store_health_checks
        (id, status, checked_at, report_json)
        VALUES (\(quote("health:\(iso(report.checkedAt))")), \(quote(report.status.rawValue)), \(quote(iso(report.checkedAt))), \(quote(json(report))))
        """)
    }

    public func queueOperationalSnapshot(now: Date = Date()) throws -> MemoryOSQueueOperationalSnapshot {
        func count(status: MemoryOSQueueStatus) throws -> Int {
            Int(try query(sql: "SELECT COUNT(*) FROM memory_l1_processing_queue WHERE status = \(quote(status.rawValue));").first?.first ?? "0") ?? 0
        }
        let isoNow = iso(now)
        let expired = Int(try query(sql: "SELECT COUNT(*) FROM memory_l1_processing_queue WHERE status IN ('leased', 'processing') AND lease_expires_at IS NOT NULL AND lease_expires_at < \(quote(isoNow));").first?.first ?? "0") ?? 0
        return MemoryOSQueueOperationalSnapshot(pending: try count(status: .pending), leased: try count(status: .leased), processing: try count(status: .processing), retryScheduled: try count(status: .retryScheduled), succeeded: try count(status: .succeeded), failed: try count(status: .failed), deadLetter: try count(status: .deadLetter), expiredLeases: expired, checkedAt: now)
    }

    // MARK: - Helpers exposed for repositories/tests

    public func execute(_ sql: String) throws {
        try withDatabaseLock {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                throw SQLiteMemoryOSStoreError.executeFailed(Self.message(db))
            }
        }
    }

    public func query(sql: String) throws -> [[String]] {
        try withDatabaseLock {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteMemoryOSStoreError.prepareFailed(Self.message(db))
            }
            defer { sqlite3_finalize(statement) }
            var rows: [[String]] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_ROW {
                    let count = sqlite3_column_count(statement)
                    var row: [String] = []
                    for index in 0..<count {
                        if let cString = sqlite3_column_text(statement, index) {
                            row.append(String(cString: cString))
                        } else {
                            row.append("")
                        }
                    }
                    rows.append(row)
                } else if result == SQLITE_DONE {
                    break
                } else {
                    throw SQLiteMemoryOSStoreError.stepFailed(Self.message(db))
                }
            }
            return rows
        }
    }

    public func queryStrings(sql: String) throws -> [String] {
        try query(sql: sql).compactMap { $0.first }
    }

    private func decodeProvenanceObject(_ row: [String]) throws -> MemoryOSProvenanceObject {
        MemoryOSProvenanceObject(id: row[0], sourceType: MemoryOSSourceType(rawValue: row[1]) ?? .manual, sourceID: nilIfEmpty(row[2]), title: row[3], content: row[4], contentHash: row[5], occurredAt: try date(row[6]), ingestedAt: try date(row[7]), sessionID: nilIfEmpty(row[8]), workObjectID: nilIfEmpty(row[9]), confidentiality: MemoryOSConfidentiality(rawValue: row[10]) ?? .personal, status: MemoryOSRecordStatus(rawValue: row[11]) ?? .active, metadata: try decode([String: String].self, row[12]))
    }

    private func decodeQueueItem(_ row: [String]) throws -> MemoryOSQueueItem {
        MemoryOSQueueItem(id: row[0], kind: row[1], status: MemoryOSQueueStatus(rawValue: row[2]) ?? .pending, priority: Int(row[3]) ?? 0, payloadJSON: row[4], attemptCount: Int(row[5]) ?? 0, maxAttempts: Int(row[6]) ?? 3, nextRunAt: try date(row[7]), lockedAt: try optionalDate(row[8]), lockedBy: nilIfEmpty(row[9]), leaseExpiresAt: try optionalDate(row[10]), idempotencyKey: row[11], payloadHash: row[12], createdAt: try date(row[13]), updatedAt: try date(row[14]), errorCode: nilIfEmpty(row[15]), errorMessage: nilIfEmpty(row[16]))
    }

    private func decodeEntity(_ row: [String]) throws -> MemoryOSEntity {
        MemoryOSEntity(id: row[0], stableKey: row[1], entityType: row[2], name: row[3], aliases: try decode([String].self, row[4]), summary: row[5], confidence: Double(row[6]) ?? 0, createdAt: try date(row[7]), updatedAt: try date(row[8]), validFrom: try optionalDate(row[9]), metadata: try decode([String: String].self, row[10]))
    }

    public func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    public func decode<T: Decodable>(_ type: T.Type, _ value: String) throws -> T {
        guard let data = value.data(using: .utf8) else { throw SQLiteMemoryOSStoreError.decodeFailed("Invalid UTF-8") }
        do { return try decoder.decode(type, from: data) } catch { throw SQLiteMemoryOSStoreError.decodeFailed(String(describing: error)) }
    }

    public func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    public func quote(_ value: String?) -> String {
        guard let value else { return "NULL" }
        return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func date(_ string: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: string) else { throw SQLiteMemoryOSStoreError.decodeFailed("Invalid date: \(string)") }
        return date
    }

    private func optionalDate(_ string: String) throws -> Date? {
        guard !string.isEmpty else { return nil }
        return try date(string)
    }

    private func nilIfEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }

    private func withDatabaseLock<T>(_ operation: () throws -> T) rethrows -> T {
        databaseLock.lock()
        defer { databaseLock.unlock() }
        return try operation()
    }

    private static func message(_ db: OpaquePointer?) -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "Unknown SQLite error" }
        return String(cString: message)
    }
}

public extension SQLiteMemoryOSStore {
    static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS memory_schema_migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_legacy_import_runs (id TEXT PRIMARY KEY, status TEXT NOT NULL, dry_run INTEGER NOT NULL, started_at TEXT NOT NULL, finished_at TEXT, imported_count INTEGER NOT NULL DEFAULT 0, failed_count INTEGER NOT NULL DEFAULT 0, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_store_health_checks (id TEXT PRIMARY KEY, status TEXT NOT NULL, checked_at TEXT NOT NULL, report_json TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS memory_audit_events (id TEXT PRIMARY KEY, event_type TEXT NOT NULL, actor TEXT NOT NULL, subject_id TEXT, payload_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS idx_memory_audit_events_time ON memory_audit_events(created_at DESC);
    CREATE TABLE IF NOT EXISTS memory_processing_metrics (id TEXT PRIMARY KEY, metric_name TEXT NOT NULL, metric_value REAL NOT NULL, dimensions_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS memory_error_events (id TEXT PRIMARY KEY, error_code TEXT NOT NULL, error_message TEXT NOT NULL, context_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS idx_memory_error_events_time ON memory_error_events(created_at DESC);
    CREATE TABLE IF NOT EXISTS memory_recovery_actions (id TEXT PRIMARY KEY, action_type TEXT NOT NULL, target_id TEXT, status TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_discard_events (id TEXT PRIMARY KEY, source_type TEXT NOT NULL, source_id TEXT, reason TEXT NOT NULL, occurred_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');

    CREATE TABLE IF NOT EXISTS memory_l0_provenance_objects (id TEXT PRIMARY KEY, source_type TEXT NOT NULL, source_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL, content_hash TEXT NOT NULL, occurred_at TEXT NOT NULL, ingested_at TEXT NOT NULL, session_id TEXT, work_object_id TEXT, confidentiality TEXT NOT NULL, status TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE INDEX IF NOT EXISTS idx_memory_l0_provenance_source ON memory_l0_provenance_objects(source_type, source_id);
    CREATE INDEX IF NOT EXISTS idx_memory_l0_provenance_time ON memory_l0_provenance_objects(occurred_at DESC);
    CREATE TABLE IF NOT EXISTS memory_l0_provenance_spans (id TEXT PRIMARY KEY, provenance_object_id TEXT NOT NULL, start_offset INTEGER, end_offset INTEGER, text TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}', FOREIGN KEY(provenance_object_id) REFERENCES memory_l0_provenance_objects(id));
    CREATE INDEX IF NOT EXISTS idx_memory_l0_spans_object ON memory_l0_provenance_spans(provenance_object_id);
    CREATE TABLE IF NOT EXISTS memory_l0_derivations (id TEXT PRIMARY KEY, source_span_id TEXT NOT NULL, derived_record_id TEXT NOT NULL, derived_record_type TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_l0_content_hashes (content_hash TEXT PRIMARY KEY, provenance_object_id TEXT NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(provenance_object_id) REFERENCES memory_l0_provenance_objects(id));
    CREATE VIRTUAL TABLE IF NOT EXISTS memory_l0_provenance_fts USING fts5(object_id UNINDEXED, source_type UNINDEXED, title, content, tokenize = 'unicode61 remove_diacritics 2');

    CREATE TABLE IF NOT EXISTS memory_l1_capture_events (id TEXT PRIMARY KEY, provenance_object_id TEXT NOT NULL, event_type TEXT NOT NULL, occurred_at TEXT NOT NULL, token_estimate INTEGER NOT NULL DEFAULT 0, processing_state TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}', FOREIGN KEY(provenance_object_id) REFERENCES memory_l0_provenance_objects(id));
    CREATE INDEX IF NOT EXISTS idx_memory_l1_capture_state ON memory_l1_capture_events(processing_state, occurred_at DESC);
    CREATE TABLE IF NOT EXISTS memory_l1_time_blocks (id TEXT PRIMARY KEY, title TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT NOT NULL, token_estimate INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE INDEX IF NOT EXISTS idx_memory_l1_time_blocks_status ON memory_l1_time_blocks(status, started_at DESC);
    CREATE TABLE IF NOT EXISTS memory_l1_time_block_events (time_block_id TEXT NOT NULL, capture_event_id TEXT NOT NULL, sequence INTEGER NOT NULL, PRIMARY KEY(time_block_id, capture_event_id), FOREIGN KEY(time_block_id) REFERENCES memory_l1_time_blocks(id), FOREIGN KEY(capture_event_id) REFERENCES memory_l1_capture_events(id));
    CREATE TABLE IF NOT EXISTS memory_l1_processing_queue (id TEXT PRIMARY KEY, kind TEXT NOT NULL, status TEXT NOT NULL, priority INTEGER NOT NULL DEFAULT 0, payload_json TEXT NOT NULL DEFAULT '{}', attempt_count INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 3, next_run_at TEXT NOT NULL, locked_at TEXT, locked_by TEXT, lease_expires_at TEXT, idempotency_key TEXT NOT NULL UNIQUE, payload_hash TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, error_code TEXT, error_message TEXT);
    CREATE INDEX IF NOT EXISTS idx_memory_l1_queue_runnable ON memory_l1_processing_queue(status, next_run_at, priority DESC);
    CREATE INDEX IF NOT EXISTS idx_memory_l1_queue_idempotency ON memory_l1_processing_queue(idempotency_key);
    CREATE TABLE IF NOT EXISTS memory_l1_queue_attempts (id TEXT PRIMARY KEY, queue_item_id TEXT NOT NULL, attempt_number INTEGER NOT NULL, status TEXT NOT NULL, started_at TEXT NOT NULL, finished_at TEXT, error_code TEXT, error_message TEXT, metadata_json TEXT NOT NULL DEFAULT '{}', FOREIGN KEY(queue_item_id) REFERENCES memory_l1_processing_queue(id));
    CREATE TABLE IF NOT EXISTS memory_l1_dead_letter_queue (id TEXT PRIMARY KEY, queue_item_id TEXT NOT NULL, failed_payload_json TEXT NOT NULL, error_code TEXT NOT NULL, error_message TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');

    CREATE TABLE IF NOT EXISTS memory_l2_nodes (id TEXT PRIMARY KEY, stable_key TEXT NOT NULL UNIQUE, node_type TEXT NOT NULL, name TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE INDEX IF NOT EXISTS idx_memory_l2_nodes_key ON memory_l2_nodes(stable_key);
    CREATE TABLE IF NOT EXISTS memory_l2_edges (id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, predicate TEXT NOT NULL, object_id TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}', FOREIGN KEY(subject_id) REFERENCES memory_l2_nodes(id), FOREIGN KEY(object_id) REFERENCES memory_l2_nodes(id));
    CREATE TABLE IF NOT EXISTS memory_l2_statements (id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, predicate TEXT NOT NULL, object_id TEXT, text TEXT NOT NULL, assertion_kind TEXT NOT NULL, confidence REAL NOT NULL, valid_at TEXT NOT NULL, committed_at TEXT NOT NULL, evidence_span_ids_json TEXT NOT NULL DEFAULT '[]', source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}', FOREIGN KEY(subject_id) REFERENCES memory_l2_nodes(id));
    CREATE INDEX IF NOT EXISTS idx_memory_l2_statements_subject ON memory_l2_statements(subject_id, committed_at DESC);
    CREATE INDEX IF NOT EXISTS idx_memory_l2_statements_temporal ON memory_l2_statements(subject_id, predicate, valid_at DESC, confidence DESC, committed_at DESC);
    CREATE TABLE IF NOT EXISTS memory_l2_statement_evidence (statement_id TEXT NOT NULL, span_id TEXT NOT NULL, strength REAL NOT NULL DEFAULT 1.0, PRIMARY KEY(statement_id, span_id), FOREIGN KEY(statement_id) REFERENCES memory_l2_statements(id), FOREIGN KEY(span_id) REFERENCES memory_l0_provenance_spans(id));
    CREATE INDEX IF NOT EXISTS idx_memory_l2_statement_evidence_statement ON memory_l2_statement_evidence(statement_id);
    CREATE TABLE IF NOT EXISTS memory_l2_statement_processing_state (statement_id TEXT NOT NULL, processing_kind TEXT NOT NULL, status TEXT NOT NULL, source_artifact_id TEXT, processed_by_artifact_id TEXT, last_attempt_at TEXT, metadata_json TEXT NOT NULL DEFAULT '{}', PRIMARY KEY(statement_id, processing_kind));
    CREATE INDEX IF NOT EXISTS idx_memory_l2_processing_state ON memory_l2_statement_processing_state(processing_kind, status, last_attempt_at);
    CREATE TABLE IF NOT EXISTS memory_l2_episodes (id TEXT PRIMARY KEY, provenance_object_id TEXT, title TEXT NOT NULL, summary TEXT NOT NULL, occurred_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_l2_processing_runs (id TEXT PRIMARY KEY, queue_item_id TEXT, status TEXT NOT NULL, started_at TEXT NOT NULL, finished_at TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_l2_processing_artifacts (id TEXT PRIMARY KEY, processing_run_id TEXT NOT NULL, artifact_type TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_l2_projections (id TEXT PRIMARY KEY, projection_key TEXT NOT NULL UNIQUE, title TEXT NOT NULL, content TEXT NOT NULL, refreshed_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_l2_projection_items (projection_id TEXT NOT NULL, statement_id TEXT NOT NULL, sequence INTEGER NOT NULL, PRIMARY KEY(projection_id, statement_id));
    CREATE VIRTUAL TABLE IF NOT EXISTS memory_l2_nodes_fts USING fts5(node_id UNINDEXED, node_type UNINDEXED, name, summary, tokenize = 'unicode61 remove_diacritics 2');
    CREATE VIRTUAL TABLE IF NOT EXISTS memory_l2_statements_fts USING fts5(statement_id UNINDEXED, predicate UNINDEXED, text, tokenize = 'unicode61 remove_diacritics 2');

    CREATE TABLE IF NOT EXISTS memory_l3_beliefs (id TEXT PRIMARY KEY, topic TEXT NOT NULL, statement TEXT NOT NULL, projection_kind TEXT NOT NULL, confidence REAL NOT NULL, evidence_statement_ids_json TEXT NOT NULL DEFAULT '[]', valid_at TEXT NOT NULL, projected_at TEXT NOT NULL, source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE INDEX IF NOT EXISTS idx_memory_l3_beliefs_topic ON memory_l3_beliefs(topic, projected_at DESC);
    CREATE INDEX IF NOT EXISTS idx_memory_l3_beliefs_temporal ON memory_l3_beliefs(topic, valid_at DESC, confidence DESC, projected_at DESC);
    CREATE TABLE IF NOT EXISTS memory_l3_belief_evidence (belief_id TEXT NOT NULL, statement_id TEXT NOT NULL, strength REAL NOT NULL DEFAULT 1.0, PRIMARY KEY(belief_id, statement_id));
    CREATE INDEX IF NOT EXISTS idx_memory_l3_belief_evidence_belief ON memory_l3_belief_evidence(belief_id);
    CREATE TABLE IF NOT EXISTS memory_l3_belief_relations (id TEXT PRIMARY KEY, source_belief_id TEXT NOT NULL, target_belief_id TEXT NOT NULL, relation_type TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_l3_promotion_records (id TEXT PRIMARY KEY, source_record_id TEXT NOT NULL, target_belief_id TEXT NOT NULL, promotion_reason TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE VIRTUAL TABLE IF NOT EXISTS memory_l3_beliefs_fts USING fts5(belief_id UNINDEXED, topic, statement, tokenize = 'unicode61 remove_diacritics 2');

    CREATE TABLE IF NOT EXISTS memory_l4_entities (id TEXT PRIMARY KEY, stable_key TEXT NOT NULL UNIQUE, entity_type TEXT NOT NULL, name TEXT NOT NULL, aliases_json TEXT NOT NULL DEFAULT '[]', summary TEXT NOT NULL DEFAULT '', confidence REAL NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, valid_from TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE INDEX IF NOT EXISTS idx_memory_l4_entities_key ON memory_l4_entities(stable_key);
    CREATE TABLE IF NOT EXISTS memory_l4_entity_aliases (id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, alias TEXT NOT NULL, normalized_alias TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}', FOREIGN KEY(entity_id) REFERENCES memory_l4_entities(id));
    CREATE INDEX IF NOT EXISTS idx_memory_l4_aliases_entity ON memory_l4_entity_aliases(entity_id, normalized_alias);
    CREATE TABLE IF NOT EXISTS memory_l4_entity_statements (id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, predicate TEXT NOT NULL, object_entity_id TEXT, text TEXT NOT NULL, assertion_kind TEXT NOT NULL, confidence REAL NOT NULL, valid_at TEXT NOT NULL, committed_at TEXT NOT NULL, evidence_span_ids_json TEXT NOT NULL DEFAULT '[]', source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}', FOREIGN KEY(entity_id) REFERENCES memory_l4_entities(id));
    CREATE INDEX IF NOT EXISTS idx_memory_l4_statements_entity ON memory_l4_entity_statements(entity_id, committed_at DESC);
    CREATE TABLE IF NOT EXISTS memory_l4_entity_statement_evidence (statement_id TEXT NOT NULL, span_id TEXT NOT NULL, strength REAL NOT NULL DEFAULT 1.0, PRIMARY KEY(statement_id, span_id));
    CREATE INDEX IF NOT EXISTS idx_memory_l4_statement_evidence_statement ON memory_l4_entity_statement_evidence(statement_id);
    CREATE TABLE IF NOT EXISTS memory_l4_archive_runs (id TEXT PRIMARY KEY, status TEXT NOT NULL, started_at TEXT NOT NULL, finished_at TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_l4_archive_statement_links (archive_run_id TEXT NOT NULL, statement_id TEXT NOT NULL, PRIMARY KEY(archive_run_id, statement_id));
    CREATE TABLE IF NOT EXISTS memory_l4_merge_events (id TEXT PRIMARY KEY, source_entity_id TEXT NOT NULL, target_entity_id TEXT NOT NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE IF NOT EXISTS memory_l4_split_events (id TEXT PRIMARY KEY, source_entity_id TEXT NOT NULL, new_entity_ids_json TEXT NOT NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE VIRTUAL TABLE IF NOT EXISTS memory_l4_entities_fts USING fts5(entity_id UNINDEXED, entity_type UNINDEXED, name, aliases, summary, tokenize = 'unicode61 remove_diacritics 2');
    CREATE VIRTUAL TABLE IF NOT EXISTS memory_l4_statements_fts USING fts5(statement_id UNINDEXED, predicate UNINDEXED, text, tokenize = 'unicode61 remove_diacritics 2');
    """
}
