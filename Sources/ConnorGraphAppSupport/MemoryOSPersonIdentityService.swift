import Foundation
import ConnorGraphCore
import ConnorGraphStore

public enum MemoryOSPersonIdentityConstants {
    public static let currentUserStableKey = "current_user"
    public static let currentUserEntityID = "l4-entity:current_user"
    public static let currentUserPersonRole = "current_user"
    public static let localAppOwnerIdentityScope = "local_app_owner"
    public static let protectedIdentityAnchor = "true"

    public static let forbiddenCurrentUserAliases: Set<String> = [
        "user", "users", "用户", "当前用户", "current", "profile", "current user", "current_user"
    ]
}

public struct MemoryOSPersonIdentityService: Sendable {
    public init() {}

    public func ensureCurrentUserAnchor(store: SQLiteMemoryOSStore, now: Date = Date()) throws -> MemoryOSEntity {
        if let existing = try resolveCurrentUserAnchor(store: store) {
            let sanitizedAliases = sanitizeCurrentUserAliases(existing.aliases)
            let expectedMetadata = currentUserMetadata(existing.metadata)
            if sanitizedAliases != existing.aliases || expectedMetadata != existing.metadata || existing.stableKey != MemoryOSPersonIdentityConstants.currentUserStableKey {
                let updated = MemoryOSEntity(
                    id: existing.id,
                    stableKey: MemoryOSPersonIdentityConstants.currentUserStableKey,
                    entityType: "person",
                    name: existing.name.isEmpty ? "Current User" : existing.name,
                    aliases: sanitizedAliases,
                    summary: existing.summary.isEmpty ? "The human currently operating this Connor installation." : existing.summary,
                    confidence: max(existing.confidence, 0.99),
                    createdAt: existing.createdAt,
                    updatedAt: now,
                    validFrom: existing.validFrom ?? now,
                    metadata: expectedMetadata
                )
                try store.upsert(entity: updated)
                return updated
            }
            return existing
        }

        let entity = MemoryOSEntity(
            id: MemoryOSPersonIdentityConstants.currentUserEntityID,
            stableKey: MemoryOSPersonIdentityConstants.currentUserStableKey,
            entityType: "person",
            name: "Current User",
            aliases: [],
            summary: "The human currently operating this Connor installation.",
            confidence: 0.99,
            createdAt: now,
            updatedAt: now,
            validFrom: now,
            metadata: currentUserMetadata([:])
        )
        try store.upsert(entity: entity)
        try store.save(audit: MemoryOSAuditEvent(
            eventType: "memory_os.person_identity.current_user_anchor_ensured",
            actor: "memory-os",
            subjectID: entity.id,
            payload: ["stable_key": entity.stableKey, "person_role": MemoryOSPersonIdentityConstants.currentUserPersonRole],
            createdAt: now
        ))
        return entity
    }

    public func resolveCurrentUserAnchor(store: SQLiteMemoryOSStore) throws -> MemoryOSEntity? {
        let byStableKey = try loadEntities(store: store, whereClause: "stable_key = \(store.quote(MemoryOSPersonIdentityConstants.currentUserStableKey))", limit: 1)
        if let entity = byStableKey.first { return entity }
        let candidates = try loadEntities(store: store, whereClause: "entity_type = 'person'", limit: 200)
        return candidates.first { entity in
            entity.metadata["person_role"] == MemoryOSPersonIdentityConstants.currentUserPersonRole ||
            entity.metadata["role"] == MemoryOSPersonIdentityConstants.currentUserPersonRole ||
            entity.metadata["identity_anchor"] == MemoryOSPersonIdentityConstants.currentUserStableKey
        }
    }

    /// Internal hard limit to prevent unbounded SQL queries.
    private static let profileContextMaxRows = 200

    public func currentUserProfileContext(store: SQLiteMemoryOSStore, now: Date = Date()) throws -> [String] {
        // Check cache first
        let cache = MemoryOSQueryCache.shared
        if let cached = cache.getCachedProfile() {
            return cached
        }
        
        guard let anchor = try resolveCurrentUserAnchor(store: store) else {
            return ["[profile] No current_user identity anchor exists."]
        }

        var lines: [String] = []
        var seen = Set<String>()

        for statement in try loadEntityStatements(store: store, entityID: anchor.id) {
            guard lines.count < Self.profileContextMaxRows else { break }
            guard seen.insert(statement.id).inserted else { continue }
            lines.append(appendUpdatedAtSuffix(statement.text, updatedAt: statement.committedAt))
        }

        for statement in try loadCurrentUserL2Statements(store: store, anchor: anchor) {
            guard lines.count < Self.profileContextMaxRows else { break }
            let dedupKey = "l2:\(statement.id)"
            guard seen.insert(dedupKey).inserted else { continue }
            lines.append(appendUpdatedAtSuffix(statement.text, updatedAt: statement.committedAt))
        }

        // Cache the result
        cache.setCachedProfile(lines)
        
        return lines
    }

    public func currentUserProfileHits(store: SQLiteMemoryOSStore) throws -> [MemoryOSRetrievalHit] {
        guard let anchor = try resolveCurrentUserAnchor(store: store) else { return [] }
        let formatter = ISO8601DateFormatter()
        let l4 = try loadEntityStatements(store: store, entityID: anchor.id).map { statement in
            let updatedAt = formatter.string(from: statement.committedAt)
            return MemoryOSRetrievalHit(
                layer: .l4,
                recordID: statement.id,
                title: statement.predicate.rawValue,
                summary: statement.text,
                matchedText: statement.text,
                score: 1,
                evidenceRefs: statement.evidenceSpanIDs,
                entityRefs: [statement.entityID] + [statement.objectEntityID].compactMap { $0 },
                metadata: ["updated_at": updatedAt, "effective_updated_at": updatedAt, "confidence": String(statement.confidence), "status": statement.metadata["status"] ?? MemoryOSRecordTemporalStatus.active.rawValue]
            )
        }
        let l2 = try loadCurrentUserL2Statements(store: store, anchor: anchor).map { statement in
            let updatedAt = formatter.string(from: statement.committedAt)
            return MemoryOSRetrievalHit(
                layer: .l2,
                recordID: statement.id,
                title: statement.predicate,
                summary: statement.text,
                matchedText: statement.text,
                score: 1,
                evidenceRefs: statement.evidenceSpanIDs,
                entityRefs: [statement.subjectID] + [statement.objectID].compactMap { $0 },
                metadata: ["updated_at": updatedAt, "effective_updated_at": updatedAt, "confidence": String(statement.confidence), "status": statement.metadata["status"] ?? MemoryOSRecordTemporalStatus.active.rawValue]
            )
        }
        return (l4 + l2).sorted(by: SQLiteMemoryOSUnifiedRetrievalService.isOrderedBefore)
    }

    private func appendUpdatedAtSuffix(_ text: String, updatedAt: Date) -> String {
        guard !text.contains("(updated_at:") else { return text }
        return "\(text) (updated_at: \(ISO8601DateFormatter().string(from: updatedAt)))"
    }

    private func currentUserMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.merging([
            "person_role": MemoryOSPersonIdentityConstants.currentUserPersonRole,
            "role": MemoryOSPersonIdentityConstants.currentUserPersonRole,
            "identity_scope": MemoryOSPersonIdentityConstants.localAppOwnerIdentityScope,
            "system_owned": "true",
            "protected_identity_anchor": MemoryOSPersonIdentityConstants.protectedIdentityAnchor
        ]) { current, _ in current }
    }

    private func sanitizeCurrentUserAliases(_ aliases: [String]) -> [String] {
        aliases.filter { alias in
            !MemoryOSPersonIdentityConstants.forbiddenCurrentUserAliases.contains(alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    private func loadEntities(store: SQLiteMemoryOSStore, whereClause: String, limit: Int) throws -> [MemoryOSEntity] {
        let rows = try store.query(sql: """
        SELECT id, stable_key, entity_type, name, aliases_json, summary, confidence, created_at, updated_at, valid_from, metadata_json
        FROM memory_l4_entities
        WHERE \(whereClause)
        ORDER BY updated_at DESC
        LIMIT \(limit)
        """)
        return try rows.map { row in
            MemoryOSEntity(
                id: row[0],
                stableKey: row[1],
                entityType: row[2],
                name: row[3],
                aliases: try store.decode([String].self, row[4]),
                summary: row[5],
                confidence: Double(row[6]) ?? 0,
                createdAt: ISO8601DateFormatter().date(from: row[7]) ?? Date(timeIntervalSince1970: 0),
                updatedAt: ISO8601DateFormatter().date(from: row[8]) ?? Date(timeIntervalSince1970: 0),
                validFrom: row[9].isEmpty ? nil : ISO8601DateFormatter().date(from: row[9]),
                metadata: try store.decode([String: String].self, row[10])
            )
        }
    }

    private func loadEntityStatements(store: SQLiteMemoryOSStore, entityID: String) throws -> [MemoryOSEntityStatement] {
        let rows = try store.query(sql: """
        SELECT id, entity_id, predicate, object_entity_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json
        FROM memory_l4_entity_statements
        WHERE entity_id = \(store.quote(entityID))
           OR json_extract(metadata_json, '$.person_role') = 'current_user'
           OR json_extract(metadata_json, '$.identity_anchor_id') = \(store.quote(entityID))
        ORDER BY committed_at DESC, confidence DESC
        LIMIT \(Self.profileContextMaxRows)
        """)
        return try rows.map { row in
            guard let predicate = MemoryOSL4RelationPredicate(rawValue: row[2]) else {
                throw NSError(domain: "MemoryOSPersonIdentityService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid L4 relation predicate: \(row[2])"])
            }
            return MemoryOSEntityStatement(
                id: row[0],
                entityID: row[1],
                predicate: predicate,
                objectEntityID: row[3].isEmpty ? nil : row[3],
                text: row[4],
                assertionKind: MemoryOSAssertionKind(rawValue: row[5]) ?? .observed,
                confidence: Double(row[6]) ?? 0,
                validAt: ISO8601DateFormatter().date(from: row[7]) ?? Date(timeIntervalSince1970: 0),
                committedAt: ISO8601DateFormatter().date(from: row[8]) ?? Date(timeIntervalSince1970: 0),
                evidenceSpanIDs: try store.decode([String].self, row[9]),
                sourceArtifactID: row[10].isEmpty ? nil : row[10],
                metadata: try store.decode([String: String].self, row[11])
            )
        }
    }

    private func loadCurrentUserL2Statements(store: SQLiteMemoryOSStore, anchor: MemoryOSEntity) throws -> [MemoryOSStatement] {
        let rows = try store.query(sql: """
        SELECT s.id, s.subject_id, s.predicate, s.object_id, s.text, s.assertion_kind, s.confidence, s.valid_at, s.committed_at, s.evidence_span_ids_json, s.source_artifact_id, s.metadata_json
        FROM memory_l2_statements s
        LEFT JOIN memory_l2_nodes n ON n.id = s.subject_id
        WHERE json_extract(s.metadata_json, '$.person_role') = 'current_user'
           OR json_extract(s.metadata_json, '$.identity_anchor_id') = \(store.quote(anchor.id))
           OR json_extract(n.metadata_json, '$.person_role') = 'current_user'
           OR n.stable_key = \(store.quote(anchor.stableKey))
           OR n.stable_key = 'current_user_profile'
        ORDER BY s.committed_at DESC, s.confidence DESC
        LIMIT \(Self.profileContextMaxRows)
        """)
        return try rows.map { row in
            MemoryOSStatement(
                id: row[0],
                subjectID: row[1],
                predicate: row[2],
                objectID: row[3].isEmpty ? nil : row[3],
                text: row[4],
                assertionKind: MemoryOSAssertionKind(rawValue: row[5]) ?? .observed,
                confidence: Double(row[6]) ?? 0,
                validAt: ISO8601DateFormatter().date(from: row[7]) ?? Date(timeIntervalSince1970: 0),
                committedAt: ISO8601DateFormatter().date(from: row[8]) ?? Date(timeIntervalSince1970: 0),
                evidenceSpanIDs: try store.decode([String].self, row[9]),
                sourceArtifactID: row[10].isEmpty ? nil : row[10],
                metadata: try store.decode([String: String].self, row[11])
            )
        }
    }
}
