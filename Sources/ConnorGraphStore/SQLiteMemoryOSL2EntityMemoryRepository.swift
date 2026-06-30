import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public final class SQLiteMemoryOSL2EntityMemoryRepository: MemoryOSL2EntityMemoryRepository, @unchecked Sendable {
    private let store: SQLiteMemoryOSStore

    public init(store: SQLiteMemoryOSStore) {
        self.store = store
    }

    public func findEntities(matchingNames names: [String]) throws -> [MemoryOSL2StoredEntity] {
        guard !names.isEmpty else { return [] }
        let entities = try loadAllEntities()
        let wanted = Set(names.map(Self.normalize))
        let matched = entities.filter { entity in
            wanted.contains(Self.normalize(entity.name)) || entity.aliases.contains { wanted.contains(Self.normalize($0)) }
        }
        return try matched.map(loadStatements(for:)).sorted { $0.name < $1.name }
    }

    public func upsertEntity(_ update: MemoryOSL2EntityUpdate, aliases: [String]) throws -> (entity: MemoryOSL2StoredEntity, action: String) {
        let name = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = try findEntities(matchingNames: [name] + aliases)
        if var existing = matches.first {
            existing.aliases = merge(existing.aliases, aliases)
            if let type = update.type?.nilIfBlank { existing.type = type }
            if let summary = update.summary?.nilIfBlank { existing.summary = summary }
            try save(entity: existing)
            return (try loadStatements(for: existing), "updated")
        }
        var entity = MemoryOSL2StoredEntity(
            id: UUID().uuidString,
            name: name,
            type: update.type?.nilIfBlank ?? "entity",
            aliases: aliases,
            summary: update.summary?.nilIfBlank ?? ""
        )
        try save(entity: entity)
        entity = try loadStatements(for: entity)
        return (entity, "created")
    }

    public func appendStatement(_ statement: MemoryOSL2StatementUpdate, to entity: MemoryOSL2StoredEntity) throws -> MemoryOSL2StatementActionSummary {
        let text = statement.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return MemoryOSL2StatementActionSummary(text: text, action: "skipped_empty") }
        let existing = try store.query(sql: "SELECT id FROM memory_l2_statements WHERE subject_id = \(store.quote(entity.id)) AND text = \(store.quote(text)) LIMIT 1")
        if !existing.isEmpty {
            return MemoryOSL2StatementActionSummary(text: text, action: "skipped_duplicate")
        }
        let connectedID: String? = nil
        let metadata = [
            "l2_fact_type": statement.factType
        ].compactMapValues { $0?.nilIfBlank }
        let now = Date()
        let memoryStatement = MemoryOSStatement(
            id: UUID().uuidString,
            subjectID: entity.id,
            predicate: statement.relation?.nilIfBlank ?? "RELATED_TO",
            objectID: connectedID,
            text: text,
            assertionKind: .observed,
            confidence: 0.7,
            validAt: now,
            committedAt: now,
            evidenceSpanIDs: [],
            sourceArtifactID: nil,
            metadata: metadata
        )
        try store.upsert(statement: memoryStatement)
        return MemoryOSL2StatementActionSummary(text: text, action: "added")
    }

    private func loadAllEntities() throws -> [MemoryOSL2StoredEntity] {
        let rows = try store.query(sql: "SELECT id, node_type, name, summary, metadata_json, COALESCE(updated_at, '') FROM memory_l2_nodes ORDER BY name ASC")
        return try rows.map { row in
            let metadata = try store.decode([String: String].self, row[4])
            return MemoryOSL2StoredEntity(
                id: row[0],
                name: row[2],
                type: row[1],
                aliases: Self.splitStoredAliases(metadata["aliases"] ?? ""),
                summary: row[3],
                statements: [],
                updatedAt: row[5]
            )
        }
    }

    private func loadStatements(for entity: MemoryOSL2StoredEntity) throws -> MemoryOSL2StoredEntity {
        let rows = try store.query(sql: """
        SELECT s.id, s.text, s.predicate, COALESCE(o.name, ''), s.metadata_json, COALESCE(s.committed_at, '')
        FROM memory_l2_statements s
        LEFT JOIN memory_l2_nodes o ON o.id = s.object_id
        WHERE s.subject_id = \(store.quote(entity.id))
        ORDER BY s.committed_at DESC, s.id ASC
        """)
        let statements = try rows.map { row in
            MemoryOSL2StoredStatement(
                id: row[0],
                text: row[1],
                relation: row[2],
                connectedEntityName: row[3].isEmpty ? nil : row[3],
                metadata: try store.decode([String: String].self, row[4]),
                committedAt: row[5]
            )
        }
        var copy = entity
        copy.statements = statements
        return copy
    }

    private func save(entity: MemoryOSL2StoredEntity) throws {
        let metadata = ["aliases": entity.aliases.joined(separator: ", ")]
        let stableKey = "l2:\(entity.type):\(Self.normalize(entity.name))"
        let now = Date()
        try store.upsert(node: MemoryOSNode(
            id: entity.id,
            stableKey: stableKey,
            nodeType: entity.type,
            name: entity.name,
            summary: entity.summary,
            createdAt: now,
            updatedAt: now,
            metadata: metadata
        ))
    }

    private static func splitStoredAliases(_ aliases: String) -> [String] {
        MemoryOSL2EntityMemoryService.splitNames(aliases)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func merge(_ lhs: [String], _ rhs: [String]) -> [String] {
        (lhs + rhs).reduce(into: []) { result, alias in
            if !result.contains(where: { Self.normalize($0) == Self.normalize(alias) }) {
                result.append(alias)
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
