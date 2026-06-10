import Foundation
import Testing
import ConnorGraphCore

private func testExtractionSource() -> GraphExtractionSource {
    GraphExtractionSource(
        id: "source-1",
        graphID: "default",
        sourceType: .chat,
        title: "Preference",
        content: "诗闻 prefers tea.",
        occurredAt: Date(timeIntervalSince1970: 1_000)
    )
}

@Test func structuredExtractionOutputConvertsToDraftWithEvidenceMetadata() throws {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "shiwen", name: "诗闻", entityKind: .personObject, scope: .personal, evidenceSpanIDs: ["span-1"]),
            GraphStructuredExtractedEntity(localID: "tea", name: "tea", entityKind: .lifeObject, scope: .personal, evidenceSpanIDs: ["span-1"])
        ],
        statements: [
            GraphStructuredExtractedStatement(subjectLocalID: "shiwen", predicate: .prefers, objectLocalID: "tea", statementText: "诗闻 prefers tea", confidence: 0.91, evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [
            GraphStructuredEvidenceSpan(id: "span-1", text: "诗闻 prefers tea.")
        ]
    )

    let draft = try output.toDraft(source: testExtractionSource())

    #expect(draft.entities.count == 2)
    #expect(draft.statements.count == 1)
    #expect(draft.statements[0].metadata["evidence_span_ids"] == "span-1")
    #expect(draft.statements[0].metadata["evidence_spans"] == "诗闻 prefers tea.")
}

@Test func structuredExtractionOutputRejectsUnknownStatementEntity() throws {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "shiwen", name: "诗闻")
        ],
        statements: [
            GraphStructuredExtractedStatement(subjectLocalID: "shiwen", predicate: .prefers, objectLocalID: "missing", statementText: "诗闻 prefers tea", evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "诗闻 prefers tea.")]
    )

    #expect(throws: GraphStructuredExtractionValidationError.statementReferencesUnknownObject(statementID: "statement-shiwen-PREFERS-missing", localID: "missing")) {
        try output.toDraft(source: testExtractionSource())
    }
}

@Test func structuredExtractionOutputRequiresStatementEvidenceByDefault() throws {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "shiwen", name: "诗闻"),
            GraphStructuredExtractedEntity(localID: "tea", name: "tea")
        ],
        statements: [
            GraphStructuredExtractedStatement(subjectLocalID: "shiwen", predicate: .prefers, objectLocalID: "tea", statementText: "诗闻 prefers tea")
        ]
    )

    #expect(throws: GraphStructuredExtractionValidationError.missingEvidence(statementID: "statement-shiwen-PREFERS-tea")) {
        try output.toDraft(source: testExtractionSource())
    }
}
