import Foundation
import SQLite3
import ConnorGraphCore

public enum SQLiteGraphKernelStoreError: Error, Equatable, CustomStringConvertible {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let message): "openFailed: \(message)"
        case .executeFailed(let message): "executeFailed: \(message)"
        case .prepareFailed(let message): "prepareFailed: \(message)"
        case .bindFailed(let message): "bindFailed: \(message)"
        case .stepFailed(let message): "stepFailed: \(message)"
        case .decodeFailed(let message): "decodeFailed: \(message)"
        }
    }
}

public final class SQLiteGraphKernelStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(path: String) throws {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw SQLiteGraphKernelStoreError.openFailed(Self.message(db))
        }
    }

    deinit {
        sqlite3_close(db)
    }

    public func migrate() throws {
        try execute("PRAGMA foreign_keys = ON;")
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_episodes_v3 (
            id TEXT PRIMARY KEY,
            graph_id TEXT NOT NULL,
            source_type TEXT NOT NULL,
            source_id TEXT,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            source_description TEXT NOT NULL,
            occurred_at TEXT NOT NULL,
            ingested_at TEXT NOT NULL,
            session_id TEXT,
            work_object_id TEXT,
            status TEXT NOT NULL,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_episodes_v3_graph_time ON graph_episodes_v3(graph_id, occurred_at DESC);")
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_entities (
            id TEXT PRIMARY KEY,
            graph_id TEXT NOT NULL,
            name TEXT NOT NULL,
            stable_key TEXT NOT NULL,
            entity_kind TEXT NOT NULL,
            scope TEXT NOT NULL,
            canonical_class_id TEXT,
            aliases_json TEXT NOT NULL,
            summary TEXT NOT NULL,
            confidence REAL NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            valid_from TEXT,
            valid_until TEXT,
            superseded_by_entity_id TEXT,
            metadata_json TEXT NOT NULL,
            UNIQUE(graph_id, stable_key)
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_entities_kind ON graph_entities(graph_id, entity_kind, status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_entities_scope_kind ON graph_entities(graph_id, scope, entity_kind, status);")
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_statements (
            id TEXT PRIMARY KEY,
            graph_id TEXT NOT NULL,
            subject_entity_id TEXT NOT NULL,
            predicate TEXT NOT NULL,
            object_entity_id TEXT NOT NULL,
            statement_text TEXT NOT NULL,
            edge_kind TEXT NOT NULL,
            valid_at TEXT NOT NULL,
            invalid_at TEXT,
            committed_at TEXT NOT NULL,
            reference_time TEXT,
            confidence REAL NOT NULL,
            belief_status TEXT NOT NULL,
            justifications_json TEXT NOT NULL,
            source_episode_ids_json TEXT NOT NULL,
            invalidated_by_statement_id TEXT,
            supersedes_statement_ids_json TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            CHECK (invalid_at IS NULL OR valid_at <= invalid_at),
            FOREIGN KEY(subject_entity_id) REFERENCES graph_entities(id),
            FOREIGN KEY(object_entity_id) REFERENCES graph_entities(id)
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_statements_subject ON graph_statements(graph_id, subject_entity_id, belief_status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_statements_object ON graph_statements(graph_id, object_entity_id, belief_status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_statements_predicate ON graph_statements(graph_id, predicate, belief_status);")
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_ontology_classes (
            id TEXT PRIMARY KEY,
            graph_id TEXT NOT NULL,
            class_entity_id TEXT NOT NULL,
            class_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            layer INTEGER NOT NULL,
            domain TEXT NOT NULL,
            lifecycle_status TEXT NOT NULL,
            description TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            UNIQUE(graph_id, class_id),
            FOREIGN KEY(class_entity_id) REFERENCES graph_entities(id)
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_anomalies (
            id TEXT PRIMARY KEY,
            graph_id TEXT NOT NULL,
            anomaly_type TEXT NOT NULL,
            statement_id TEXT NOT NULL,
            related_statement_ids_json TEXT NOT NULL,
            severity TEXT NOT NULL,
            status TEXT NOT NULL,
            detected_at TEXT NOT NULL,
            resolved_at TEXT,
            resolution_json TEXT NOT NULL,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_anomalies_graph_status ON graph_anomalies(graph_id, status, detected_at DESC);")
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_jobs_v3 (
            id TEXT PRIMARY KEY,
            graph_id TEXT NOT NULL,
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            priority INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            attempt_count INTEGER NOT NULL,
            max_attempts INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            next_run_at TEXT NOT NULL,
            started_at TEXT,
            finished_at TEXT,
            error_code TEXT,
            error_message TEXT,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_jobs_v3_runnable ON graph_jobs_v3(graph_id, status, next_run_at, priority DESC);")
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_extraction_traces (
            id TEXT PRIMARY KEY,
            job_id TEXT NOT NULL,
            graph_id TEXT NOT NULL,
            source_id TEXT NOT NULL,
            source_type TEXT NOT NULL,
            outcome TEXT NOT NULL,
            admission_action TEXT,
            admission_reasons_json TEXT NOT NULL,
            extracted_entity_count INTEGER NOT NULL,
            extracted_statement_count INTEGER NOT NULL,
            committed_entity_count INTEGER NOT NULL,
            committed_statement_count INTEGER NOT NULL,
            anomaly_count INTEGER NOT NULL,
            error_message TEXT,
            created_at TEXT NOT NULL,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_extraction_traces_job ON graph_extraction_traces(job_id, created_at DESC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_extraction_traces_source ON graph_extraction_traces(graph_id, source_id, created_at DESC);")
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_extraction_trace_payloads (
            trace_id TEXT PRIMARY KEY,
            prompt_text TEXT,
            raw_response_json TEXT,
            normalized_json TEXT,
            decoder_error_kind TEXT,
            decoder_error_message TEXT,
            created_at TEXT NOT NULL,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS graph_entities_fts USING fts5(
            entity_id UNINDEXED,
            graph_id UNINDEXED,
            entity_kind UNINDEXED,
            name,
            aliases,
            summary,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """)
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS graph_statements_fts USING fts5(
            statement_id UNINDEXED,
            graph_id UNINDEXED,
            predicate UNINDEXED,
            edge_kind UNINDEXED,
            statement_text,
            subject_name,
            object_name,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """)

        // App integration tables
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_write_candidates (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            proposed_by_run_id TEXT NOT NULL,
            proposed_by_tool_call_id TEXT,
            rationale TEXT NOT NULL,
            confidence REAL NOT NULL,
            payload_json TEXT NOT NULL,
            source_episode_ids_json TEXT NOT NULL,
            related_node_ids_json TEXT NOT NULL,
            related_fact_ids_json TEXT NOT NULL,
            status TEXT NOT NULL,
            validation_errors_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_write_candidates_status ON graph_write_candidates(group_id, status);")
        try execute("""
        CREATE TABLE IF NOT EXISTS agent_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            messages_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_agent_sessions_updated ON agent_sessions(updated_at DESC);")
        try execute("""
        CREATE TABLE IF NOT EXISTS agent_runs (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            group_id TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            model TEXT,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_agent_runs_session ON agent_runs(session_id);")
        try execute("""
        CREATE TABLE IF NOT EXISTS agent_events (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            sequence INTEGER,
            created_at TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_agent_events_run ON agent_events(run_id, sequence);")
        try execute("""
        CREATE TABLE IF NOT EXISTS agent_audit_events (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            actor TEXT NOT NULL,
            capability TEXT,
            tool_name TEXT,
            decision TEXT,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_agent_audit_events_run ON agent_audit_events(run_id);")
    }

    public func tableNames() throws -> Set<String> {
        Set(try queryStrings(sql: "SELECT name FROM sqlite_master WHERE type = 'table';"))
    }

    public func upsert(episode: GraphEpisodeV3) throws {
        try execute("""
        INSERT OR REPLACE INTO graph_episodes_v3
        (id, graph_id, source_type, source_id, title, content, source_description, occurred_at, ingested_at, session_id, work_object_id, status, metadata_json)
        VALUES (\(quote(episode.id)), \(quote(episode.graphID)), \(quote(episode.sourceType.rawValue)), \(quote(episode.sourceID)), \(quote(episode.title)), \(quote(episode.content)), \(quote(episode.sourceDescription)), \(quote(iso(episode.occurredAt))), \(quote(iso(episode.ingestedAt))), \(quote(episode.sessionID)), \(quote(episode.workObjectID)), \(quote(episode.status.rawValue)), \(quote(json(episode.metadata))))
        """)
    }

    public func episode(id: String) throws -> GraphEpisodeV3? {
        let rows = try query(sql: "SELECT id, graph_id, source_type, source_id, title, content, source_description, occurred_at, ingested_at, session_id, work_object_id, status, metadata_json FROM graph_episodes_v3 WHERE id = \(quote(id))")
        guard let row = rows.first else { return nil }
        return try decodeEpisode(row)
    }

    public func episodes(graphID: String, limit: Int = 200) throws -> [GraphEpisodeV3] {
        try query(sql: "SELECT id, graph_id, source_type, source_id, title, content, source_description, occurred_at, ingested_at, session_id, work_object_id, status, metadata_json FROM graph_episodes_v3 WHERE graph_id = \(quote(graphID)) ORDER BY occurred_at DESC LIMIT \(limit)").map(decodeEpisode)
    }

    public func upsert(entity: GraphEntity) throws {
        try execute("""
        INSERT OR REPLACE INTO graph_entities
        (id, graph_id, name, stable_key, entity_kind, scope, canonical_class_id, aliases_json, summary, confidence, status, created_at, updated_at, valid_from, valid_until, superseded_by_entity_id, metadata_json)
        VALUES (\(quote(entity.id)), \(quote(entity.graphID)), \(quote(entity.name)), \(quote(entity.stableKey)), \(quote(entity.entityKind.rawValue)), \(quote(entity.scope.rawValue)), \(quote(entity.canonicalClassID)), \(quote(json(entity.aliases))), \(quote(entity.summary)), \(entity.confidence), \(quote(entity.status.rawValue)), \(quote(iso(entity.createdAt))), \(quote(iso(entity.updatedAt))), \(quote(entity.validFrom.map(iso))), \(quote(entity.validUntil.map(iso))), \(quote(entity.supersededByEntityID)), \(quote(json(entity.metadata))))
        """)
        try upsertEntityFTS(entity)
    }

    public func entity(id: String) throws -> GraphEntity? {
        let rows = try query(sql: "SELECT id, graph_id, name, stable_key, entity_kind, scope, canonical_class_id, aliases_json, summary, confidence, status, created_at, updated_at, valid_from, valid_until, superseded_by_entity_id, metadata_json FROM graph_entities WHERE id = \(quote(id))")
        guard let row = rows.first else { return nil }
        return try decodeEntity(row)
    }

    public func entity(stableKey: String, graphID: String) throws -> GraphEntity? {
        let rows = try query(sql: "SELECT id, graph_id, name, stable_key, entity_kind, scope, canonical_class_id, aliases_json, summary, confidence, status, created_at, updated_at, valid_from, valid_until, superseded_by_entity_id, metadata_json FROM graph_entities WHERE graph_id = \(quote(graphID)) AND stable_key = \(quote(stableKey)) LIMIT 1")
        guard let row = rows.first else { return nil }
        return try decodeEntity(row)
    }

    public func entities(graphID: String, scope: GraphScope? = nil, entityKind: GraphEntityKind? = nil) throws -> [GraphEntity] {
        var conditions = ["graph_id = \(quote(graphID))"]
        if let scope { conditions.append("scope = \(quote(scope.rawValue))") }
        if let entityKind { conditions.append("entity_kind = \(quote(entityKind.rawValue))") }
        return try query(sql: "SELECT id, graph_id, name, stable_key, entity_kind, scope, canonical_class_id, aliases_json, summary, confidence, status, created_at, updated_at, valid_from, valid_until, superseded_by_entity_id, metadata_json FROM graph_entities WHERE \(conditions.joined(separator: " AND ")) ORDER BY name").map(decodeEntity)
    }

    public func upsert(statement: GraphStatement) throws {
        try execute("""
        INSERT OR REPLACE INTO graph_statements
        (id, graph_id, subject_entity_id, predicate, object_entity_id, statement_text, edge_kind, valid_at, invalid_at, committed_at, reference_time, confidence, belief_status, justifications_json, source_episode_ids_json, invalidated_by_statement_id, supersedes_statement_ids_json, metadata_json)
        VALUES (\(quote(statement.id)), \(quote(statement.graphID)), \(quote(statement.subjectEntityID)), \(quote(statement.predicate.rawValue)), \(quote(statement.objectEntityID)), \(quote(statement.statementText)), \(quote(statement.edgeKind.rawValue)), \(quote(iso(statement.validAt))), \(quote(statement.invalidAt.map(iso))), \(quote(iso(statement.committedAt))), \(quote(statement.referenceTime.map(iso))), \(statement.confidence), \(quote(statement.beliefStatus.rawValue)), \(quote(json(statement.justifications))), \(quote(json(statement.sourceEpisodeIDs))), \(quote(statement.invalidatedByStatementID)), \(quote(json(statement.supersedesStatementIDs))), \(quote(json(statement.metadata))))
        """)
        try upsertStatementFTS(statement)
    }

    public func statement(id: String) throws -> GraphStatement? {
        let rows = try query(sql: "SELECT id, graph_id, subject_entity_id, predicate, object_entity_id, statement_text, edge_kind, valid_at, invalid_at, committed_at, reference_time, confidence, belief_status, justifications_json, source_episode_ids_json, invalidated_by_statement_id, supersedes_statement_ids_json, metadata_json FROM graph_statements WHERE id = \(quote(id))")
        guard let row = rows.first else { return nil }
        return try decodeStatement(row)
    }

    public func statements(graphID: String, predicate: GraphPredicate? = nil, beliefStatus: GraphBeliefStatus = .active) throws -> [GraphStatement] {
        var conditions = ["graph_id = \(quote(graphID))", "belief_status = \(quote(beliefStatus.rawValue))", "invalid_at IS NULL"]
        if let predicate { conditions.append("predicate = \(quote(predicate.rawValue))") }
        return try query(sql: "SELECT id, graph_id, subject_entity_id, predicate, object_entity_id, statement_text, edge_kind, valid_at, invalid_at, committed_at, reference_time, confidence, belief_status, justifications_json, source_episode_ids_json, invalidated_by_statement_id, supersedes_statement_ids_json, metadata_json FROM graph_statements WHERE \(conditions.joined(separator: " AND ")) ORDER BY committed_at DESC").map(decodeStatement)
    }

    public func upsert(ontologyClass: GraphOntologyClass) throws {
        try execute("""
        INSERT OR REPLACE INTO graph_ontology_classes
        (id, graph_id, class_entity_id, class_id, display_name, layer, domain, lifecycle_status, description, created_at, updated_at, metadata_json)
        VALUES (\(quote(ontologyClass.id)), \(quote(ontologyClass.graphID)), \(quote(ontologyClass.classEntityID)), \(quote(ontologyClass.classID)), \(quote(ontologyClass.displayName)), \(ontologyClass.layer), \(quote(ontologyClass.domain)), \(quote(ontologyClass.lifecycleStatus.rawValue)), \(quote(ontologyClass.description)), \(quote(iso(ontologyClass.createdAt))), \(quote(iso(ontologyClass.updatedAt))), \(quote(json(ontologyClass.metadata))))
        """)
    }

    public func ontologyClasses(graphID: String) throws -> [GraphOntologyClass] {
        try query(sql: "SELECT id, graph_id, class_entity_id, class_id, display_name, layer, domain, lifecycle_status, description, created_at, updated_at, metadata_json FROM graph_ontology_classes WHERE graph_id = \(quote(graphID)) ORDER BY layer, class_id").map(decodeOntologyClass)
    }

    public func upsert(anomaly: GraphAnomaly) throws {
        try execute("""
        INSERT OR REPLACE INTO graph_anomalies
        (id, graph_id, anomaly_type, statement_id, related_statement_ids_json, severity, status, detected_at, resolved_at, resolution_json, metadata_json)
        VALUES (\(quote(anomaly.id)), \(quote(anomaly.graphID)), \(quote(anomaly.anomalyType.rawValue)), \(quote(anomaly.statementID)), \(quote(json(anomaly.relatedStatementIDs))), \(quote(anomaly.severity.rawValue)), \(quote(anomaly.status.rawValue)), \(quote(iso(anomaly.detectedAt))), \(quote(anomaly.resolvedAt.map(iso))), \(quote(json(anomaly.resolution))), \(quote(json(anomaly.metadata))))
        """)
    }

    public func anomaly(id: String) throws -> GraphAnomaly? {
        let rows = try query(sql: "SELECT id, graph_id, anomaly_type, statement_id, related_statement_ids_json, severity, status, detected_at, resolved_at, resolution_json, metadata_json FROM graph_anomalies WHERE id = \(quote(id))")
        guard let row = rows.first else { return nil }
        return try decodeAnomaly(row)
    }

    public func upsert(job: GraphJobV3) throws {
        try execute("""
        INSERT OR REPLACE INTO graph_jobs_v3
        (id, graph_id, type, status, priority, payload_json, attempt_count, max_attempts, created_at, updated_at, next_run_at, started_at, finished_at, error_code, error_message, metadata_json)
        VALUES (\(quote(job.id)), \(quote(job.graphID)), \(quote(job.type.rawValue)), \(quote(job.status.rawValue)), \(job.priority), \(quote(json(job.payload))), \(job.attemptCount), \(job.maxAttempts), \(quote(iso(job.createdAt))), \(quote(iso(job.updatedAt))), \(quote(iso(job.nextRunAt))), \(quote(job.startedAt.map(iso))), \(quote(job.finishedAt.map(iso))), \(quote(job.errorCode)), \(quote(job.errorMessage)), \(quote(json(job.metadata))))
        """)
    }

    public func runnableJobs(graphID: String, at date: Date, limit: Int = 10) throws -> [GraphJobV3] {
        try query(sql: "SELECT id, graph_id, type, status, priority, payload_json, attempt_count, max_attempts, created_at, updated_at, next_run_at, started_at, finished_at, error_code, error_message, metadata_json FROM graph_jobs_v3 WHERE graph_id = \(quote(graphID)) AND status = \(quote(GraphJobV3Status.queued.rawValue)) AND next_run_at <= \(quote(iso(date))) ORDER BY priority DESC, next_run_at ASC LIMIT \(limit)").map(decodeJob)
    }

    public func job(id: String) throws -> GraphJobV3? {
        try query(sql: "SELECT id, graph_id, type, status, priority, payload_json, attempt_count, max_attempts, created_at, updated_at, next_run_at, started_at, finished_at, error_code, error_message, metadata_json FROM graph_jobs_v3 WHERE id = \(quote(id)) LIMIT 1").map(decodeJob).first
    }

    public func appendExtractionTrace(_ trace: GraphExtractionTrace) throws {
        try execute("""
        INSERT INTO graph_extraction_traces
        (id, job_id, graph_id, source_id, source_type, outcome, admission_action, admission_reasons_json, extracted_entity_count, extracted_statement_count, committed_entity_count, committed_statement_count, anomaly_count, error_message, created_at, metadata_json)
        VALUES (\(quote(trace.id)), \(quote(trace.jobID)), \(quote(trace.graphID)), \(quote(trace.sourceID)), \(quote(trace.sourceType.rawValue)), \(quote(trace.outcome.rawValue)), \(quote(trace.admissionAction?.rawValue)), \(quote(json(trace.admissionReasons.map(\.rawValue)))), \(trace.extractedEntityCount), \(trace.extractedStatementCount), \(trace.committedEntityCount), \(trace.committedStatementCount), \(trace.anomalyCount), \(quote(trace.errorMessage)), \(quote(iso(trace.createdAt))), \(quote(json(trace.metadata))))
        """)
    }

    public func extractionTraces(jobID: String, limit: Int = 20) throws -> [GraphExtractionTrace] {
        try query(sql: """
        SELECT id, job_id, graph_id, source_id, source_type, outcome, admission_action, admission_reasons_json, extracted_entity_count, extracted_statement_count, committed_entity_count, committed_statement_count, anomaly_count, error_message, created_at, metadata_json
        FROM graph_extraction_traces WHERE job_id = \(quote(jobID)) ORDER BY created_at DESC LIMIT \(limit)
        """).map(decodeExtractionTrace)
    }

    public func extractionTrace(id: String) throws -> GraphExtractionTrace? {
        try query(sql: """
        SELECT id, job_id, graph_id, source_id, source_type, outcome, admission_action, admission_reasons_json, extracted_entity_count, extracted_statement_count, committed_entity_count, committed_statement_count, anomaly_count, error_message, created_at, metadata_json
        FROM graph_extraction_traces WHERE id = \(quote(id)) LIMIT 1
        """).map(decodeExtractionTrace).first
    }

    public func extractionTraces(graphID: String, sourceID: String? = nil, limit: Int = 100) throws -> [GraphExtractionTrace] {
        var conditions = ["graph_id = \(quote(graphID))"]
        if let sourceID { conditions.append("source_id = \(quote(sourceID))") }
        return try query(sql: """
        SELECT id, job_id, graph_id, source_id, source_type, outcome, admission_action, admission_reasons_json, extracted_entity_count, extracted_statement_count, committed_entity_count, committed_statement_count, anomaly_count, error_message, created_at, metadata_json
        FROM graph_extraction_traces WHERE \(conditions.joined(separator: " AND ")) ORDER BY created_at DESC LIMIT \(limit)
        """).map(decodeExtractionTrace)
    }

    public func appendExtractionTracePayload(_ payload: GraphExtractionTracePayload) throws {
        try execute("""
        INSERT OR REPLACE INTO graph_extraction_trace_payloads
        (trace_id, prompt_text, raw_response_json, normalized_json, decoder_error_kind, decoder_error_message, created_at, metadata_json)
        VALUES (\(quote(payload.traceID)), \(quote(payload.promptText)), \(quote(payload.rawResponseJSON)), \(quote(payload.normalizedJSON)), \(quote(payload.decoderErrorKind)), \(quote(payload.decoderErrorMessage)), \(quote(iso(payload.createdAt))), \(quote(json(payload.metadata))))
        """)
    }

    public func extractionTracePayload(traceID: String) throws -> GraphExtractionTracePayload? {
        try query(sql: """
        SELECT trace_id, prompt_text, raw_response_json, normalized_json, decoder_error_kind, decoder_error_message, created_at, metadata_json
        FROM graph_extraction_trace_payloads WHERE trace_id = \(quote(traceID)) LIMIT 1
        """).map(decodeExtractionTracePayload).first
    }

    @discardableResult
    public func enqueueExtractionJob(
        graphID: String,
        source: GraphExtractionSource,
        priority: Int = 5,
        now: Date = Date()
    ) throws -> String {
        let jobID = "job-extraction-\(source.id)"
        let payload = GraphExtractionJobPayload(source: source).dictionary
        try upsert(job: GraphJobV3(
            id: jobID,
            graphID: graphID,
            type: .extraction,
            status: .queued,
            priority: priority,
            payload: payload,
            createdAt: now,
            updatedAt: now,
            nextRunAt: now
        ))
        return jobID
    }

    public func seedBaseOntology(graphID: String) throws {
        let specs: [(String, String, Int, String, GraphEntityKind)] = Self.baseOntologySpecs()
        for (classID, displayName, layer, domain, _) in specs {
            let entityID = "class-\(classID)"
            let entity = GraphEntity(
                id: entityID,
                graphID: graphID,
                name: displayName,
                stableKey: "\(GraphScope.publicScope.rawValue):\(GraphEntityKind.classNode.rawValue):\(classID)",
                entityKind: .classNode,
                scope: .publicScope,
                canonicalClassID: "class",
                summary: "Ontology class: \(displayName)",
                metadata: ["class_id": classID, "domain": domain]
            )
            try upsert(entity: entity)
            try upsert(ontologyClass: GraphOntologyClass(
                id: "ontology-\(classID)",
                graphID: graphID,
                classEntityID: entityID,
                classID: classID,
                displayName: displayName,
                layer: layer,
                domain: domain,
                description: "Seed ontology class \(displayName)"
            ))
        }
    }

    public func searchEntitiesFTS(query text: String, graphID: String, limit: Int) throws -> [GraphEntity] {
        let ids = try query(sql: "SELECT entity_id FROM graph_entities_fts WHERE graph_entities_fts MATCH \(quote(text)) AND graph_id = \(quote(graphID)) LIMIT \(limit)").compactMap { $0.first }
        return try ids.compactMap { try entity(id: $0) }
    }

    public func searchStatementsFTS(query text: String, graphID: String, limit: Int) throws -> [GraphStatement] {
        let ids = try query(sql: "SELECT statement_id FROM graph_statements_fts WHERE graph_statements_fts MATCH \(quote(text)) AND graph_id = \(quote(graphID)) LIMIT \(limit)").compactMap { $0.first }
        return try ids.compactMap { try statement(id: $0) }
    }

    // MARK: - Graph Write Candidates

    public func upsertWriteCandidate(_ candidate: GraphWriteCandidate) throws {
        try execute("""
        INSERT OR REPLACE INTO graph_write_candidates
        (id, group_id, kind, proposed_by_run_id, proposed_by_tool_call_id, rationale, confidence, payload_json, source_episode_ids_json, related_node_ids_json, related_fact_ids_json, status, validation_errors_json, created_at, updated_at)
        VALUES (\(quote(candidate.id)), \(quote(candidate.groupID)), \(quote(candidate.kind.rawValue)), \(quote(candidate.proposedByRunID)), \(quote(candidate.proposedByToolCallID)), \(quote(candidate.rationale)), \(candidate.confidence), \(quote(candidate.payloadJSON)), \(quote(json(candidate.sourceEpisodeIDs))), \(quote(json(candidate.relatedNodeIDs))), \(quote(json(candidate.relatedFactIDs))), \(quote(candidate.status.rawValue)), \(quote(json(candidate.validationErrors))), \(quote(iso(candidate.createdAt))), \(quote(iso(candidate.updatedAt))))
        """)
    }

    public func writeCandidates(groupID: String, status: GraphWriteCandidateStatus? = nil, limit: Int = 100) throws -> [GraphWriteCandidate] {
        var conditions = ["group_id = \(quote(groupID))"]
        if let status { conditions.append("status = \(quote(status.rawValue))") }
        return try query(sql: """
        SELECT id, group_id, kind, proposed_by_run_id, proposed_by_tool_call_id, rationale, confidence, payload_json, source_episode_ids_json, related_node_ids_json, related_fact_ids_json, status, validation_errors_json, created_at, updated_at
        FROM graph_write_candidates WHERE \(conditions.joined(separator: " AND ")) ORDER BY created_at DESC LIMIT \(limit)
        """).map(decodeWriteCandidate)
    }

    private func decodeWriteCandidate(_ row: [String]) throws -> GraphWriteCandidate {
        GraphWriteCandidate(
            id: row[0], groupID: row[1], kind: GraphWriteCandidateKind(rawValue: row[2]) ?? .createNode,
            proposedByRunID: row[3], proposedByToolCallID: nilIfEmpty(row[4]),
            rationale: row[5], confidence: Double(row[6]) ?? 0, payloadJSON: row[7],
            sourceEpisodeIDs: try decode([String].self, row[8]),
            relatedNodeIDs: try decode([String].self, row[9]),
            relatedFactIDs: try decode([String].self, row[10]),
            status: GraphWriteCandidateStatus(rawValue: row[11]) ?? .pendingValidation,
            validationErrors: try decode([String].self, row[12]),
            createdAt: try date(row[13]), updatedAt: try date(row[14])
        )
    }

    // MARK: - Agent Sessions

    public func upsertSession(_ session: AgentSession) throws {
        try execute("""
        INSERT OR REPLACE INTO agent_sessions
        (id, title, messages_json, created_at, updated_at)
        VALUES (\(quote(session.id)), \(quote(session.title)), \(quote(json(session.messages))), \(quote(iso(session.createdAt))), \(quote(iso(session.updatedAt))))
        """)
    }

    public func session(id: String) throws -> AgentSession? {
        let rows = try query(sql: "SELECT id, title, messages_json, created_at, updated_at FROM agent_sessions WHERE id = \(quote(id))")
        guard let row = rows.first else { return nil }
        return try decodeSession(row)
    }

    public func recentSessions(limit: Int = 50) throws -> [AgentSession] {
        try query(sql: "SELECT id, title, messages_json, created_at, updated_at FROM agent_sessions ORDER BY updated_at DESC LIMIT \(limit)").map(decodeSession)
    }

    private func decodeSession(_ row: [String]) throws -> AgentSession {
        AgentSession(
            id: row[0], title: row[1],
            messages: try decode([AgentMessage].self, row[2]),
            createdAt: try date(row[3]), updatedAt: try date(row[4])
        )
    }

    // MARK: - Agent Runs & Events

    public func upsert(run: AgentRun) throws {
        try execute("""
        INSERT OR REPLACE INTO agent_runs
        (id, session_id, group_id, status, started_at, completed_at, model, metadata_json)
        VALUES (\(quote(run.id)), \(quote(run.sessionID)), \(quote(run.groupID)), \(quote(run.status.rawValue)), \(quote(iso(run.startedAt))), \(quote(run.completedAt.map(iso))), \(quote(run.model)), \(quote(json(run.metadata))))
        """)
    }

    public func append(event: PersistedAgentEvent) throws {
        let seqStr = event.sequence.map(String.init) ?? "NULL"
        try execute("""
        INSERT INTO agent_events
        (id, run_id, session_id, kind, payload_json, sequence, created_at)
        VALUES (\(quote(event.id)), \(quote(event.runID)), \(quote(event.sessionID)), \(quote(event.kind.rawValue)), \(quote(event.payloadJSON)), \(seqStr), \(quote(iso(event.createdAt))))
        """)
    }

    // MARK: - Agent Audit Events

    public func append(auditEvent: AgentAuditEvent) throws {
        try execute("""
        INSERT INTO agent_audit_events
        (id, run_id, session_id, event_type, actor, capability, tool_name, decision, payload_json, created_at)
        VALUES (\(quote(auditEvent.id)), \(quote(auditEvent.runID)), \(quote(auditEvent.sessionID)), \(quote(auditEvent.eventType.rawValue)), \(quote(auditEvent.actor)), \(quote(auditEvent.capability?.rawValue)), \(quote(auditEvent.toolName)), \(quote(auditEvent.decision.map { json($0) })), \(quote(auditEvent.payloadJSON)), \(quote(iso(auditEvent.createdAt))))
        """)
    }

    private func upsertEntityFTS(_ entity: GraphEntity) throws {
        try execute("DELETE FROM graph_entities_fts WHERE entity_id = \(quote(entity.id));")
        try execute("""
        INSERT INTO graph_entities_fts(entity_id, graph_id, entity_kind, name, aliases, summary)
        VALUES (\(quote(entity.id)), \(quote(entity.graphID)), \(quote(entity.entityKind.rawValue)), \(quote(entity.name)), \(quote(entity.aliases.joined(separator: " "))), \(quote(entity.summary)))
        """)
    }

    private func upsertStatementFTS(_ statement: GraphStatement) throws {
        let subjectName = (try? entity(id: statement.subjectEntityID)?.name) ?? ""
        let objectName = (try? entity(id: statement.objectEntityID)?.name) ?? ""
        try execute("DELETE FROM graph_statements_fts WHERE statement_id = \(quote(statement.id));")
        try execute("""
        INSERT INTO graph_statements_fts(statement_id, graph_id, predicate, edge_kind, statement_text, subject_name, object_name)
        VALUES (\(quote(statement.id)), \(quote(statement.graphID)), \(quote(statement.predicate.rawValue)), \(quote(statement.edgeKind.rawValue)), \(quote(statement.statementText)), \(quote(subjectName)), \(quote(objectName)))
        """)
    }

    public static func baseOntologySpecs() -> [(String, String, Int, String, GraphEntityKind)] {
        let general = ["person", "organization", "location", "event", "artifact", "software", "hardware", "concept", "data_structure", "process", "metric", "time_expression", "publication", "law_policy", "natural_object"].map { ($0, $0.replacingOccurrences(of: "_", with: " "), 0, "general", GraphEntityKind.classNode) }
        let personal = ["email", "message", "conversation_thread", "contact", "calendar_event", "reminder", "task", "commitment", "preference", "habit", "goal", "address", "home", "family_member", "bill", "subscription", "health_record", "device", "account", "credential_reference", "purchase", "travel_plan", "meal", "exercise"].map { ($0, $0.replacingOccurrences(of: "_", with: " "), 1, "personal-life", GraphEntityKind.classNode) }
        let knowledge = ["question", "answer", "decision", "sop", "runbook", "work_object", "project", "milestone", "issue", "repository", "code_module", "design_doc", "research_note", "source_document", "claim", "argument", "constraint", "risk", "requirement"].map { ($0, $0.replacingOccurrences(of: "_", with: " "), 2, "knowledge-project", GraphEntityKind.classNode) }
        return general + personal + knowledge
    }

    private func decodeEpisode(_ row: [String]) throws -> GraphEpisodeV3 {
        GraphEpisodeV3(
            id: row[0], graphID: row[1], sourceType: GraphEpisodeV3SourceType(rawValue: row[2]) ?? .manual, sourceID: nilIfEmpty(row[3]), title: row[4], content: row[5], sourceDescription: row[6], occurredAt: try date(row[7]), ingestedAt: try date(row[8]), sessionID: nilIfEmpty(row[9]), workObjectID: nilIfEmpty(row[10]), status: GraphEntityStatus(rawValue: row[11]) ?? .active, metadata: try decode([String: String].self, row[12])
        )
    }

    private func decodeEntity(_ row: [String]) throws -> GraphEntity {
        GraphEntity(
            id: row[0], graphID: row[1], name: row[2], stableKey: row[3], entityKind: GraphEntityKind(rawValue: row[4]) ?? .entity, scope: GraphScope(rawValue: row[5]) ?? .personal, canonicalClassID: nilIfEmpty(row[6]), aliases: try decode([String].self, row[7]), summary: row[8], confidence: Double(row[9]) ?? 0, status: GraphEntityStatus(rawValue: row[10]) ?? .active, createdAt: try date(row[11]), updatedAt: try date(row[12]), validFrom: try optionalDate(row[13]), validUntil: try optionalDate(row[14]), supersededByEntityID: nilIfEmpty(row[15]), metadata: try decode([String: String].self, row[16])
        )
    }

    private func decodeStatement(_ row: [String]) throws -> GraphStatement {
        GraphStatement(
            id: row[0], graphID: row[1], subjectEntityID: row[2], predicate: GraphPredicate(rawValue: row[3]) ?? .relatedTo, objectEntityID: row[4], statementText: row[5], edgeKind: GraphEdgeKind(rawValue: row[6]) ?? .structural, validAt: try date(row[7]), invalidAt: try optionalDate(row[8]), committedAt: try date(row[9]), referenceTime: try optionalDate(row[10]), confidence: Double(row[11]) ?? 0, beliefStatus: GraphBeliefStatus(rawValue: row[12]) ?? .active, justifications: try decode([GraphJustification].self, row[13]), sourceEpisodeIDs: try decode([String].self, row[14]), invalidatedByStatementID: nilIfEmpty(row[15]), supersedesStatementIDs: try decode([String].self, row[16]), metadata: try decode([String: String].self, row[17])
        )
    }

    private func decodeOntologyClass(_ row: [String]) throws -> GraphOntologyClass {
        GraphOntologyClass(
            id: row[0], graphID: row[1], classEntityID: row[2], classID: row[3], displayName: row[4], layer: Int(row[5]) ?? 0, domain: row[6], lifecycleStatus: GraphOntologyClassLifecycleStatus(rawValue: row[7]) ?? .curated, description: row[8], createdAt: try date(row[9]), updatedAt: try date(row[10]), metadata: try decode([String: String].self, row[11])
        )
    }

    private func decodeAnomaly(_ row: [String]) throws -> GraphAnomaly {
        GraphAnomaly(
            id: row[0], graphID: row[1], anomalyType: GraphAnomalyType(rawValue: row[2]) ?? .commonSenseViolation, statementID: row[3], relatedStatementIDs: try decode([String].self, row[4]), severity: GraphAnomalySeverity(rawValue: row[5]) ?? .medium, status: GraphAnomalyStatus(rawValue: row[6]) ?? .open, detectedAt: try date(row[7]), resolvedAt: try optionalDate(row[8]), resolution: try decode([String: String].self, row[9]), metadata: try decode([String: String].self, row[10])
        )
    }

    private func decodeExtractionTracePayload(_ row: [String]) throws -> GraphExtractionTracePayload {
        GraphExtractionTracePayload(
            traceID: row[0],
            promptText: nilIfEmpty(row[1]),
            rawResponseJSON: nilIfEmpty(row[2]),
            normalizedJSON: nilIfEmpty(row[3]),
            decoderErrorKind: nilIfEmpty(row[4]),
            decoderErrorMessage: nilIfEmpty(row[5]),
            createdAt: try date(row[6]),
            metadata: try decode([String: String].self, row[7])
        )
    }

    private func decodeExtractionTrace(_ row: [String]) throws -> GraphExtractionTrace {
        let reasonRawValues = try decode([String].self, row[7])
        return GraphExtractionTrace(
            id: row[0],
            jobID: row[1],
            graphID: row[2],
            sourceID: row[3],
            sourceType: GraphExtractionSourceType(rawValue: row[4]) ?? .manual,
            outcome: GraphExtractionTraceOutcome(rawValue: row[5]) ?? .failed,
            admissionAction: nilIfEmpty(row[6]).flatMap(GraphWriteAdmissionDecisionAction.init(rawValue:)),
            admissionReasons: reasonRawValues.compactMap(GraphWriteAdmissionReason.init(rawValue:)),
            extractedEntityCount: Int(row[8]) ?? 0,
            extractedStatementCount: Int(row[9]) ?? 0,
            committedEntityCount: Int(row[10]) ?? 0,
            committedStatementCount: Int(row[11]) ?? 0,
            anomalyCount: Int(row[12]) ?? 0,
            errorMessage: nilIfEmpty(row[13]),
            createdAt: try date(row[14]),
            metadata: try decode([String: String].self, row[15])
        )
    }

    private func decodeJob(_ row: [String]) throws -> GraphJobV3 {
        GraphJobV3(
            id: row[0], graphID: row[1], type: GraphJobV3Type(rawValue: row[2]) ?? .indexRefresh, status: GraphJobV3Status(rawValue: row[3]) ?? .queued, priority: Int(row[4]) ?? 0, payload: try decode([String: String].self, row[5]), attemptCount: Int(row[6]) ?? 0, maxAttempts: Int(row[7]) ?? 3, createdAt: try date(row[8]), updatedAt: try date(row[9]), nextRunAt: try date(row[10]), startedAt: try optionalDate(row[11]), finishedAt: try optionalDate(row[12]), errorCode: nilIfEmpty(row[13]), errorMessage: nilIfEmpty(row[14]), metadata: try decode([String: String].self, row[15])
        )
    }

    private func execute(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteGraphKernelStoreError.executeFailed(Self.message(db))
        }
    }

    private func query(sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteGraphKernelStoreError.prepareFailed(Self.message(db))
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
                throw SQLiteGraphKernelStoreError.stepFailed(Self.message(db))
            }
        }
        return rows
    }

    private func queryStrings(sql: String) throws -> [String] {
        try query(sql: sql).compactMap { $0.first }
    }

    private func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private func decode<T: Decodable>(_ type: T.Type, _ value: String) throws -> T {
        guard let data = value.data(using: .utf8) else { throw SQLiteGraphKernelStoreError.decodeFailed("Invalid UTF-8") }
        do { return try decoder.decode(type, from: data) } catch { throw SQLiteGraphKernelStoreError.decodeFailed(String(describing: error)) }
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func date(_ string: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: string) else { throw SQLiteGraphKernelStoreError.decodeFailed("Invalid date: \(string)") }
        return date
    }

    private func optionalDate(_ string: String) throws -> Date? {
        guard !string.isEmpty else { return nil }
        return try date(string)
    }

    private func nilIfEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }

    private func quote(_ value: String?) -> String {
        guard let value else { return "NULL" }
        return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func message(_ db: OpaquePointer?) -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "Unknown SQLite error" }
        return String(cString: message)
    }
}
