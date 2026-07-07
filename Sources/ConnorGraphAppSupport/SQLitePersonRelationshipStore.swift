import Foundation
import SQLite3
import ConnorGraphCore

public protocol PersonRelationshipStore: Sendable {
    func loadRelationships(includeInactive: Bool) async throws -> [PersonRelationship]
    func relationships(for personID: ContactID, includeInactive: Bool) async throws -> [PersonRelationship]
    func currentUserRelationships(includeInactive: Bool) async throws -> [PersonRelationship]
    func relationship(id: String) async throws -> PersonRelationship?
    func upsert(_ relationship: PersonRelationship) async throws -> PersonRelationship
    func markDeleted(id: String, now: Date) async throws
    func reassignPersonIDForMerge(sourceID: ContactID, targetID: ContactID, now: Date) async throws
}

public enum SQLitePersonRelationshipStoreError: Error, LocalizedError, Sendable, Equatable {
    case openFailed(String)
    case sqlite(String)
    case relationshipNotFound(String)
    case invalidEndpoint(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): message
        case .sqlite(let message): message
        case .relationshipNotFound(let id): "Person relationship not found: \(id)"
        case .invalidEndpoint(let message): message
        }
    }
}

public final class SQLitePersonRelationshipStore: PersonRelationshipStore, @unchecked Sendable {
    private let db: OpaquePointer
    private let queue = DispatchQueue(label: "ConnorGraphAppSupport.SQLitePersonRelationshipStore")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let openedDB = db else {
            throw SQLitePersonRelationshipStoreError.openFailed("Cannot open \(databaseURL.path)")
        }
        self.db = openedDB

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .secondsSince1970

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .secondsSince1970

        try Self.configurePragmas(db: openedDB)
        try Self.createTables(db: openedDB)
    }

    deinit {
        queue.sync {
            _ = sqlite3_close(db)
        }
    }

    public func loadRelationships(includeInactive: Bool = false) async throws -> [PersonRelationship] {
        try queue.sync {
            try loadRelationshipsInternal(includeInactive: includeInactive)
        }
    }

    public func relationships(for personID: ContactID, includeInactive: Bool = false) async throws -> [PersonRelationship] {
        try queue.sync {
            let escaped = escape(personID.rawValue)
            let statusClause = includeInactive ? "" : " AND status IN ('active', 'pending')"
            return try queryJSONRelationships(sql: """
                SELECT raw_json FROM person_relationships
                WHERE (source_person_id = '\(escaped)' OR target_person_id = '\(escaped)')\(statusClause)
                ORDER BY updated_at DESC, id ASC;
                """)
        }
    }

    public func currentUserRelationships(includeInactive: Bool = false) async throws -> [PersonRelationship] {
        try queue.sync {
            let anchor = PersonRelationshipEndpoint.currentUserProtectedIdentityAnchor
            let stableKey = PersonRelationshipEndpoint.currentUserMemoryStableKey
            let entityID = PersonRelationshipEndpoint.currentUserMemoryEntityID
            let statusClause = includeInactive ? "" : " AND status IN ('active', 'pending')"
            return try queryJSONRelationships(sql: """
                SELECT raw_json FROM person_relationships
                WHERE (
                    source_kind = 'currentUser' OR target_kind = 'currentUser'
                    OR source_protected_identity_anchor = '\(escape(anchor))'
                    OR target_protected_identity_anchor = '\(escape(anchor))'
                    OR source_memory_stable_key = '\(escape(stableKey))'
                    OR target_memory_stable_key = '\(escape(stableKey))'
                    OR source_memory_entity_id = '\(escape(entityID))'
                    OR target_memory_entity_id = '\(escape(entityID))'
                )\(statusClause)
                ORDER BY updated_at DESC, id ASC;
                """)
        }
    }

    public func relationship(id: String) async throws -> PersonRelationship? {
        try queue.sync {
            let sql = "SELECT raw_json FROM person_relationships WHERE id = '\(escape(id))' LIMIT 1;"
            return try queryJSONRelationships(sql: sql).first
        }
    }

    public func upsert(_ relationship: PersonRelationship) async throws -> PersonRelationship {
        try queue.sync {
            try upsertInternal(relationship)
            return relationship
        }
    }

    public func markDeleted(id: String, now: Date = Date()) async throws {
        try queue.sync {
            guard var relationship = try relationshipInternal(id: id) else {
                throw SQLitePersonRelationshipStoreError.relationshipNotFound(id)
            }
            relationship.status = .deleted
            relationship.updatedAt = now
            try upsertInternal(relationship)
        }
    }

    public func reassignPersonIDForMerge(sourceID: ContactID, targetID: ContactID, now: Date = Date()) async throws {
        try queue.sync {
            let relationships = try loadRelationshipsInternal(includeInactive: true)
            var changed: [PersonRelationship] = []
            for relationship in relationships {
                var relationship = relationship
                var didChange = false

                if relationship.source.kind == .personProfile, relationship.source.personID == sourceID {
                    relationship.source.personID = targetID
                    didChange = true
                }
                if relationship.target.kind == .personProfile, relationship.target.personID == sourceID {
                    relationship.target.personID = targetID
                    didChange = true
                }

                if didChange {
                    if relationship.source.kind == .personProfile,
                       relationship.target.kind == .personProfile,
                       relationship.source.personID == relationship.target.personID {
                        relationship.status = .archived
                    }
                    relationship.updatedAt = now
                    changed.append(relationship)
                }
            }

            for relationship in changed {
                try upsertInternal(relationship)
            }
        }
    }

    private static func configurePragmas(db: OpaquePointer) throws {
        try execute("PRAGMA journal_mode = WAL;", db: db)
        try execute("PRAGMA synchronous = NORMAL;", db: db)
        try execute("PRAGMA busy_timeout = 5000;", db: db)
        try execute("PRAGMA temp_store = MEMORY;", db: db)
    }

    private static func createTables(db: OpaquePointer) throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS person_relationships (
                id TEXT PRIMARY KEY,
                source_kind TEXT NOT NULL,
                source_person_id TEXT,
                source_protected_identity_anchor TEXT,
                source_memory_entity_id TEXT,
                source_memory_stable_key TEXT,
                target_kind TEXT NOT NULL,
                target_person_id TEXT,
                target_protected_identity_anchor TEXT,
                target_memory_entity_id TEXT,
                target_memory_stable_key TEXT,
                relationship_kind TEXT NOT NULL,
                custom_kind_label TEXT,
                note TEXT,
                evidence_text TEXT,
                confidence REAL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                raw_json TEXT NOT NULL
            );
        """, db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_relationships_source_person ON person_relationships(source_person_id);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_relationships_target_person ON person_relationships(target_person_id);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_relationships_source_kind ON person_relationships(source_kind);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_relationships_target_kind ON person_relationships(target_kind);", db: db)
        try execute("CREATE INDEX IF NOT EXISTS idx_person_relationships_status ON person_relationships(status);", db: db)
    }

    private static func execute(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw SQLitePersonRelationshipStoreError.sqlite(message)
        }
    }

    private func loadRelationshipsInternal(includeInactive: Bool) throws -> [PersonRelationship] {
        let sql: String
        if includeInactive {
            sql = "SELECT raw_json FROM person_relationships ORDER BY updated_at DESC, id ASC;"
        } else {
            sql = "SELECT raw_json FROM person_relationships WHERE status IN ('active', 'pending') ORDER BY updated_at DESC, id ASC;"
        }
        return try queryJSONRelationships(sql: sql)
    }

    private func relationshipInternal(id: String) throws -> PersonRelationship? {
        let sql = "SELECT raw_json FROM person_relationships WHERE id = '\(escape(id))' LIMIT 1;"
        return try queryJSONRelationships(sql: sql).first
    }

    private func upsertInternal(_ relationship: PersonRelationship) throws {
        try validate(relationship.source, label: "source")
        try validate(relationship.target, label: "target")
        let rawJSON = String(decoding: try encoder.encode(relationship), as: UTF8.self)
        try executePrepared(
            """
            INSERT OR REPLACE INTO person_relationships (
                id,
                source_kind, source_person_id, source_protected_identity_anchor, source_memory_entity_id, source_memory_stable_key,
                target_kind, target_person_id, target_protected_identity_anchor, target_memory_entity_id, target_memory_stable_key,
                relationship_kind, custom_kind_label, note, evidence_text, confidence, status, created_at, updated_at, raw_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(relationship.id),
                .text(relationship.source.kind.rawValue),
                .optionalText(relationship.source.personID?.rawValue),
                .optionalText(relationship.source.protectedIdentityAnchor),
                .optionalText(relationship.source.memoryEntityID),
                .optionalText(relationship.source.memoryStableKey),
                .text(relationship.target.kind.rawValue),
                .optionalText(relationship.target.personID?.rawValue),
                .optionalText(relationship.target.protectedIdentityAnchor),
                .optionalText(relationship.target.memoryEntityID),
                .optionalText(relationship.target.memoryStableKey),
                .text(relationship.kind.rawValue),
                .optionalText(relationship.customKindLabel),
                .optionalText(relationship.note),
                .optionalText(relationship.evidenceText),
                .optionalDouble(relationship.confidence),
                .text(relationship.status.rawValue),
                .text(isoString(relationship.createdAt)),
                .text(isoString(relationship.updatedAt)),
                .text(rawJSON)
            ]
        )
    }

    private func validate(_ endpoint: PersonRelationshipEndpoint, label: String) throws {
        switch endpoint.kind {
        case .personProfile:
            guard endpoint.personID != nil else {
                throw SQLitePersonRelationshipStoreError.invalidEndpoint("\(label) personProfile endpoint requires personID")
            }
        case .currentUser:
            guard endpoint.protectedIdentityAnchor == PersonRelationshipEndpoint.currentUserProtectedIdentityAnchor,
                  endpoint.memoryStableKey == PersonRelationshipEndpoint.currentUserMemoryStableKey else {
                throw SQLitePersonRelationshipStoreError.invalidEndpoint("\(label) currentUser endpoint requires current_user anchor metadata")
            }
        }
    }

    private func queryJSONRelationships(sql: String) throws -> [PersonRelationship] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        var relationships: [PersonRelationship] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw lastError() }
            guard let cString = sqlite3_column_text(statement, 0) else { continue }
            let rawJSON = String(cString: cString)
            relationships.append(try decoder.decode(PersonRelationship.self, from: Data(rawJSON.utf8)))
        }
        return relationships
    }

    private enum Binding {
        case text(String)
        case optionalText(String?)
        case optionalDouble(Double?)
    }

    private func executePrepared(_ sql: String, bindings: [Binding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLITE_RELATIONSHIP_TRANSIENT)
            case .optionalText(let value):
                if let value {
                    result = sqlite3_bind_text(statement, index, value, -1, SQLITE_RELATIONSHIP_TRANSIENT)
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            case .optionalDouble(let value):
                if let value {
                    result = sqlite3_bind_double(statement, index, value)
                } else {
                    result = sqlite3_bind_null(statement, index)
                }
            }
            guard result == SQLITE_OK else { throw lastError() }
        }

        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func lastError() -> SQLitePersonRelationshipStoreError {
        SQLitePersonRelationshipStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func isoString(_ date: Date) -> String {
        String(format: "%.6f", date.timeIntervalSince1970)
    }
}

private let SQLITE_RELATIONSHIP_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
