import Foundation
import Testing
import ConnorGraphCore

@Test func graphPredicateDeclaresEdgeSemantics() {
    #expect(GraphPredicate.instanceOf.edgeKind == .taxonomy)
    #expect(GraphPredicate.subclassOf.edgeKind == .taxonomy)
    #expect(GraphPredicate.partOf.edgeKind == .structural)
    #expect(GraphPredicate.scheduledAt.edgeKind == .calendar)
    #expect(GraphPredicate.prefers.edgeKind == .preference)
    #expect(GraphPredicate.sentBy.edgeKind == .communication)

    #expect(GraphPredicate.subclassOf.isTransitive)
    #expect(GraphPredicate.partOf.isTransitive)
    #expect(GraphPredicate.dependsOn.isTransitive)
    #expect(!GraphPredicate.createdBy.isTransitive)

    #expect(GraphPredicate.partOf.inverse == .hasPart)
    #expect(GraphPredicate.hasPart.inverse == .partOf)
    #expect(GraphPredicate.answers.inverse == .answeredBy)
}

@Test func graphStableKeyNormalizesScopeKindAndName() {
    let key = GraphStableKeyBuilder.stableKey(scope: .personal, entityKind: .communicationObject, name: "  Apple Inc. / 苹果公司  ")

    #expect(key == "personal:communication_object:apple_inc_苹果公司")
}

@Test func graphStatementCarriesTemporalBeliefAndJustification() {
    let validAt = Date(timeIntervalSince1970: 1_000)
    let committedAt = Date(timeIntervalSince1970: 1_100)
    let justification = GraphJustification(type: .userStated, source: "episode-1", strength: 1.0, evidenceSpan: "诗闻 prefers structured plans")
    let statement = GraphStatement(
        id: "statement-1",
        graphID: "default",
        subjectEntityID: "person-shiwen",
        predicate: .prefers,
        objectEntityID: "preference-structured-plans",
        statementText: "诗闻 prefers structured plans.",
        validAt: validAt,
        committedAt: committedAt,
        confidence: 0.95,
        beliefStatus: .active,
        justifications: [justification],
        sourceEpisodeIDs: ["episode-1"]
    )

    #expect(statement.edgeKind == .preference)
    #expect(statement.validAt == validAt)
    #expect(statement.committedAt == committedAt)
    #expect(statement.justifications.first?.type == .userStated)
    #expect(statement.sourceEpisodeIDs == ["episode-1"])
}
