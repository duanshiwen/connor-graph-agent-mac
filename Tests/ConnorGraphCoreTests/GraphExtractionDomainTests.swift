import Foundation
import Testing
import ConnorGraphCore

@Test func extractionDraftBuildsEpisodeEntitiesAndStatements() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let source = GraphExtractionSource(
        id: "email-1",
        graphID: "default",
        sourceType: .email,
        title: "Tea preference",
        content: "诗闻 likes tea.",
        occurredAt: now,
        metadata: ["mailbox": "inbox"]
    )
    let subject = GraphExtractedEntityDraft(localID: "shiwen", name: "诗闻", entityKind: .personObject, scope: .personal)
    let object = GraphExtractedEntityDraft(localID: "tea", name: "tea", entityKind: .lifeObject, scope: .personal, canonicalClassID: "preference")
    let relation = GraphExtractedStatementDraft(subjectLocalID: "shiwen", predicate: .prefers, objectLocalID: "tea", statementText: "诗闻 prefers tea", confidence: 0.88)

    let batch = try GraphExtractionDraft(source: source, entities: [subject, object], statements: [relation]).toOptimisticWriteBatch(now: now)

    #expect(batch.graphID == "default")
    #expect(batch.episode?.id == "episode-email-1")
    #expect(batch.entities.map(\.id).sorted() == ["entity-default-shiwen", "entity-default-tea"].sorted())
    #expect(batch.statements.count == 1)
    #expect(batch.statements.first?.subjectEntityID == "entity-default-shiwen")
    #expect(batch.statements.first?.objectEntityID == "entity-default-tea")
    #expect(batch.statements.first?.sourceEpisodeIDs == ["episode-email-1"])
    #expect(batch.statements.first?.justifications.first?.type == .extracted)
}

@Test func extractionDraftRejectsStatementWithUnknownLocalEntity() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let source = GraphExtractionSource(id: "note-1", graphID: "default", sourceType: .note, title: "Note", content: "content", occurredAt: now)
    let relation = GraphExtractedStatementDraft(subjectLocalID: "missing", predicate: .mentions, objectLocalID: "also-missing", statementText: "bad")

    #expect(throws: GraphExtractionError.self) {
        _ = try GraphExtractionDraft(source: source, entities: [], statements: [relation]).toOptimisticWriteBatch(now: now)
    }
}
