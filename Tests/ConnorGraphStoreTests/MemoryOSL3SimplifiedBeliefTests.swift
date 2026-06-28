import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryL3DatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func simplifiedL3BeliefUpsertPersistsStatementDisciplineDomainAndRelatedConceptNames() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryL3DatabaseURL().path)
    try store.migrate()
    let createdAt = Date(timeIntervalSince1970: 1_000)
    let updatedAt = Date(timeIntervalSince1970: 2_000)

    let belief = MemoryOSBelief(
        id: "belief-1",
        statement: "Semantic memory separates reusable knowledge statements from operational facts.",
        domain: "knowledge-management",
        relatedObjectNames: "Semantic memory, Knowledge representation",
        createdAt: createdAt,
        updatedAt: updatedAt
    )
    try store.upsert(belief: belief)

    let rows = try store.query(sql: "SELECT id, statement, domain, related_object_names, created_at, updated_at FROM memory_l3_beliefs WHERE id = 'belief-1'")
    #expect(rows.count == 1)
    #expect(rows[0][0] == "belief-1")
    #expect(rows[0][1] == belief.statement)
    #expect(rows[0][2] == "knowledge-management")
    #expect(rows[0][3] == "Semantic memory, Knowledge representation")
    #expect(rows[0][4].contains("1970-01-01T00:16:40"))
    #expect(rows[0][5].contains("1970-01-01T00:33:20"))
}

@Test func simplifiedL3BeliefUpsertPreservesCreatedAtWhenUpdatingExistingBelief() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryL3DatabaseURL().path)
    try store.migrate()

    try store.upsert(belief: MemoryOSBelief(
        id: "belief-1",
        statement: "Original reusable knowledge statement.",
        domain: "knowledge-management",
        relatedObjectNames: "Semantic memory",
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000)
    ))

    try store.upsert(belief: MemoryOSBelief(
        id: "belief-1",
        statement: "Updated reusable knowledge statement.",
        domain: "software-engineering",
        relatedObjectNames: "Memory architecture",
        createdAt: Date(timeIntervalSince1970: 9_999),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    ))

    let rows = try store.query(sql: "SELECT statement, domain, related_object_names, created_at, updated_at FROM memory_l3_beliefs WHERE id = 'belief-1'")
    #expect(rows.count == 1)
    #expect(rows[0][0] == "Updated reusable knowledge statement.")
    #expect(rows[0][1] == "software-engineering")
    #expect(rows[0][2] == "Memory architecture")
    #expect(rows[0][3].contains("1970-01-01T00:16:40"))
    #expect(rows[0][4].contains("1970-01-01T00:33:20"))
}

@Test func simplifiedL3BeliefFTSIndexesOnlyStatement() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryL3DatabaseURL().path)
    try store.migrate()

    try store.upsert(belief: MemoryOSBelief(
        id: "belief-1",
        statement: "Alpha semantic memory rule",
        domain: "OnlyDomainToken",
        relatedObjectNames: "OnlyRelatedConceptToken",
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000)
    ))

    let statementHits = try store.queryStrings(sql: "SELECT belief_id FROM memory_l3_beliefs_fts WHERE memory_l3_beliefs_fts MATCH 'Alpha'")
    let domainHits = try store.queryStrings(sql: "SELECT belief_id FROM memory_l3_beliefs_fts WHERE memory_l3_beliefs_fts MATCH 'OnlyDomainToken'")
    let relatedHits = try store.queryStrings(sql: "SELECT belief_id FROM memory_l3_beliefs_fts WHERE memory_l3_beliefs_fts MATCH 'OnlyRelatedConceptToken'")

    #expect(statementHits == ["belief-1"])
    #expect(domainHits.isEmpty)
    #expect(relatedHits.isEmpty)
}

@Test func simplifiedL3DomainsCanBeListedByDisciplineWithCounts() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryL3DatabaseURL().path)
    try store.migrate()

    try store.upsert(belief: MemoryOSBelief(statement: "A", domain: "software-engineering"))
    try store.upsert(belief: MemoryOSBelief(statement: "B", domain: "software-engineering"))
    try store.upsert(belief: MemoryOSBelief(statement: "C", domain: "knowledge-management"))

    let domains = try store.listL3Domains()

    #expect(domains.map(\.domain) == ["software-engineering", "knowledge-management"])
    #expect(domains.first?.beliefCount == 2)
    #expect(domains.last?.beliefCount == 1)
}

@Test func simplifiedL3RelatedConceptNamesAreNormalizedAsDurableConceptNameList() throws {
    let normalized = MemoryOSBelief.normalizedRelatedConceptNames("Semantic memory, Knowledge representation，Semantic memory、Controlled vocabulary")

    #expect(normalized == "Semantic memory, Knowledge representation, Controlled vocabulary")
}

@Test func simplifiedL3DisciplineDomainNormalizationPreventsProjectAndModuleDomainPollution() throws {
    #expect(MemoryOSBelief.normalizedDisciplineDomain("Software Engineering") == "software-engineering")
    #expect(MemoryOSBelief.normalizedDisciplineDomain("AI") == "artificial-intelligence")
    #expect(MemoryOSBelief.normalizedDisciplineDomain("memory-os") == "knowledge-management")
    #expect(MemoryOSBelief.normalizedDisciplineDomain("") == "general-knowledge")
}
