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
        try execute("""
        INSERT OR IGNORE INTO schema_migrations(version, applied_at)
        VALUES (1, \(quote(iso(Date()))));
        """)
    }

    public func tableNames() throws -> Set<String> {
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table';"
        return Set(try queryStrings(sql: sql))
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
        INSERT OR REPLACE INTO chat_sessions
        (id, title, created_at, updated_at, metadata_json)
        VALUES (?, ?, ?, ?, ?);
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
            try bind(jsonString([String: String]()), at: 8, in: statement)
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
            let citationsRaw = text(statement, 5)
        else {
            throw SQLiteGraphStoreError.decodeFailed("chat_messages row")
        }
        return AgentMessage(
            id: id,
            role: role,
            content: content,
            createdAt: createdAt,
            citations: try json([String].self, from: citationsRaw),
            contextSnapshot: text(statement, 6)
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

