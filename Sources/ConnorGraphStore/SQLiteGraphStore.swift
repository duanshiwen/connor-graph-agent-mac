import Foundation
import SQLite3
import ConnorGraphCore
import ConnorGraphMemory

public enum SQLiteGraphStoreError: Error, Equatable, CustomStringConvertible {
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

private struct ChatMessageMetadata: Codable, Equatable {
    var promptInspection: AgentPromptInspectionSnapshot?

    init(promptInspection: AgentPromptInspectionSnapshot? = nil) {
        self.promptInspection = promptInspection
    }
}

public final class SQLiteGraphStore: @unchecked Sendable {
    private let path: String
    private var db: OpaquePointer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(path: String) throws {
        self.path = path
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601

        if sqlite3_open(path, &db) != SQLITE_OK {
            throw SQLiteGraphStoreError.openFailed(Self.message(db))
        }
    }

    deinit {
        sqlite3_close(db)
    }

    public func migrate() throws {
        try execute("PRAGMA foreign_keys = ON;")
        try execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_nodes (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            source_path TEXT,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            valid_at TEXT,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS semantic_edges (
            id TEXT PRIMARY KEY,
            source_node_id TEXT NOT NULL,
            target_node_id TEXT NOT NULL,
            relation TEXT NOT NULL,
            fact TEXT NOT NULL,
            confidence REAL NOT NULL,
            created_at TEXT NOT NULL,
            valid_at TEXT,
            invalid_at TEXT,
            source_episode_id TEXT,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS observe_log_entries (
            id TEXT PRIMARY KEY,
            timestamp TEXT NOT NULL,
            kind TEXT NOT NULL,
            source TEXT NOT NULL,
            content TEXT NOT NULL,
            normalized_summary TEXT NOT NULL,
            work_object_id TEXT,
            session_id TEXT,
            related_node_ids_json TEXT NOT NULL,
            related_edge_ids_json TEXT NOT NULL,
            importance REAL NOT NULL,
            confidence REAL NOT NULL,
            status TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            promoted_node_id TEXT,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_nodes_type ON graph_nodes(type);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_nodes_status ON graph_nodes(status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_semantic_edges_source ON semantic_edges(source_node_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_semantic_edges_target ON semantic_edges(target_node_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_semantic_edges_relation ON semantic_edges(relation);")
        try execute("""
        CREATE TABLE IF NOT EXISTS chat_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS chat_messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL,
            citations_json TEXT NOT NULL,
            context_snapshot TEXT,
            metadata_json TEXT NOT NULL,
            FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_observe_log_status ON observe_log_entries(status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_observe_log_expires_at ON observe_log_entries(expires_at);")
        try execute("""
        CREATE TABLE IF NOT EXISTS chat_session_summaries (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            source_message_count INTEGER NOT NULL,
            last_message_id TEXT,
            metadata_json TEXT NOT NULL,
            FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_chat_sessions_updated_at ON chat_sessions(updated_at);")
        try execute("CREATE INDEX IF NOT EXISTS idx_chat_messages_session_id ON chat_messages(session_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON chat_messages(created_at);")
        try execute("CREATE INDEX IF NOT EXISTS idx_chat_session_summaries_session_updated_at ON chat_session_summaries(session_id, updated_at);")

        try migrateGraphitiGradeV2Schema()

        try execute("""
        INSERT OR IGNORE INTO schema_migrations(version, applied_at)
        VALUES (1, \(quote(iso(Date()))));
        """)
    }

    private func migrateGraphitiGradeV2Schema() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_episodes (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            source_type TEXT NOT NULL,
            source_id TEXT,
            name TEXT NOT NULL,
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
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_episodes_group_time ON graph_episodes(group_id, occurred_at DESC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_episodes_source ON graph_episodes(source_type, source_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_episodes_session ON graph_episodes(session_id, occurred_at DESC);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_nodes_v2 (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            stable_key TEXT,
            type TEXT NOT NULL,
            canonical_name TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            labels_json TEXT NOT NULL,
            attributes_json TEXT NOT NULL,
            status TEXT NOT NULL,
            confidence REAL NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            valid_from TEXT,
            valid_until TEXT,
            superseded_by_node_id TEXT,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_graph_nodes_v2_stable_key ON graph_nodes_v2(group_id, stable_key) WHERE stable_key IS NOT NULL;")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_nodes_v2_type ON graph_nodes_v2(group_id, type, status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_nodes_v2_name ON graph_nodes_v2(group_id, canonical_name);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_nodes_v2_updated ON graph_nodes_v2(group_id, updated_at DESC);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_facts (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            source_node_id TEXT NOT NULL,
            target_node_id TEXT NOT NULL,
            relation TEXT NOT NULL,
            fact TEXT NOT NULL,
            confidence REAL NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            valid_at TEXT,
            invalid_at TEXT,
            expired_at TEXT,
            reference_time TEXT,
            invalidated_by_fact_id TEXT,
            attributes_json TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            FOREIGN KEY(source_node_id) REFERENCES graph_nodes_v2(id),
            FOREIGN KEY(target_node_id) REFERENCES graph_nodes_v2(id)
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_facts_source ON graph_facts(group_id, source_node_id, status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_facts_target ON graph_facts(group_id, target_node_id, status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_facts_relation ON graph_facts(group_id, relation, status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_facts_temporal ON graph_facts(group_id, valid_at, invalid_at, expired_at);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_facts_updated ON graph_facts(group_id, updated_at DESC);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_mentions (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            episode_id TEXT NOT NULL,
            node_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            confidence REAL NOT NULL,
            metadata_json TEXT NOT NULL,
            UNIQUE(episode_id, node_id),
            FOREIGN KEY(episode_id) REFERENCES graph_episodes(id),
            FOREIGN KEY(node_id) REFERENCES graph_nodes_v2(id)
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_mentions_episode ON graph_mentions(group_id, episode_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_mentions_node ON graph_mentions(group_id, node_id);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_fact_sources (
            fact_id TEXT NOT NULL,
            episode_id TEXT NOT NULL,
            group_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY(fact_id, episode_id),
            FOREIGN KEY(fact_id) REFERENCES graph_facts(id),
            FOREIGN KEY(episode_id) REFERENCES graph_episodes(id)
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_fact_sources_episode ON graph_fact_sources(group_id, episode_id);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_generation_runs (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            trigger_type TEXT NOT NULL,
            trigger_id TEXT,
            status TEXT NOT NULL,
            started_at TEXT,
            finished_at TEXT,
            model TEXT,
            prompt_tokens INTEGER NOT NULL DEFAULT 0,
            completion_tokens INTEGER NOT NULL DEFAULT 0,
            estimated_cost_microunits INTEGER NOT NULL DEFAULT 0,
            actual_cost_microunits INTEGER NOT NULL DEFAULT 0,
            error_message TEXT,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_generation_runs_status ON graph_generation_runs(group_id, status);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_node_candidates (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            episode_id TEXT NOT NULL,
            group_id TEXT NOT NULL,
            proposed_type TEXT NOT NULL,
            proposed_name TEXT NOT NULL,
            proposed_summary TEXT NOT NULL,
            proposed_labels_json TEXT NOT NULL,
            proposed_attributes_json TEXT NOT NULL,
            status TEXT NOT NULL,
            resolved_node_id TEXT,
            resolution_reason TEXT,
            confidence REAL NOT NULL,
            created_at TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_node_candidates_run ON graph_node_candidates(run_id, status);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_fact_candidates (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            episode_id TEXT NOT NULL,
            group_id TEXT NOT NULL,
            source_candidate_id TEXT,
            target_candidate_id TEXT,
            source_node_id TEXT,
            target_node_id TEXT,
            relation TEXT NOT NULL,
            fact TEXT NOT NULL,
            valid_at TEXT,
            invalid_at TEXT,
            status TEXT NOT NULL,
            resolved_fact_id TEXT,
            resolution_reason TEXT,
            confidence REAL NOT NULL,
            created_at TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_fact_candidates_run ON graph_fact_candidates(run_id, status);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_embeddings (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            owner_type TEXT NOT NULL,
            owner_id TEXT NOT NULL,
            embedding_model TEXT NOT NULL,
            dimensions INTEGER NOT NULL,
            vector_blob BLOB NOT NULL,
            vector_norm REAL NOT NULL,
            content_hash TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(owner_type, owner_id, embedding_model, content_hash)
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_embeddings_owner ON graph_embeddings(group_id, owner_type, owner_id);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_embeddings_model ON graph_embeddings(group_id, embedding_model, owner_type);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_index_tasks (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            owner_type TEXT NOT NULL,
            owner_id TEXT NOT NULL,
            task_type TEXT NOT NULL,
            status TEXT NOT NULL,
            attempt_count INTEGER NOT NULL,
            next_run_at TEXT NOT NULL,
            error_message TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_index_tasks_runnable ON graph_index_tasks(status, next_run_at);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_index_tasks_owner ON graph_index_tasks(group_id, owner_type, owner_id);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_jobs (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            priority INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            attempt_count INTEGER NOT NULL,
            max_attempts INTEGER NOT NULL,
            next_run_at TEXT NOT NULL,
            lease_owner TEXT,
            lease_expires_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            started_at TEXT,
            finished_at TEXT,
            error_code TEXT,
            error_message TEXT,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_jobs_runnable ON graph_jobs(status, next_run_at, priority DESC);")
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_jobs_lease ON graph_jobs(status, lease_expires_at);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_job_events (
            id TEXT PRIMARY KEY,
            job_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            message TEXT NOT NULL,
            created_at TEXT NOT NULL,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_graph_job_events_job ON graph_job_events(job_id, created_at);")

        try execute("""
        CREATE TABLE IF NOT EXISTS graph_cost_budgets (
            id TEXT PRIMARY KEY,
            scope_type TEXT NOT NULL,
            scope_id TEXT NOT NULL,
            period TEXT NOT NULL,
            token_limit INTEGER,
            cost_limit_microunits INTEGER,
            used_prompt_tokens INTEGER NOT NULL,
            used_completion_tokens INTEGER NOT NULL,
            used_cost_microunits INTEGER NOT NULL,
            reset_at TEXT,
            metadata_json TEXT NOT NULL
        );
        """)
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_graph_cost_budgets_scope ON graph_cost_budgets(scope_type, scope_id, period);")

        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS graph_nodes_fts USING fts5(
            node_id UNINDEXED,
            group_id UNINDEXED,
            type UNINDEXED,
            title,
            canonical_name,
            summary,
            labels,
            attributes,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """)
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS graph_facts_fts USING fts5(
            fact_id UNINDEXED,
            group_id UNINDEXED,
            relation UNINDEXED,
            fact,
            source_name,
            target_name,
            attributes,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """)
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS graph_episodes_fts USING fts5(
            episode_id UNINDEXED,
            group_id UNINDEXED,
            source_type UNINDEXED,
            content,
            source_description,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """)
    }

    public func tableNames() throws -> Set<String> {
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table';"
        return Set(try queryStrings(sql: sql))
    }

    public func indexNames() throws -> Set<String> {
        let sql = "SELECT name FROM sqlite_master WHERE type = 'index';"
        return Set(try queryStrings(sql: sql))
    }

    public func upsert(episode: GraphEpisode) throws {
        let sql = """
        INSERT OR REPLACE INTO graph_episodes
        (id, group_id, source_type, source_id, name, content, source_description, occurred_at, ingested_at, session_id, work_object_id, status, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(episode.id, at: 1, in: statement)
            try bind(episode.groupID, at: 2, in: statement)
            try bind(episode.sourceType.rawValue, at: 3, in: statement)
            try bind(episode.sourceID, at: 4, in: statement)
            try bind(episode.name, at: 5, in: statement)
            try bind(episode.content, at: 6, in: statement)
            try bind(episode.sourceDescription, at: 7, in: statement)
            try bind(iso(episode.occurredAt), at: 8, in: statement)
            try bind(iso(episode.ingestedAt), at: 9, in: statement)
            try bind(episode.sessionID, at: 10, in: statement)
            try bind(episode.workObjectID, at: 11, in: statement)
            try bind(episode.status.rawValue, at: 12, in: statement)
            try bind(jsonString(episode.metadata), at: 13, in: statement)
            try stepDone(statement)
        }
        try scheduleFTSIndex(ownerType: .episode, ownerID: episode.id, groupID: episode.groupID)
    }

    public func graphEpisode(id: String) throws -> GraphEpisode? {
        let sql = """
        SELECT id, group_id, source_type, source_id, name, content, source_description, occurred_at, ingested_at, session_id, work_object_id, status, metadata_json
        FROM graph_episodes WHERE id = ? LIMIT 1;
        """
        return try withStatement(sql) { statement in
            try bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeGraphEpisode(statement)
        }
    }

    public func upsert(nodeV2 node: GraphNodeV2) throws {
        let sql = """
        INSERT OR REPLACE INTO graph_nodes_v2
        (id, group_id, stable_key, type, canonical_name, title, summary, labels_json, attributes_json, status, confidence, created_at, updated_at, valid_from, valid_until, superseded_by_node_id, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(node.id, at: 1, in: statement)
            try bind(node.groupID, at: 2, in: statement)
            try bind(node.stableKey, at: 3, in: statement)
            try bind(node.type.rawValue, at: 4, in: statement)
            try bind(node.canonicalName, at: 5, in: statement)
            try bind(node.title, at: 6, in: statement)
            try bind(node.summary, at: 7, in: statement)
            try bind(jsonString(node.labels), at: 8, in: statement)
            try bind(jsonString(node.attributes), at: 9, in: statement)
            try bind(node.status.rawValue, at: 10, in: statement)
            sqlite3_bind_double(statement, 11, node.confidence)
            try bind(iso(node.createdAt), at: 12, in: statement)
            try bind(iso(node.updatedAt), at: 13, in: statement)
            try bind(node.validFrom.map(iso), at: 14, in: statement)
            try bind(node.validUntil.map(iso), at: 15, in: statement)
            try bind(node.supersededByNodeID, at: 16, in: statement)
            try bind(jsonString(node.metadata), at: 17, in: statement)
            try stepDone(statement)
        }
        try scheduleFTSIndex(ownerType: .node, ownerID: node.id, groupID: node.groupID)
    }

    public func graphNodeV2(id: String) throws -> GraphNodeV2? {
        let sql = """
        SELECT id, group_id, stable_key, type, canonical_name, title, summary, labels_json, attributes_json, status, confidence, created_at, updated_at, valid_from, valid_until, superseded_by_node_id, metadata_json
        FROM graph_nodes_v2 WHERE id = ? LIMIT 1;
        """
        return try withStatement(sql) { statement in
            try bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeGraphNodeV2(statement)
        }
    }

    public func upsert(fact: GraphFact, sourceEpisodeIDs: [String] = []) throws {
        let sql = """
        INSERT OR REPLACE INTO graph_facts
        (id, group_id, source_node_id, target_node_id, relation, fact, confidence, status, created_at, updated_at, valid_at, invalid_at, expired_at, reference_time, invalidated_by_fact_id, attributes_json, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(fact.id, at: 1, in: statement)
            try bind(fact.groupID, at: 2, in: statement)
            try bind(fact.sourceNodeID, at: 3, in: statement)
            try bind(fact.targetNodeID, at: 4, in: statement)
            try bind(fact.relation.rawValue, at: 5, in: statement)
            try bind(fact.fact, at: 6, in: statement)
            sqlite3_bind_double(statement, 7, fact.confidence)
            try bind(fact.status.rawValue, at: 8, in: statement)
            try bind(iso(fact.createdAt), at: 9, in: statement)
            try bind(iso(fact.updatedAt), at: 10, in: statement)
            try bind(fact.validAt.map(iso), at: 11, in: statement)
            try bind(fact.invalidAt.map(iso), at: 12, in: statement)
            try bind(fact.expiredAt.map(iso), at: 13, in: statement)
            try bind(fact.referenceTime.map(iso), at: 14, in: statement)
            try bind(fact.invalidatedByFactID, at: 15, in: statement)
            try bind(jsonString(fact.attributes), at: 16, in: statement)
            try bind(jsonString(fact.metadata), at: 17, in: statement)
            try stepDone(statement)
        }
        for episodeID in sourceEpisodeIDs {
            try upsertFactSource(factID: fact.id, episodeID: episodeID, groupID: fact.groupID)
        }
        try scheduleFTSIndex(ownerType: .fact, ownerID: fact.id, groupID: fact.groupID)
    }

    public func graphFact(id: String) throws -> GraphFact? {
        let sql = """
        SELECT id, group_id, source_node_id, target_node_id, relation, fact, confidence, status, created_at, updated_at, valid_at, invalid_at, expired_at, reference_time, invalidated_by_fact_id, attributes_json, metadata_json
        FROM graph_facts WHERE id = ? LIMIT 1;
        """
        return try withStatement(sql) { statement in
            try bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeGraphFact(statement)
        }
    }

    public func sourceEpisodeIDs(factID: String) throws -> [String] {
        let sql = "SELECT episode_id FROM graph_fact_sources WHERE fact_id = ? ORDER BY episode_id ASC;"
        return try withStatement(sql) { statement in
            try bind(factID, at: 1, in: statement)
            var ids: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let id = text(statement, 0) { ids.append(id) }
            }
            return ids
        }
    }

    private func upsertFactSource(factID: String, episodeID: String, groupID: String) throws {
        let sql = """
        INSERT OR REPLACE INTO graph_fact_sources (fact_id, episode_id, group_id, created_at)
        VALUES (?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(factID, at: 1, in: statement)
            try bind(episodeID, at: 2, in: statement)
            try bind(groupID, at: 3, in: statement)
            try bind(iso(Date()), at: 4, in: statement)
            try stepDone(statement)
        }
    }

    public func upsert(embedding: GraphEmbedding) throws {
        guard embedding.vectorNorm > 0 else {
            throw SQLiteGraphStoreError.decodeFailed("graph_embeddings vector_norm must be positive")
        }
        let sql = """
        INSERT OR REPLACE INTO graph_embeddings
        (id, group_id, owner_type, owner_id, embedding_model, dimensions, vector_blob, vector_norm, content_hash, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let vectorData = try vectorBlob(embedding.vector)
        try withStatement(sql) { statement in
            try bind(embedding.id, at: 1, in: statement)
            try bind(embedding.groupID, at: 2, in: statement)
            try bind(embedding.ownerType.rawValue, at: 3, in: statement)
            try bind(embedding.ownerID, at: 4, in: statement)
            try bind(embedding.embeddingModel, at: 5, in: statement)
            sqlite3_bind_int(statement, 6, Int32(embedding.vector.count))
            try bind(vectorData, at: 7, in: statement)
            sqlite3_bind_double(statement, 8, embedding.vectorNorm)
            try bind(embedding.contentHash, at: 9, in: statement)
            try bind(iso(embedding.createdAt), at: 10, in: statement)
            try stepDone(statement)
        }
    }

    public func graphEmbedding(id: String) throws -> GraphEmbedding? {
        let sql = """
        SELECT id, group_id, owner_type, owner_id, embedding_model, dimensions, vector_blob, vector_norm, content_hash, created_at
        FROM graph_embeddings
        WHERE id = ?;
        """
        return try withStatement(sql) { statement in
            try bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeGraphEmbedding(statement)
        }
    }

    public func searchEmbeddings(
        queryVector: [Double],
        groupID: String,
        embeddingModel: String,
        ownerTypes: Set<GraphIndexOwnerType> = Set(GraphIndexOwnerType.allCases),
        limit: Int
    ) throws -> [GraphEmbeddingSearchResult] {
        guard !queryVector.isEmpty, limit > 0 else { return [] }
        let queryNorm = GraphEmbedding.norm(queryVector)
        guard queryNorm > 0 else { return [] }
        let sql = """
        SELECT id, group_id, owner_type, owner_id, embedding_model, dimensions, vector_blob, vector_norm, content_hash, created_at
        FROM graph_embeddings
        WHERE group_id = ? AND embedding_model = ? AND dimensions = ?;
        """
        var results: [GraphEmbeddingSearchResult] = []
        try withStatement(sql) { statement in
            try bind(groupID, at: 1, in: statement)
            try bind(embeddingModel, at: 2, in: statement)
            sqlite3_bind_int(statement, 3, Int32(queryVector.count))
            while sqlite3_step(statement) == SQLITE_ROW {
                let embedding = try decodeGraphEmbedding(statement)
                guard ownerTypes.isEmpty || ownerTypes.contains(embedding.ownerType), embedding.vectorNorm > 0 else { continue }
                let dotProduct = zip(queryVector, embedding.vector).reduce(0.0) { partial, pair in
                    partial + pair.0 * pair.1
                }
                let score = dotProduct / (queryNorm * embedding.vectorNorm)
                results.append(GraphEmbeddingSearchResult(embedding: embedding, score: score))
            }
        }
        return Array(results.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.embedding.id < rhs.embedding.id }
            return lhs.score > rhs.score
        }.prefix(limit))
    }

    public func upsert(costBudget budget: GraphCostBudget) throws {
        let sql = """
        INSERT OR REPLACE INTO graph_cost_budgets
        (id, scope_type, scope_id, period, token_limit, cost_limit_microunits, used_prompt_tokens, used_completion_tokens, used_cost_microunits, reset_at, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(budget.id, at: 1, in: statement)
            try bind(budget.scopeType.rawValue, at: 2, in: statement)
            try bind(budget.scopeID, at: 3, in: statement)
            try bind(budget.period.rawValue, at: 4, in: statement)
            bindIntOrNull(budget.tokenLimit, at: 5, in: statement)
            bindIntOrNull(budget.costLimitMicrounits, at: 6, in: statement)
            sqlite3_bind_int(statement, 7, Int32(budget.usedPromptTokens))
            sqlite3_bind_int(statement, 8, Int32(budget.usedCompletionTokens))
            sqlite3_bind_int(statement, 9, Int32(budget.usedCostMicrounits))
            try bind(budget.resetAt.map(iso), at: 10, in: statement)
            try bind(jsonString(budget.metadata), at: 11, in: statement)
            try stepDone(statement)
        }
    }

    public func costBudget(scopeType: GraphCostBudgetScopeType, scopeID: String, period: GraphCostBudgetPeriod) throws -> GraphCostBudget? {
        let sql = """
        SELECT id, scope_type, scope_id, period, token_limit, cost_limit_microunits, used_prompt_tokens, used_completion_tokens, used_cost_microunits, reset_at, metadata_json
        FROM graph_cost_budgets
        WHERE scope_type = ? AND scope_id = ? AND period = ?
        LIMIT 1;
        """
        return try withStatement(sql) { statement in
            try bind(scopeType.rawValue, at: 1, in: statement)
            try bind(scopeID, at: 2, in: statement)
            try bind(period.rawValue, at: 3, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeGraphCostBudget(statement)
        }
    }

    public func checkCostBudget(scopeType: GraphCostBudgetScopeType, scopeID: String, period: GraphCostBudgetPeriod, estimatedTokens: Int, estimatedCostMicrounits: Int) throws -> GraphCostBudgetDecision {
        guard let budget = try costBudget(scopeType: scopeType, scopeID: scopeID, period: period) else {
            return .allowed
        }
        let usedTokens = budget.usedPromptTokens + budget.usedCompletionTokens
        if let tokenLimit = budget.tokenLimit, usedTokens + estimatedTokens > tokenLimit {
            return .blocked(reason: "token_limit_exceeded")
        }
        if let costLimit = budget.costLimitMicrounits, budget.usedCostMicrounits + estimatedCostMicrounits > costLimit {
            return .blocked(reason: "cost_limit_exceeded")
        }
        return .allowed
    }

    public func recordCostUsage(scopeType: GraphCostBudgetScopeType, scopeID: String, period: GraphCostBudgetPeriod, promptTokens: Int, completionTokens: Int, costMicrounits: Int) throws {
        let sql = """
        UPDATE graph_cost_budgets
        SET used_prompt_tokens = used_prompt_tokens + ?,
            used_completion_tokens = used_completion_tokens + ?,
            used_cost_microunits = used_cost_microunits + ?
        WHERE scope_type = ? AND scope_id = ? AND period = ?;
        """
        try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(promptTokens))
            sqlite3_bind_int(statement, 2, Int32(completionTokens))
            sqlite3_bind_int(statement, 3, Int32(costMicrounits))
            try bind(scopeType.rawValue, at: 4, in: statement)
            try bind(scopeID, at: 5, in: statement)
            try bind(period.rawValue, at: 6, in: statement)
            try stepDone(statement)
        }
    }

    public func enqueue(job: GraphJob) throws {
        let sql = """
        INSERT OR REPLACE INTO graph_jobs
        (id, group_id, type, status, priority, payload_json, attempt_count, max_attempts, next_run_at, lease_owner, lease_expires_at, created_at, updated_at, started_at, finished_at, error_code, error_message, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(job.id, at: 1, in: statement)
            try bind(job.groupID, at: 2, in: statement)
            try bind(job.type.rawValue, at: 3, in: statement)
            try bind(job.status.rawValue, at: 4, in: statement)
            sqlite3_bind_int(statement, 5, Int32(job.priority))
            try bind(jsonString(job.payload), at: 6, in: statement)
            sqlite3_bind_int(statement, 7, Int32(job.attemptCount))
            sqlite3_bind_int(statement, 8, Int32(job.maxAttempts))
            try bind(iso(job.nextRunAt), at: 9, in: statement)
            try bind(job.leaseOwner, at: 10, in: statement)
            try bind(job.leaseExpiresAt.map(iso), at: 11, in: statement)
            try bind(iso(job.createdAt), at: 12, in: statement)
            try bind(iso(job.updatedAt), at: 13, in: statement)
            try bind(job.startedAt.map(iso), at: 14, in: statement)
            try bind(job.finishedAt.map(iso), at: 15, in: statement)
            try bind(job.errorCode, at: 16, in: statement)
            try bind(job.errorMessage, at: 17, in: statement)
            try bind(jsonString(job.metadata), at: 18, in: statement)
            try stepDone(statement)
        }
    }

    public func graphJob(id: String) throws -> GraphJob? {
        let sql = """
        SELECT id, group_id, type, status, priority, payload_json, attempt_count, max_attempts, next_run_at, lease_owner, lease_expires_at, created_at, updated_at, started_at, finished_at, error_code, error_message, metadata_json
        FROM graph_jobs WHERE id = ? LIMIT 1;
        """
        return try withStatement(sql) { statement in
            try bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeGraphJob(statement)
        }
    }

    public func leaseNextGraphJob(workerID: String, now: Date, leaseDuration: TimeInterval) throws -> GraphJob? {
        let select = """
        SELECT id FROM graph_jobs
        WHERE status = ? AND next_run_at <= ?
        ORDER BY priority DESC, created_at ASC
        LIMIT 1;
        """
        let jobID = try withStatement(select) { statement in
            try bind(GraphJobStatus.queued.rawValue, at: 1, in: statement)
            try bind(iso(now), at: 2, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil as String? }
            return text(statement, 0)
        }
        guard let jobID else { return nil }
        let leaseExpiresAt = now.addingTimeInterval(leaseDuration)
        let update = """
        UPDATE graph_jobs
        SET status = ?, lease_owner = ?, lease_expires_at = ?, started_at = COALESCE(started_at, ?), updated_at = ?
        WHERE id = ? AND status = ?;
        """
        try withStatement(update) { statement in
            try bind(GraphJobStatus.running.rawValue, at: 1, in: statement)
            try bind(workerID, at: 2, in: statement)
            try bind(iso(leaseExpiresAt), at: 3, in: statement)
            try bind(iso(now), at: 4, in: statement)
            try bind(iso(now), at: 5, in: statement)
            try bind(jobID, at: 6, in: statement)
            try bind(GraphJobStatus.queued.rawValue, at: 7, in: statement)
            try stepDone(statement)
        }
        return try graphJob(id: jobID)
    }

    public func completeGraphJob(id: String, now: Date) throws {
        let sql = """
        UPDATE graph_jobs
        SET status = ?, finished_at = ?, updated_at = ?, lease_owner = NULL, lease_expires_at = NULL
        WHERE id = ?;
        """
        try withStatement(sql) { statement in
            try bind(GraphJobStatus.succeeded.rawValue, at: 1, in: statement)
            try bind(iso(now), at: 2, in: statement)
            try bind(iso(now), at: 3, in: statement)
            try bind(id, at: 4, in: statement)
            try stepDone(statement)
        }
    }

    public func pauseGraphJob(id: String) throws {
        try updateGraphJobStatus(id: id, status: .paused, now: Date())
    }

    public func resumeGraphJob(id: String, now: Date) throws {
        let sql = """
        UPDATE graph_jobs
        SET status = ?, next_run_at = ?, updated_at = ?, lease_owner = NULL, lease_expires_at = NULL
        WHERE id = ? AND status = ?;
        """
        try withStatement(sql) { statement in
            try bind(GraphJobStatus.queued.rawValue, at: 1, in: statement)
            try bind(iso(now), at: 2, in: statement)
            try bind(iso(now), at: 3, in: statement)
            try bind(id, at: 4, in: statement)
            try bind(GraphJobStatus.paused.rawValue, at: 5, in: statement)
            try stepDone(statement)
        }
    }

    public func recoverExpiredGraphJobLeases(now: Date) throws {
        let sql = """
        UPDATE graph_jobs
        SET status = ?, lease_owner = NULL, lease_expires_at = NULL, updated_at = ?
        WHERE status = ? AND lease_expires_at IS NOT NULL AND lease_expires_at <= ?;
        """
        try withStatement(sql) { statement in
            try bind(GraphJobStatus.queued.rawValue, at: 1, in: statement)
            try bind(iso(now), at: 2, in: statement)
            try bind(GraphJobStatus.running.rawValue, at: 3, in: statement)
            try bind(iso(now), at: 4, in: statement)
            try stepDone(statement)
        }
    }

    public func failGraphJob(id: String, errorCode: String, message: String, now: Date, retryDelay: TimeInterval) throws {
        guard let job = try graphJob(id: id) else { return }
        let nextAttempt = job.attemptCount + 1
        let finalStatus: GraphJobStatus = nextAttempt >= job.maxAttempts ? .deadLetter : .queued
        let nextRunAt = now.addingTimeInterval(retryDelay)
        let sql = """
        UPDATE graph_jobs
        SET status = ?, attempt_count = ?, next_run_at = ?, lease_owner = NULL, lease_expires_at = NULL, updated_at = ?, error_code = ?, error_message = ?
        WHERE id = ?;
        """
        try withStatement(sql) { statement in
            try bind(finalStatus.rawValue, at: 1, in: statement)
            sqlite3_bind_int(statement, 2, Int32(nextAttempt))
            try bind(iso(nextRunAt), at: 3, in: statement)
            try bind(iso(now), at: 4, in: statement)
            try bind(errorCode, at: 5, in: statement)
            try bind(message, at: 6, in: statement)
            try bind(id, at: 7, in: statement)
            try stepDone(statement)
        }
    }

    private func updateGraphJobStatus(id: String, status: GraphJobStatus, now: Date) throws {
        let sql = "UPDATE graph_jobs SET status = ?, updated_at = ? WHERE id = ?;"
        try withStatement(sql) { statement in
            try bind(status.rawValue, at: 1, in: statement)
            try bind(iso(now), at: 2, in: statement)
            try bind(id, at: 3, in: statement)
            try stepDone(statement)
        }
    }

    public func pendingIndexTasks(limit: Int) throws -> [GraphIndexTask] {
        let sql = """
        SELECT id, group_id, owner_type, owner_id, task_type, status, attempt_count, next_run_at, error_message, created_at, updated_at
        FROM graph_index_tasks
        WHERE status = ?
        ORDER BY created_at ASC
        LIMIT ?;
        """
        return try withStatement(sql) { statement in
            try bind(GraphJobStatus.queued.rawValue, at: 1, in: statement)
            sqlite3_bind_int(statement, 2, Int32(limit))
            var tasks: [GraphIndexTask] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                tasks.append(try decodeGraphIndexTask(statement))
            }
            return tasks
        }
    }

    public func processPendingFTSIndexTasks(limit: Int) throws {
        let tasks = try pendingIndexTasks(limit: limit).filter { $0.taskType == .ftsUpsert }
        for task in tasks {
            switch task.ownerType {
            case .episode:
                if let episode = try graphEpisode(id: task.ownerID) { try upsertEpisodeFTS(episode) }
            case .node:
                if let node = try graphNodeV2(id: task.ownerID) { try upsertNodeFTS(node) }
            case .fact:
                if let fact = try graphFact(id: task.ownerID) { try upsertFactFTS(fact) }
            }
            try markIndexTaskSucceeded(task.id)
        }
    }

    public func searchNodeFTS(query: String, groupID: String, limit: Int) throws -> [GraphNodeV2] {
        let sql = """
        SELECT node_id FROM graph_nodes_fts
        WHERE graph_nodes_fts MATCH ? AND group_id = ?
        ORDER BY bm25(graph_nodes_fts)
        LIMIT ?;
        """
        let ids = try searchFTSIDs(sql: sql, query: query, groupID: groupID, limit: limit)
        return try ids.compactMap { try graphNodeV2(id: $0) }
    }

    public func searchFactFTS(query: String, groupID: String, limit: Int) throws -> [GraphFact] {
        let sql = """
        SELECT fact_id FROM graph_facts_fts
        WHERE graph_facts_fts MATCH ? AND group_id = ?
        ORDER BY bm25(graph_facts_fts)
        LIMIT ?;
        """
        let ids = try searchFTSIDs(sql: sql, query: query, groupID: groupID, limit: limit)
        return try ids.compactMap { try graphFact(id: $0) }
    }

    public func searchEpisodeFTS(query: String, groupID: String, limit: Int) throws -> [GraphEpisode] {
        let sql = """
        SELECT episode_id FROM graph_episodes_fts
        WHERE graph_episodes_fts MATCH ? AND group_id = ?
        ORDER BY bm25(graph_episodes_fts)
        LIMIT ?;
        """
        let ids = try searchFTSIDs(sql: sql, query: query, groupID: groupID, limit: limit)
        return try ids.compactMap { try graphEpisode(id: $0) }
    }

    public func upsert(node: GraphNode) throws {
        let sql = """
        INSERT OR REPLACE INTO graph_nodes
        (id, type, title, summary, source_path, status, created_at, valid_at, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(node.id, at: 1, in: statement)
            try bind(node.type.rawValue, at: 2, in: statement)
            try bind(node.title, at: 3, in: statement)
            try bind(node.summary, at: 4, in: statement)
            try bind(node.sourcePath, at: 5, in: statement)
            try bind(node.status.rawValue, at: 6, in: statement)
            try bind(iso(node.createdAt), at: 7, in: statement)
            try bind(node.validAt.map(iso), at: 8, in: statement)
            try bind(jsonString(node.metadata), at: 9, in: statement)
            try stepDone(statement)
        }
    }

    public func node(id: String) throws -> GraphNode? {
        let sql = "SELECT id, type, title, summary, source_path, status, created_at, valid_at, metadata_json FROM graph_nodes WHERE id = ? LIMIT 1;"
        return try withStatement(sql) { statement in
            try bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeNode(statement)
        }
    }

    public func upsert(edge: SemanticEdge) throws {
        let sql = """
        INSERT OR REPLACE INTO semantic_edges
        (id, source_node_id, target_node_id, relation, fact, confidence, created_at, valid_at, invalid_at, source_episode_id, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(edge.id, at: 1, in: statement)
            try bind(edge.sourceNodeID, at: 2, in: statement)
            try bind(edge.targetNodeID, at: 3, in: statement)
            try bind(edge.relation.rawValue, at: 4, in: statement)
            try bind(edge.fact, at: 5, in: statement)
            sqlite3_bind_double(statement, 6, edge.confidence)
            try bind(iso(edge.createdAt), at: 7, in: statement)
            try bind(edge.validAt.map(iso), at: 8, in: statement)
            try bind(edge.invalidAt.map(iso), at: 9, in: statement)
            try bind(edge.sourceEpisodeID, at: 10, in: statement)
            try bind(jsonString(edge.metadata), at: 11, in: statement)
            try stepDone(statement)
        }
    }

    public func edge(id: String) throws -> SemanticEdge? {
        let sql = """
        SELECT id, source_node_id, target_node_id, relation, fact, confidence, created_at, valid_at, invalid_at, source_episode_id, metadata_json
        FROM semantic_edges WHERE id = ? LIMIT 1;
        """
        return try withStatement(sql) { statement in
            try bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeEdge(statement)
        }
    }

    public func neighborhoodEdges(nodeID: String) throws -> [SemanticEdge] {
        let sql = """
        SELECT id, source_node_id, target_node_id, relation, fact, confidence, created_at, valid_at, invalid_at, source_episode_id, metadata_json
        FROM semantic_edges
        WHERE source_node_id = ? OR target_node_id = ?
        ORDER BY id ASC;
        """
        return try withStatement(sql) { statement in
            try bind(nodeID, at: 1, in: statement)
            try bind(nodeID, at: 2, in: statement)
            return try collectEdges(statement)
        }
    }

    public func upsert(observeLogEntry entry: ObserveLogEntry) throws {
        let sql = """
        INSERT OR REPLACE INTO observe_log_entries
        (id, timestamp, kind, source, content, normalized_summary, work_object_id, session_id, related_node_ids_json, related_edge_ids_json, importance, confidence, status, expires_at, promoted_node_id, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(entry.id, at: 1, in: statement)
            try bind(iso(entry.timestamp), at: 2, in: statement)
            try bind(entry.kind.rawValue, at: 3, in: statement)
            try bind(entry.source.rawValue, at: 4, in: statement)
            try bind(entry.content, at: 5, in: statement)
            try bind(entry.normalizedSummary, at: 6, in: statement)
            try bind(entry.workObjectID, at: 7, in: statement)
            try bind(entry.sessionID, at: 8, in: statement)
            try bind(jsonString(entry.relatedNodeIDs), at: 9, in: statement)
            try bind(jsonString(entry.relatedEdgeIDs), at: 10, in: statement)
            sqlite3_bind_double(statement, 11, entry.importance)
            sqlite3_bind_double(statement, 12, entry.confidence)
            try bind(entry.status.rawValue, at: 13, in: statement)
            try bind(iso(entry.expiresAt), at: 14, in: statement)
            try bind(entry.promotedNodeID, at: 15, in: statement)
            try bind(jsonString(entry.metadata), at: 16, in: statement)
            try stepDone(statement)
        }
    }

    public func observeLogEntry(id: String) throws -> ObserveLogEntry? {
        let sql = """
        SELECT id, timestamp, kind, source, content, normalized_summary, work_object_id, session_id, related_node_ids_json, related_edge_ids_json, importance, confidence, status, expires_at, promoted_node_id, metadata_json
        FROM observe_log_entries WHERE id = ? LIMIT 1;
        """
        return try withStatement(sql) { statement in
            try bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeObserveLogEntry(statement)
        }
    }

    public func observeLogEntries(status: ObserveLogStatus, limit: Int) throws -> [ObserveLogEntry] {
        let sql = """
        SELECT id, timestamp, kind, source, content, normalized_summary, work_object_id, session_id, related_node_ids_json, related_edge_ids_json, importance, confidence, status, expires_at, promoted_node_id, metadata_json
        FROM observe_log_entries
        WHERE status = ?
        ORDER BY timestamp DESC
        LIMIT ?;
        """
        return try withStatement(sql) { statement in
            try bind(status.rawValue, at: 1, in: statement)
            sqlite3_bind_int(statement, 2, Int32(limit))
            var entries: [ObserveLogEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                entries.append(try decodeObserveLogEntry(statement))
            }
            return entries
        }
    }

    public func allNodes(limit: Int = 1_000) throws -> [GraphNode] {
        let sql = """
        SELECT id, type, title, summary, source_path, status, created_at, valid_at, metadata_json
        FROM graph_nodes
        ORDER BY id ASC
        LIMIT ?;
        """
        return try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            var nodes: [GraphNode] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                nodes.append(try decodeNode(statement))
            }
            return nodes
        }
    }

    public func allEdges(limit: Int = 2_000) throws -> [SemanticEdge] {
        let sql = """
        SELECT id, source_node_id, target_node_id, relation, fact, confidence, created_at, valid_at, invalid_at, source_episode_id, metadata_json
        FROM semantic_edges
        ORDER BY id ASC
        LIMIT ?;
        """
        return try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            return try collectEdges(statement)
        }
    }

    public func recentObserveLogEntries(limit: Int = 500) throws -> [ObserveLogEntry] {
        let sql = """
        SELECT id, timestamp, kind, source, content, normalized_summary, work_object_id, session_id, related_node_ids_json, related_edge_ids_json, importance, confidence, status, expires_at, promoted_node_id, metadata_json
        FROM observe_log_entries
        ORDER BY timestamp DESC
        LIMIT ?;
        """
        return try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            var entries: [ObserveLogEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                entries.append(try decodeObserveLogEntry(statement))
            }
            return entries
        }
    }

    public func promotionCandidates(limit: Int = 100) throws -> [ObserveLogEntry] {
        let sql = """
        SELECT id, timestamp, kind, source, content, normalized_summary, work_object_id, session_id, related_node_ids_json, related_edge_ids_json, importance, confidence, status, expires_at, promoted_node_id, metadata_json
        FROM observe_log_entries
        WHERE status = ? AND kind IN (?, ?, ?)
        ORDER BY id ASC
        LIMIT ?;
        """
        return try withStatement(sql) { statement in
            try bind(ObserveLogStatus.active.rawValue, at: 1, in: statement)
            try bind(ObserveLogKind.candidateFact.rawValue, at: 2, in: statement)
            try bind(ObserveLogKind.decisionHint.rawValue, at: 3, in: statement)
            try bind(ObserveLogKind.userPreference.rawValue, at: 4, in: statement)
            sqlite3_bind_int(statement, 5, Int32(limit))
            var entries: [ObserveLogEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                entries.append(try decodeObserveLogEntry(statement))
            }
            return entries
        }
    }

    public func update(observeLogEntry entry: ObserveLogEntry) throws {
        try upsert(observeLogEntry: entry)
    }

    public func observeLogEntries(limit: Int) throws -> [ObserveLogEntry] {
        try recentObserveLogEntries(limit: limit)
    }

    public func upsert(chatSession session: AgentSession) throws {
        let sql = """
        INSERT INTO chat_sessions
        (id, title, created_at, updated_at, metadata_json)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            metadata_json = excluded.metadata_json;
        """
        try withStatement(sql) { statement in
            try bind(session.id, at: 1, in: statement)
            try bind(session.title, at: 2, in: statement)
            try bind(iso(session.createdAt), at: 3, in: statement)
            try bind(iso(session.updatedAt), at: 4, in: statement)
            try bind(jsonString([String: String]()), at: 5, in: statement)
            try stepDone(statement)
        }
    }

    public func chatSessions(limit: Int = 50) throws -> [AgentSession] {
        let sql = """
        SELECT id, title, created_at, updated_at, metadata_json
        FROM chat_sessions
        ORDER BY updated_at DESC
        LIMIT ?;
        """
        return try withStatement(sql) { statement in
            sqlite3_bind_int(statement, 1, Int32(limit))
            var sessions: [AgentSession] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                sessions.append(try decodeChatSession(statement, includeMessages: false))
            }
            return sessions
        }
    }

    public func chatSession(id: String) throws -> AgentSession? {
        let sql = """
        SELECT id, title, created_at, updated_at, metadata_json
        FROM chat_sessions
        WHERE id = ?
        LIMIT 1;
        """
        return try withStatement(sql) { statement in
            try bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeChatSession(statement, includeMessages: true)
        }
    }

    public func append(chatMessage message: AgentMessage, sessionID: String) throws {
        let sql = """
        INSERT OR REPLACE INTO chat_messages
        (id, session_id, role, content, created_at, citations_json, context_snapshot, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(message.id, at: 1, in: statement)
            try bind(sessionID, at: 2, in: statement)
            try bind(message.role.rawValue, at: 3, in: statement)
            try bind(message.content, at: 4, in: statement)
            try bind(iso(message.createdAt), at: 5, in: statement)
            try bind(jsonString(message.citations), at: 6, in: statement)
            try bind(message.contextSnapshot, at: 7, in: statement)
            try bind(jsonString(ChatMessageMetadata(promptInspection: message.promptInspection)), at: 8, in: statement)
            try stepDone(statement)
        }
    }

    public func chatMessages(sessionID: String) throws -> [AgentMessage] {
        let sql = """
        SELECT id, session_id, role, content, created_at, citations_json, context_snapshot, metadata_json
        FROM chat_messages
        WHERE session_id = ?
        ORDER BY created_at ASC;
        """
        return try withStatement(sql) { statement in
            try bind(sessionID, at: 1, in: statement)
            var messages: [AgentMessage] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                messages.append(try decodeChatMessage(statement))
            }
            return messages
        }
    }

    public func upsert(chatSessionSummary summary: AgentSessionSummary) throws {
        let sql = """
        INSERT OR REPLACE INTO chat_session_summaries
        (id, session_id, content, created_at, updated_at, source_message_count, last_message_id, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            try bind(summary.id, at: 1, in: statement)
            try bind(summary.sessionID, at: 2, in: statement)
            try bind(summary.content, at: 3, in: statement)
            try bind(iso(summary.createdAt), at: 4, in: statement)
            try bind(iso(summary.updatedAt), at: 5, in: statement)
            sqlite3_bind_int(statement, 6, Int32(summary.sourceMessageCount))
            try bind(summary.lastMessageID, at: 7, in: statement)
            try bind(jsonString([String: String]()), at: 8, in: statement)
            try stepDone(statement)
        }
    }

    public func latestChatSessionSummary(sessionID: String) throws -> AgentSessionSummary? {
        let sql = """
        SELECT id, session_id, content, created_at, updated_at, source_message_count, last_message_id, metadata_json
        FROM chat_session_summaries
        WHERE session_id = ?
        ORDER BY updated_at DESC
        LIMIT 1;
        """
        return try withStatement(sql) { statement in
            try bind(sessionID, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decodeChatSessionSummary(statement)
        }
    }

    public func snapshot(
        nodeLimit: Int = 1_000,
        edgeLimit: Int = 2_000,
        observeLogLimit: Int = 500
    ) throws -> GraphStoreSnapshot {
        GraphStoreSnapshot(
            nodes: try allNodes(limit: nodeLimit),
            edges: try allEdges(limit: edgeLimit),
            observeLogEntries: try recentObserveLogEntries(limit: observeLogLimit)
        )
    }

    private func scheduleFTSIndex(ownerType: GraphIndexOwnerType, ownerID: String, groupID: String) throws {
        let now = Date()
        let taskID = "fts-\(ownerType.rawValue)-\(ownerID)"
        let sql = """
        INSERT INTO graph_index_tasks
        (id, group_id, owner_type, owner_id, task_type, status, attempt_count, next_run_at, error_message, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, 0, ?, NULL, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            status = excluded.status,
            next_run_at = excluded.next_run_at,
            updated_at = excluded.updated_at,
            error_message = NULL;
        """
        try withStatement(sql) { statement in
            try bind(taskID, at: 1, in: statement)
            try bind(groupID, at: 2, in: statement)
            try bind(ownerType.rawValue, at: 3, in: statement)
            try bind(ownerID, at: 4, in: statement)
            try bind(GraphIndexTaskType.ftsUpsert.rawValue, at: 5, in: statement)
            try bind(GraphJobStatus.queued.rawValue, at: 6, in: statement)
            try bind(iso(now), at: 7, in: statement)
            try bind(iso(now), at: 8, in: statement)
            try bind(iso(now), at: 9, in: statement)
            try stepDone(statement)
        }
    }

    private func markIndexTaskSucceeded(_ id: String) throws {
        let sql = "UPDATE graph_index_tasks SET status = ?, updated_at = ? WHERE id = ?;"
        try withStatement(sql) { statement in
            try bind(GraphJobStatus.succeeded.rawValue, at: 1, in: statement)
            try bind(iso(Date()), at: 2, in: statement)
            try bind(id, at: 3, in: statement)
            try stepDone(statement)
        }
    }

    private func upsertNodeFTS(_ node: GraphNodeV2) throws {
        try deleteFTSRow(table: "graph_nodes_fts", idColumn: "node_id", id: node.id)
        let sql = "INSERT INTO graph_nodes_fts (node_id, group_id, type, title, canonical_name, summary, labels, attributes) VALUES (?, ?, ?, ?, ?, ?, ?, ?);"
        try withStatement(sql) { statement in
            try bind(node.id, at: 1, in: statement)
            try bind(node.groupID, at: 2, in: statement)
            try bind(node.type.rawValue, at: 3, in: statement)
            try bind(searchableText(node.title), at: 4, in: statement)
            try bind(searchableText(node.canonicalName), at: 5, in: statement)
            try bind(searchableText(node.summary), at: 6, in: statement)
            try bind(searchableText(node.labels.joined(separator: " ")), at: 7, in: statement)
            try bind(searchableText(node.attributes.map { "\($0.key) \($0.value)" }.joined(separator: " ")), at: 8, in: statement)
            try stepDone(statement)
        }
    }

    private func upsertFactFTS(_ fact: GraphFact) throws {
        try deleteFTSRow(table: "graph_facts_fts", idColumn: "fact_id", id: fact.id)
        let sourceName = (try graphNodeV2(id: fact.sourceNodeID))?.canonicalName ?? ""
        let targetName = (try graphNodeV2(id: fact.targetNodeID))?.canonicalName ?? ""
        let sql = "INSERT INTO graph_facts_fts (fact_id, group_id, relation, fact, source_name, target_name, attributes) VALUES (?, ?, ?, ?, ?, ?, ?);"
        try withStatement(sql) { statement in
            try bind(fact.id, at: 1, in: statement)
            try bind(fact.groupID, at: 2, in: statement)
            try bind(fact.relation.rawValue, at: 3, in: statement)
            try bind(searchableText(fact.fact), at: 4, in: statement)
            try bind(searchableText(sourceName), at: 5, in: statement)
            try bind(searchableText(targetName), at: 6, in: statement)
            try bind(searchableText(fact.attributes.map { "\($0.key) \($0.value)" }.joined(separator: " ")), at: 7, in: statement)
            try stepDone(statement)
        }
    }

    private func upsertEpisodeFTS(_ episode: GraphEpisode) throws {
        try deleteFTSRow(table: "graph_episodes_fts", idColumn: "episode_id", id: episode.id)
        let sql = "INSERT INTO graph_episodes_fts (episode_id, group_id, source_type, content, source_description) VALUES (?, ?, ?, ?, ?);"
        try withStatement(sql) { statement in
            try bind(episode.id, at: 1, in: statement)
            try bind(episode.groupID, at: 2, in: statement)
            try bind(episode.sourceType.rawValue, at: 3, in: statement)
            try bind(searchableText(episode.content), at: 4, in: statement)
            try bind(searchableText(episode.sourceDescription), at: 5, in: statement)
            try stepDone(statement)
        }
    }

    private func deleteFTSRow(table: String, idColumn: String, id: String) throws {
        try withStatement("DELETE FROM \(table) WHERE \(idColumn) = ?;") { statement in
            try bind(id, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    private func searchFTSIDs(sql: String, query: String, groupID: String, limit: Int) throws -> [String] {
        try withStatement(sql) { statement in
            try bind(searchableQuery(query), at: 1, in: statement)
            try bind(groupID, at: 2, in: statement)
            sqlite3_bind_int(statement, 3, Int32(limit))
            var ids: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let id = text(statement, 0) { ids.append(id) }
            }
            return ids
        }
    }

    private func searchableQuery(_ text: String) -> String {
        if text.contains(where: { isCJK($0) }) {
            return cjkNGrams(text).joined(separator: " OR ")
        }
        return text
    }

    private func searchableText(_ text: String) -> String {
        let grams = cjkNGrams(text)
        guard !grams.isEmpty else { return text }
        return ([text] + grams).joined(separator: " ")
    }

    private func cjkNGrams(_ text: String) -> [String] {
        let chars = text.filter(isCJK)
        guard !chars.isEmpty else { return [] }
        var grams = chars.map(String.init)
        if chars.count >= 2 {
            for index in 0..<(chars.count - 1) {
                let start = chars.index(chars.startIndex, offsetBy: index)
                let end = chars.index(after: start)
                grams.append(String(chars[start...end]))
            }
        }
        return Array(Set(grams)).sorted()
    }

    private func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private func execute(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteGraphStoreError.executeFailed(Self.message(db))
        }
    }

    private func queryStrings(sql: String) throws -> [String] {
        try withStatement(sql) { statement in
            var results: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(text(statement, 0) ?? "")
            }
            return results
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteGraphStoreError.prepareFailed(Self.message(db))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteGraphStoreError.stepFailed(Self.message(db))
        }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer?) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw SQLiteGraphStoreError.bindFailed(Self.message(db))
        }
    }

    private func bindIntOrNull(_ value: Int?, at index: Int32, in statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ value: Data, at index: Int32, in statement: OpaquePointer?) throws {
        let result = value.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
        }
        guard result == SQLITE_OK else {
            throw SQLiteGraphStoreError.bindFailed(Self.message(db))
        }
    }

    private func vectorBlob(_ vector: [Double]) throws -> Data {
        var data = Data()
        data.reserveCapacity(vector.count * MemoryLayout<Double>.size)
        for value in vector {
            var littleEndian = value.bitPattern.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    private func vector(_ statement: OpaquePointer?, _ column: Int32, dimensions: Int) throws -> [Double] {
        guard let bytes = sqlite3_column_blob(statement, column) else {
            throw SQLiteGraphStoreError.decodeFailed("graph_embeddings vector_blob")
        }
        let byteCount = Int(sqlite3_column_bytes(statement, column))
        guard byteCount == dimensions * MemoryLayout<Double>.size else {
            throw SQLiteGraphStoreError.decodeFailed("graph_embeddings vector_blob dimensions")
        }
        let data = Data(bytes: bytes, count: byteCount)
        return stride(from: 0, to: byteCount, by: MemoryLayout<Double>.size).map { offset in
            let bits = data.withUnsafeBytes { rawBuffer in
                rawBuffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            }
            return Double(bitPattern: UInt64(littleEndian: bits))
        }
    }

    private func optionalInt(_ statement: OpaquePointer?, _ column: Int32) -> Int? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, column))
    }

    private func decodeGraphEpisode(_ statement: OpaquePointer?) throws -> GraphEpisode {
        guard
            let id = text(statement, 0),
            let groupID = text(statement, 1),
            let sourceTypeRaw = text(statement, 2),
            let sourceType = GraphEpisodeSourceType(rawValue: sourceTypeRaw),
            let name = text(statement, 4),
            let content = text(statement, 5),
            let sourceDescription = text(statement, 6),
            let occurredRaw = text(statement, 7),
            let occurredAt = date(occurredRaw),
            let ingestedRaw = text(statement, 8),
            let ingestedAt = date(ingestedRaw),
            let statusRaw = text(statement, 11),
            let status = GraphTemporalStatus(rawValue: statusRaw),
            let metadataRaw = text(statement, 12)
        else {
            throw SQLiteGraphStoreError.decodeFailed("graph_episodes row")
        }
        return GraphEpisode(
            id: id,
            groupID: groupID,
            sourceType: sourceType,
            sourceID: text(statement, 3),
            name: name,
            content: content,
            sourceDescription: sourceDescription,
            occurredAt: occurredAt,
            ingestedAt: ingestedAt,
            sessionID: text(statement, 9),
            workObjectID: text(statement, 10),
            status: status,
            metadata: try json([String: String].self, from: metadataRaw)
        )
    }

    private func decodeGraphNodeV2(_ statement: OpaquePointer?) throws -> GraphNodeV2 {
        guard
            let id = text(statement, 0),
            let groupID = text(statement, 1),
            let typeRaw = text(statement, 3),
            let type = NodeType(rawValue: typeRaw),
            let canonicalName = text(statement, 4),
            let title = text(statement, 5),
            let summary = text(statement, 6),
            let labelsRaw = text(statement, 7),
            let attributesRaw = text(statement, 8),
            let statusRaw = text(statement, 9),
            let status = GraphTemporalStatus(rawValue: statusRaw),
            let createdRaw = text(statement, 11),
            let createdAt = date(createdRaw),
            let updatedRaw = text(statement, 12),
            let updatedAt = date(updatedRaw),
            let metadataRaw = text(statement, 16)
        else {
            throw SQLiteGraphStoreError.decodeFailed("graph_nodes_v2 row")
        }
        return GraphNodeV2(
            id: id,
            groupID: groupID,
            stableKey: text(statement, 2),
            type: type,
            canonicalName: canonicalName,
            title: title,
            summary: summary,
            labels: try json([String].self, from: labelsRaw),
            attributes: try json([String: String].self, from: attributesRaw),
            status: status,
            confidence: sqlite3_column_double(statement, 10),
            createdAt: createdAt,
            updatedAt: updatedAt,
            validFrom: text(statement, 13).flatMap(date),
            validUntil: text(statement, 14).flatMap(date),
            supersededByNodeID: text(statement, 15),
            metadata: try json([String: String].self, from: metadataRaw)
        )
    }

    private func decodeGraphFact(_ statement: OpaquePointer?) throws -> GraphFact {
        guard
            let id = text(statement, 0),
            let groupID = text(statement, 1),
            let sourceNodeID = text(statement, 2),
            let targetNodeID = text(statement, 3),
            let relationRaw = text(statement, 4),
            let relation = RelationType(rawValue: relationRaw),
            let fact = text(statement, 5),
            let statusRaw = text(statement, 7),
            let status = GraphTemporalStatus(rawValue: statusRaw),
            let createdRaw = text(statement, 8),
            let createdAt = date(createdRaw),
            let updatedRaw = text(statement, 9),
            let updatedAt = date(updatedRaw),
            let attributesRaw = text(statement, 15),
            let metadataRaw = text(statement, 16)
        else {
            throw SQLiteGraphStoreError.decodeFailed("graph_facts row")
        }
        return GraphFact(
            id: id,
            groupID: groupID,
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            relation: relation,
            fact: fact,
            confidence: sqlite3_column_double(statement, 6),
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            validAt: text(statement, 10).flatMap(date),
            invalidAt: text(statement, 11).flatMap(date),
            expiredAt: text(statement, 12).flatMap(date),
            referenceTime: text(statement, 13).flatMap(date),
            invalidatedByFactID: text(statement, 14),
            attributes: try json([String: String].self, from: attributesRaw),
            metadata: try json([String: String].self, from: metadataRaw)
        )
    }

    private func decodeGraphEmbedding(_ statement: OpaquePointer?) throws -> GraphEmbedding {
        guard
            let id = text(statement, 0),
            let groupID = text(statement, 1),
            let ownerTypeRaw = text(statement, 2),
            let ownerType = GraphIndexOwnerType(rawValue: ownerTypeRaw),
            let ownerID = text(statement, 3),
            let embeddingModel = text(statement, 4),
            let contentHash = text(statement, 8),
            let createdRaw = text(statement, 9),
            let createdAt = date(createdRaw)
        else {
            throw SQLiteGraphStoreError.decodeFailed("graph_embeddings row")
        }
        let dimensions = Int(sqlite3_column_int(statement, 5))
        return GraphEmbedding(
            id: id,
            groupID: groupID,
            ownerType: ownerType,
            ownerID: ownerID,
            embeddingModel: embeddingModel,
            vector: try vector(statement, 6, dimensions: dimensions),
            contentHash: contentHash,
            createdAt: createdAt
        )
    }

    private func decodeGraphCostBudget(_ statement: OpaquePointer?) throws -> GraphCostBudget {
        guard
            let id = text(statement, 0),
            let scopeTypeRaw = text(statement, 1),
            let scopeType = GraphCostBudgetScopeType(rawValue: scopeTypeRaw),
            let scopeID = text(statement, 2),
            let periodRaw = text(statement, 3),
            let period = GraphCostBudgetPeriod(rawValue: periodRaw),
            let metadataRaw = text(statement, 10)
        else {
            throw SQLiteGraphStoreError.decodeFailed("graph_cost_budgets row")
        }
        return GraphCostBudget(
            id: id,
            scopeType: scopeType,
            scopeID: scopeID,
            period: period,
            tokenLimit: optionalInt(statement, 4),
            costLimitMicrounits: optionalInt(statement, 5),
            usedPromptTokens: Int(sqlite3_column_int(statement, 6)),
            usedCompletionTokens: Int(sqlite3_column_int(statement, 7)),
            usedCostMicrounits: Int(sqlite3_column_int(statement, 8)),
            resetAt: text(statement, 9).flatMap(date),
            metadata: try json([String: String].self, from: metadataRaw)
        )
    }

    private func decodeGraphJob(_ statement: OpaquePointer?) throws -> GraphJob {
        guard
            let id = text(statement, 0),
            let groupID = text(statement, 1),
            let typeRaw = text(statement, 2),
            let type = GraphJobType(rawValue: typeRaw),
            let statusRaw = text(statement, 3),
            let status = GraphJobStatus(rawValue: statusRaw),
            let payloadRaw = text(statement, 5),
            let nextRunRaw = text(statement, 8),
            let nextRunAt = date(nextRunRaw),
            let createdRaw = text(statement, 11),
            let createdAt = date(createdRaw),
            let updatedRaw = text(statement, 12),
            let updatedAt = date(updatedRaw),
            let metadataRaw = text(statement, 17)
        else {
            throw SQLiteGraphStoreError.decodeFailed("graph_jobs row")
        }
        return GraphJob(
            id: id,
            groupID: groupID,
            type: type,
            status: status,
            priority: Int(sqlite3_column_int(statement, 4)),
            payload: try json([String: String].self, from: payloadRaw),
            attemptCount: Int(sqlite3_column_int(statement, 6)),
            maxAttempts: Int(sqlite3_column_int(statement, 7)),
            nextRunAt: nextRunAt,
            leaseOwner: text(statement, 9),
            leaseExpiresAt: text(statement, 10).flatMap(date),
            createdAt: createdAt,
            updatedAt: updatedAt,
            startedAt: text(statement, 13).flatMap(date),
            finishedAt: text(statement, 14).flatMap(date),
            errorCode: text(statement, 15),
            errorMessage: text(statement, 16),
            metadata: try json([String: String].self, from: metadataRaw)
        )
    }

    private func decodeGraphIndexTask(_ statement: OpaquePointer?) throws -> GraphIndexTask {
        guard
            let id = text(statement, 0),
            let groupID = text(statement, 1),
            let ownerTypeRaw = text(statement, 2),
            let ownerType = GraphIndexOwnerType(rawValue: ownerTypeRaw),
            let ownerID = text(statement, 3),
            let taskTypeRaw = text(statement, 4),
            let taskType = GraphIndexTaskType(rawValue: taskTypeRaw),
            let statusRaw = text(statement, 5),
            let status = GraphJobStatus(rawValue: statusRaw),
            let nextRunRaw = text(statement, 7),
            let nextRunAt = date(nextRunRaw),
            let createdRaw = text(statement, 9),
            let createdAt = date(createdRaw),
            let updatedRaw = text(statement, 10),
            let updatedAt = date(updatedRaw)
        else {
            throw SQLiteGraphStoreError.decodeFailed("graph_index_tasks row")
        }
        return GraphIndexTask(
            id: id,
            groupID: groupID,
            ownerType: ownerType,
            ownerID: ownerID,
            taskType: taskType,
            status: status,
            attemptCount: Int(sqlite3_column_int(statement, 6)),
            nextRunAt: nextRunAt,
            errorMessage: text(statement, 8),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func decodeNode(_ statement: OpaquePointer?) throws -> GraphNode {
        guard
            let id = text(statement, 0),
            let typeRaw = text(statement, 1),
            let type = NodeType(rawValue: typeRaw),
            let title = text(statement, 2),
            let summary = text(statement, 3),
            let statusRaw = text(statement, 5),
            let status = NodeStatus(rawValue: statusRaw),
            let createdRaw = text(statement, 6),
            let createdAt = date(createdRaw),
            let metadataRaw = text(statement, 8)
        else {
            throw SQLiteGraphStoreError.decodeFailed("graph_nodes row")
        }
        return GraphNode(
            id: id,
            type: type,
            title: title,
            summary: summary,
            sourcePath: text(statement, 4),
            status: status,
            createdAt: createdAt,
            validAt: text(statement, 7).flatMap(date),
            metadata: try json([String: String].self, from: metadataRaw)
        )
    }

    private func decodeEdge(_ statement: OpaquePointer?) throws -> SemanticEdge {
        guard
            let id = text(statement, 0),
            let source = text(statement, 1),
            let target = text(statement, 2),
            let relationRaw = text(statement, 3),
            let relation = RelationType(rawValue: relationRaw),
            let fact = text(statement, 4),
            let createdRaw = text(statement, 6),
            let createdAt = date(createdRaw),
            let metadataRaw = text(statement, 10)
        else {
            throw SQLiteGraphStoreError.decodeFailed("semantic_edges row")
        }
        return SemanticEdge(
            id: id,
            sourceNodeID: source,
            targetNodeID: target,
            relation: relation,
            fact: fact,
            confidence: sqlite3_column_double(statement, 5),
            createdAt: createdAt,
            validAt: text(statement, 7).flatMap(date),
            invalidAt: text(statement, 8).flatMap(date),
            sourceEpisodeID: text(statement, 9),
            metadata: try json([String: String].self, from: metadataRaw)
        )
    }

    private func collectEdges(_ statement: OpaquePointer?) throws -> [SemanticEdge] {
        var edges: [SemanticEdge] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            edges.append(try decodeEdge(statement))
        }
        return edges
    }

    private func decodeChatSession(_ statement: OpaquePointer?, includeMessages: Bool) throws -> AgentSession {
        guard
            let id = text(statement, 0),
            let title = text(statement, 1),
            let createdRaw = text(statement, 2),
            let createdAt = date(createdRaw),
            let updatedRaw = text(statement, 3),
            let updatedAt = date(updatedRaw)
        else {
            throw SQLiteGraphStoreError.decodeFailed("chat_sessions row")
        }
        let messages = includeMessages ? try chatMessages(sessionID: id) : []
        return AgentSession(id: id, title: title, messages: messages, createdAt: createdAt, updatedAt: updatedAt)
    }

    private func decodeChatMessage(_ statement: OpaquePointer?) throws -> AgentMessage {
        guard
            let id = text(statement, 0),
            let roleRaw = text(statement, 2),
            let role = AgentRole(rawValue: roleRaw),
            let content = text(statement, 3),
            let createdRaw = text(statement, 4),
            let createdAt = date(createdRaw),
            let citationsRaw = text(statement, 5),
            let metadataRaw = text(statement, 7)
        else {
            throw SQLiteGraphStoreError.decodeFailed("chat_messages row")
        }
        let metadata = try json(ChatMessageMetadata.self, from: metadataRaw)
        return AgentMessage(
            id: id,
            role: role,
            content: content,
            createdAt: createdAt,
            citations: try json([String].self, from: citationsRaw),
            contextSnapshot: text(statement, 6),
            promptInspection: metadata.promptInspection
        )
    }

    private func decodeChatSessionSummary(_ statement: OpaquePointer?) throws -> AgentSessionSummary {
        guard
            let id = text(statement, 0),
            let sessionID = text(statement, 1),
            let content = text(statement, 2),
            let createdRaw = text(statement, 3),
            let createdAt = date(createdRaw),
            let updatedRaw = text(statement, 4),
            let updatedAt = date(updatedRaw)
        else {
            throw SQLiteGraphStoreError.decodeFailed("chat_session_summaries row")
        }
        return AgentSessionSummary(
            id: id,
            sessionID: sessionID,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sourceMessageCount: Int(sqlite3_column_int(statement, 5)),
            lastMessageID: text(statement, 6)
        )
    }

    private func decodeObserveLogEntry(_ statement: OpaquePointer?) throws -> ObserveLogEntry {
        guard
            let id = text(statement, 0),
            let timestampRaw = text(statement, 1),
            let timestamp = date(timestampRaw),
            let kindRaw = text(statement, 2),
            let kind = ObserveLogKind(rawValue: kindRaw),
            let sourceRaw = text(statement, 3),
            let source = ObserveLogSource(rawValue: sourceRaw),
            let content = text(statement, 4),
            let normalized = text(statement, 5),
            let nodeIDsRaw = text(statement, 8),
            let edgeIDsRaw = text(statement, 9),
            let statusRaw = text(statement, 12),
            let status = ObserveLogStatus(rawValue: statusRaw),
            let expiresRaw = text(statement, 13),
            let expiresAt = date(expiresRaw),
            let metadataRaw = text(statement, 15)
        else {
            throw SQLiteGraphStoreError.decodeFailed("observe_log_entries row")
        }
        return ObserveLogEntry(
            id: id,
            timestamp: timestamp,
            kind: kind,
            source: source,
            content: content,
            normalizedSummary: normalized,
            workObjectID: text(statement, 6),
            sessionID: text(statement, 7),
            relatedNodeIDs: try json([String].self, from: nodeIDsRaw),
            relatedEdgeIDs: try json([String].self, from: edgeIDsRaw),
            importance: sqlite3_column_double(statement, 10),
            confidence: sqlite3_column_double(statement, 11),
            status: status,
            expiresAt: expiresAt,
            promotedNodeID: text(statement, 14),
            metadata: try json([String: String].self, from: metadataRaw)
        )
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        String(data: try encoder.encode(value), encoding: .utf8) ?? "null"
    }

    private func json<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw SQLiteGraphStoreError.decodeFailed("invalid utf8 json")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, column)
        else { return nil }
        return String(cString: pointer)
    }

    private func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func message(_ db: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: message)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

