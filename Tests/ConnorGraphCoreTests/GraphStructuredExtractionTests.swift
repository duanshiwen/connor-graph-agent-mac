import Foundation
import Testing
import ConnorGraphCore

@Test func structuredExtractionOutputValidatesEvidenceSchema() throws {
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

    try output.validate()
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
        try output.validate()
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
        try output.validate()
    }
}
