import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func constraintValidatorRejectsInvalidTemporalRange() {
    let validator = GraphConstraintValidator()
    let statement = GraphStatement(
        id: "statement-invalid-time",
        graphID: "default",
        subjectEntityID: "a",
        predicate: .relatedTo,
        objectEntityID: "b",
        statementText: "invalid",
        validAt: Date(timeIntervalSince1970: 2_000),
        invalidAt: Date(timeIntervalSince1970: 1_000),
        committedAt: Date(timeIntervalSince1970: 2_000),
        justifications: [GraphJustification(type: .extracted, source: "episode-1", strength: 0.8)],
        sourceEpisodeIDs: ["episode-1"]
    )

    let result = validator.validate(statement: statement, subject: nil, object: nil)

    #expect(result.errors.contains(.invalidTemporalRange))
}

@Test func constraintValidatorRejectsSubclassSelfLoopAndMissingJustification() {
    let validator = GraphConstraintValidator()
    let statement = GraphStatement(
        id: "statement-self-loop",
        graphID: "default",
        subjectEntityID: "class-person",
        predicate: .subclassOf,
        objectEntityID: "class-person",
        statementText: "person subclass person",
        validAt: Date(timeIntervalSince1970: 1_000),
        committedAt: Date(timeIntervalSince1970: 1_000),
        justifications: [],
        sourceEpisodeIDs: []
    )

    let result = validator.validate(statement: statement, subject: nil, object: nil)

    #expect(result.errors.contains(.selfTaxonomyLoop))
    #expect(result.errors.contains(.missingJustification))
    #expect(result.errors.contains(.missingSourceEpisode))
}

@Test func constraintValidatorRejectsInstanceOfObjectThatIsNotClass() {
    let validator = GraphConstraintValidator()
    let subject = GraphEntity(id: "apple", graphID: "default", name: "Apple", entityKind: .entity, scope: .publicScope)
    let object = GraphEntity(id: "cupertino", graphID: "default", name: "Cupertino", entityKind: .place, scope: .publicScope)
    let statement = GraphStatement(
        id: "statement-bad-instance",
        graphID: "default",
        subjectEntityID: subject.id,
        predicate: .instanceOf,
        objectEntityID: object.id,
        statementText: "Apple instance of Cupertino",
        validAt: Date(timeIntervalSince1970: 1_000),
        committedAt: Date(timeIntervalSince1970: 1_000),
        justifications: [GraphJustification(type: .extracted, source: "episode-1", strength: 0.8)],
        sourceEpisodeIDs: ["episode-1"]
    )

    let result = validator.validate(statement: statement, subject: subject, object: object)

    #expect(result.errors.contains(.instanceOfObjectIsNotClass))
}
