import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryMemoryOSRepositoryDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func memoryOSRepositoriesPersistL2StatementWithoutEvidenceJoinTable() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryMemoryOSRepositoryDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let object = MemoryOSProvenanceObject(id: "prov-repo", sourceType: .manual, title: "Evidence", content: "Entity statements need evidence.", occurredAt: now)
    let span = MemoryOSProvenanceSpan(id: "span-repo", provenanceObjectID: object.id, text: "need evidence")
    let node = MemoryOSNode(id: "node-repo", stableKey: "default:concept:evidence", nodeType: "concept", name: "Evidence")
    let statement = MemoryOSStatement(id: "stmt-repo", subjectID: node.id, predicate: "requires", text: "Entity statements need evidence.", assertionKind: .observed, confidence: 0.9, validAt: now, committedAt: now, evidenceSpanIDs: [span.id])

    try store.upsert(provenance: object)
    try store.upsert(span: span)
    try store.upsert(node: node)
    try store.upsert(statement: statement)

    let statementRows = try store.query(sql: "SELECT id, evidence_span_ids_json FROM memory_l2_statements WHERE id = 'stmt-repo'")
    #expect(statementRows == [["stmt-repo", "[\"span-repo\"]"]])
    let evidenceTables = try store.query(sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'memory_l2_statement_evidence'")
    #expect(evidenceTables.isEmpty)
}
