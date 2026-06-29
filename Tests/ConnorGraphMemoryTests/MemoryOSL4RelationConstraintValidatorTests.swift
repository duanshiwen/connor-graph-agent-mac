import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func l4RelationConstraintValidatorAcceptsValidCompositionRelation() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(name: "Memory OS", conceptType: "system"),
        MemoryOSExtractedConceptEntity(name: "L4", conceptType: "component")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectName: "Memory OS",
        predicate: .hasPart,
        objectName: "L4",
        text: "Memory OS has L4."
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities)

    #expect(issues.isEmpty)
}

@Test func l4RelationConstraintValidatorAllowsMissingEvidenceButRejectsSelfLoop() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(name: "Memory OS", conceptType: "system")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectName: "Memory OS",
        predicate: .hasPart,
        objectName: "Memory OS",
        text: "Memory OS has itself."
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities)
    let codes = Set(issues.map(\.code))

    #expect(!codes.contains("missing_relation_evidence"))
    #expect(codes.contains("l4_relation_self_loop"))
}

@Test func l4RelationConstraintValidatorAllowsWeakRelationsWithoutReason() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(name: "Memory OS", conceptType: "system"),
        MemoryOSExtractedConceptEntity(name: "Graph", conceptType: "concept")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectName: "Memory OS",
        predicate: .relatedTo,
        objectName: "Graph",
        text: "Memory OS relates to graph."
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities)

    #expect(issues.isEmpty)
}

@Test func l4RelationConstraintValidatorAllowsCausalRelationsWithoutBasis() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(name: "Tool Loop", conceptType: "mechanism"),
        MemoryOSExtractedConceptEntity(name: "Memory Quality", conceptType: "outcome")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectName: "Tool Loop",
        predicate: .causes,
        objectName: "Memory Quality",
        text: "Tool loops cause quality."
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities)

    #expect(issues.isEmpty)
}

@Test func l4RelationConstraintValidatorAllowsStrictIdentityBelowConfidence() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(name: "Memory OS", conceptType: "system"),
        MemoryOSExtractedConceptEntity(name: "Memory System", conceptType: "system")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectName: "Memory OS",
        predicate: .sameAs,
        objectName: "Memory System",
        text: "Memory OS is the same as Memory System."
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities)

    #expect(issues.isEmpty)
}

@Test func l4RelationConstraintValidatorUsesControlledTypeAliasesForIdentityCompatibility() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(name: "北京大学", conceptType: "university"),
        MemoryOSExtractedConceptEntity(name: "Peking University", conceptType: "organization")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectName: "北京大学",
        predicate: .sameAs,
        objectName: "Peking University",
        text: "北京大学 is Peking University."
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities)

    #expect(issues.isEmpty)
}

@Test func l4RelationConstraintValidatorRejectsTaxonomyObjectThatIsNotTypeLike() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(name: "Memory OS", conceptType: "system"),
        MemoryOSExtractedConceptEntity(name: "SQLite", conceptType: "technology")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectName: "Memory OS",
        predicate: .instanceOf,
        objectName: "SQLite",
        text: "Memory OS is an instance of SQLite."
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities)

    #expect(issues.contains { $0.code == "l4_relation_object_type_not_allowed" })
}
