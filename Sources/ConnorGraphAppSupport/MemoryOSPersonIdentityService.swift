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

public struct MemoryOSCurrentUserProfileContext: Sendable, Codable, Equatable {
    public var currentUserMarker: String
    public var resolvedCurrentUserEntityIDs: [String]
    public var hitCount: Int { hits.count }
    public var hits: [MemoryOSRetrievalHit]
    public var diagnostics: [MemoryOSCurrentViewDiagnostic]
    public var scopePolicy: String

    public init(
        currentUserMarker: String = MemoryOSPersonIdentityConstants.currentUserStableKey,
        resolvedCurrentUserEntityIDs: [String] = [],
        hits: [MemoryOSRetrievalHit] = [],
        diagnostics: [MemoryOSCurrentViewDiagnostic] = [],
        scopePolicy: String = "current_user_anchor_only_no_generic_user_fallback"
    ) {
        self.currentUserMarker = currentUserMarker
        self.resolvedCurrentUserEntityIDs = resolvedCurrentUserEntityIDs
        self.hits = hits
        self.diagnostics = diagnostics
        self.scopePolicy = scopePolicy
    }
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

    public func currentUserProfileContext(store: SQLiteMemoryOSStore, limit: Int = 12, focus: String? = nil, now: Date = Date()) throws -> MemoryOSCurrentUserProfileContext {
        guard let anchor = try resolveCurrentUserAnchor(store: store) else {
            return MemoryOSCurrentUserProfileContext(diagnostics: [MemoryOSCurrentViewDiagnostic(
                kind: "missing_current_user_profile",
                severity: "warning",
                message: "No current_user identity anchor exists. Create it with ensureCurrentUserAnchor before reading profile facts.",
                createdAt: now
            )])
        }

        let safeLimit = max(1, min(limit, 50))
        var hits: [MemoryOSRetrievalHit] = []
        var seen = Set<String>()

        func append(_ hit: MemoryOSRetrievalHit) {
            guard hits.count < safeLimit else { return }
            guard matchesFocus(hit, focus: focus) else { return }
            guard seen.insert(hit.id).inserted else { return }
            hits.append(hit)
        }

        for statement in try loadEntityStatements(store: store, entityID: anchor.id, limit: safeLimit) {
            append(MemoryOSRetrievalHit(
                layer: .l4,
                recordID: statement.id,
                title: statement.predicate.rawValue,
                summary: statement.text,
                matchedText: statement.text,
                score: statement.confidence,
                evidenceRefs: statement.evidenceSpanIDs,
                entityRefs: [anchor.id],
                canReadRaw: false,
                canExpandDepth: true,
                metadata: statement.metadata.merging([
                    "record_kind": "current_user_l4_statement",
                    "person_role": MemoryOSPersonIdentityConstants.currentUserPersonRole,
                    "identity_anchor_id": anchor.id
                ]) { current, _ in current }
            ))
        }

        for statement in try loadCurrentUserL2Statements(store: store, anchor: anchor, limit: safeLimit) {
            append(MemoryOSRetrievalHit(
                layer: .l2,
                recordID: statement.id,
                title: statement.predicate,
                summary: statement.text,
                matchedText: statement.text,
                score: statement.confidence,
                evidenceRefs: statement.evidenceSpanIDs,
                entityRefs: [anchor.id],
                canReadRaw: true,
                canExpandDepth: false,
                metadata: statement.metadata.merging([
                    "record_kind": "current_user_l2_profile_fact",
                    "person_role": MemoryOSPersonIdentityConstants.currentUserPersonRole,
                    "identity_anchor_id": anchor.id
                ]) { current, _ in current }
            ))
        }

        return MemoryOSCurrentUserProfileContext(
            resolvedCurrentUserEntityIDs: [anchor.id],
            hits: Array(hits.prefix(safeLimit)),
            diagnostics: hits.isEmpty ? [MemoryOSCurrentViewDiagnostic(
                kind: "empty_current_user_profile",
                severity: "info",
                message: "Current user anchor exists but no scoped profile facts were found.",
                candidateRecordIDs: [anchor.id],
                createdAt: now
            )] : [],
            scopePolicy: "current_user_anchor_only_no_generic_user_fallback"
        )
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

    private func matchesFocus(_ hit: MemoryOSRetrievalHit, focus: String?) -> Bool {
        guard let focus, !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        let terms = focus.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !terms.isEmpty else { return true }
        let haystack = ([hit.title, hit.summary, hit.matchedText] + hit.metadata.flatMap { [$0.key, $0.value] }).joined(separator: " ").lowercased()
        return terms.contains { haystack.contains($0) }
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

    private func loadEntityStatements(store: SQLiteMemoryOSStore, entityID: String, limit: Int) throws -> [MemoryOSEntityStatement] {
        let rows = try store.query(sql: """
        SELECT id, entity_id, predicate, object_entity_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json
        FROM memory_l4_entity_statements
        WHERE entity_id = \(store.quote(entityID))
           OR json_extract(metadata_json, '$.person_role') = 'current_user'
           OR json_extract(metadata_json, '$.identity_anchor_id') = \(store.quote(entityID))
        ORDER BY committed_at DESC, confidence DESC
        LIMIT \(limit)
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

    private func loadCurrentUserL2Statements(store: SQLiteMemoryOSStore, anchor: MemoryOSEntity, limit: Int) throws -> [MemoryOSStatement] {
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
        LIMIT \(limit)
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
