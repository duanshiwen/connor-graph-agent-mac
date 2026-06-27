import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryMemoryOSProjectionDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func memoryOSStorePersistsProjectionBatchAcrossL2L3L4() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSProjectionDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 3_000)
    try store.upsert(provenance: MemoryOSProvenanceObject(id: "object-1", sourceType: .manual, title: "Evidence", content: "诗闻正在推进 Connor Memory OS H4。", occurredAt: now))
    try store.upsert(span: MemoryOSProvenanceSpan(id: "span-1", provenanceObjectID: "object-1", text: "诗闻正在推进 Connor Memory OS H4。"))

    let batch = MemoryOSProjectionBatch(
        artifactID: "artifact-1",
        nodes: [
            MemoryOSNode(id: "node-person", stableKey: "personal:person_object:诗闻", nodeType: "person_object", name: "诗闻", createdAt: now, updatedAt: now),
            MemoryOSNode(id: "node-project", stableKey: "project:work_object:connor-memory-os", nodeType: "work_object", name: "Connor Memory OS", createdAt: now, updatedAt: now)
        ],
        statements: [
            MemoryOSStatement(id: "statement-1", subjectID: "node-person", predicate: "RELATED_TO", objectID: "node-project", text: "诗闻正在推进 Connor Memory OS H4。", assertionKind: .observed, confidence: 0.94, validAt: now, committedAt: now, evidenceSpanIDs: ["span-1"], sourceArtifactID: "artifact-1")
        ],
        entities: [
            MemoryOSEntity(id: "entity-person", stableKey: "personal:person_object:诗闻", entityType: "person_object", name: "诗闻", aliases: ["Shiwen"], summary: "Current user", confidence: 0.95, createdAt: now, updatedAt: now),
            MemoryOSEntity(id: "entity-project", stableKey: "project:work_object:connor-memory-os", entityType: "work_object", name: "Connor Memory OS", summary: "Memory OS", confidence: 0.93, createdAt: now, updatedAt: now)
        ],
        entityStatements: [
            MemoryOSEntityStatement(id: "entity-statement-1", entityID: "entity-person", predicate: .relatedTo, objectEntityID: "entity-project", text: "诗闻正在推进 Connor Memory OS H4。", assertionKind: .observed, confidence: 0.94, validAt: now, committedAt: now, evidenceSpanIDs: ["span-1"], sourceArtifactID: "artifact-1")
        ],
        beliefs: [
            MemoryOSBelief(id: "belief-1", topic: "RELATED_TO", statement: "诗闻正在推进 Connor Memory OS H4。", projectionKind: .observed, confidence: 0.94, evidenceStatementIDs: ["statement-1"], validAt: now, projectedAt: now, sourceArtifactID: "artifact-1")
        ]
    )

    try store.saveProjectionBatch(batch)

    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_nodes;").first?.first == "2")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_statements;").first?.first == "1")
    #expect(try store.query(sql: "SELECT evidence_span_ids_json FROM memory_l2_statements WHERE id = 'statement-1';").first?.first == "[\"span-1\"]")
    #expect(try store.query(sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'memory_l2_statement_evidence';").isEmpty)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l3_beliefs;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l4_entities;").first?.first == "2")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l4_entity_statements;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l4_entity_statement_evidence WHERE span_id = 'span-1';").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_projections WHERE projection_key = 'artifact:artifact-1';").first?.first == "1")
    #expect(try store.searchStatementsFTS(query: "Connor", limit: 10).contains("statement-1"))
    #expect(try store.searchEntitiesFTS(query: "Shiwen", limit: 10).contains("entity-person"))
}
