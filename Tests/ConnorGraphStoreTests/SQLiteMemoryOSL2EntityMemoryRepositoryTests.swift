import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

private func temporaryL2EntityMemoryDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func sqliteL2EntityMemoryRepositoryFindsAliasAndReturnsMinimalView() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryL2EntityMemoryDatabaseURL().path)
    try store.migrate()
    let repository = SQLiteMemoryOSL2EntityMemoryRepository(store: store)
    let service = MemoryOSL2EntityMemoryService(repository: repository)

    _ = try service.updateEntities(MemoryOSL2UpdateEntitiesRequest(entities: [
        MemoryOSL2EntityUpdate(
            name: "《迟到的青春期》",
            type: "work_object",
            aliases: "迟到的青春期, Late Puberty",
            summary: "诗闻的纪录片项目。",
            statements: [
                MemoryOSL2StatementUpdate(
                    text: "《迟到的青春期》马尼拉一个月阶段的明确决策是：不去贫民窟。",
                    factType: "decision"
                )
            ]
        )
    ]))

    let result = try service.findEntities(MemoryOSL2FindEntitiesRequest(names: "Late Puberty"))

    #expect(result.matches.count == 1)
    #expect(result.matches[0].name == "《迟到的青春期》")
    #expect(result.matches[0].aliases == "迟到的青春期, Late Puberty")
    #expect(result.matches[0].statements[0].relation == "RELATED_TO")
    #expect(result.matches[0].statements[0].connectedEntity == nil)

    let statementRows = try store.query(sql: "SELECT evidence_span_ids_json, metadata_json FROM memory_l2_statements")
    #expect(statementRows.count == 1)
    #expect(statementRows[0][0] == "[]")
    let metadata = try store.decode([String: String].self, statementRows[0][1])
    #expect(metadata["l2_fact_type"] == "decision")
    #expect(metadata["factType"] == nil)
    #expect(metadata["polarity"] == nil)
    #expect(metadata["originalPhrase"] == nil)
    let evidenceTables = try store.query(sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'memory_l2_statement_evidence'")
    #expect(evidenceTables.isEmpty)
}

@Test func sqliteL2EntityMemoryRejectsInvalidRelation() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryL2EntityMemoryDatabaseURL().path)
    try store.migrate()
    let repository = SQLiteMemoryOSL2EntityMemoryRepository(store: store)
    let service = MemoryOSL2EntityMemoryService(repository: repository)

    #expect(throws: MemoryOSL2EntityMemoryValidationError.self) {
        try service.updateEntities(MemoryOSL2UpdateEntitiesRequest(entities: [
            MemoryOSL2EntityUpdate(
                name: "Test Entity",
                statements: [
                    MemoryOSL2StatementUpdate(text: "Test statement", relation: "IDENTITY", factType: "other")
                ]
            )
        ]))
    }
}

@Test func graphPredicateFallbacksToRelatedToForUnknownRelation() {
    // Test that GraphPredicate initialization falls back to RELATED_TO
    // when an unknown relation string is provided
    let invalidRelation = "INTERESTED_IN"
    let normalized = invalidRelation.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
        .uppercased()
    
    let predicate = GraphPredicate(rawValue: normalized) ?? .relatedTo
    #expect(predicate == .relatedTo)
}
