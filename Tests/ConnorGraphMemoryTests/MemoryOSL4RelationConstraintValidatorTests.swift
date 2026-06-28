import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func l4RelationConstraintValidatorAcceptsValidCompositionRelation() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(localID: "memory-os", name: "Memory OS", conceptType: "system", confidence: 0.9, evidenceSpanIDs: ["span-1"]),
        MemoryOSExtractedConceptEntity(localID: "l4", name: "L4", conceptType: "component", confidence: 0.9, evidenceSpanIDs: ["span-1"])
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectLocalID: "memory-os",
        predicate: .hasPart,
        objectLocalID: "l4",
        text: "Memory OS has L4.",
        confidence: 0.86,
        evidenceSpanIDs: ["span-1"]
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities, evidenceSpanIDs: ["span-1"])

    #expect(issues.isEmpty)
}

@Test func l4RelationConstraintValidatorAllowsMissingEvidenceButRejectsSelfLoop() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(localID: "memory-os", name: "Memory OS", conceptType: "system", confidence: 0.9)
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectLocalID: "memory-os",
        predicate: .hasPart,
        objectLocalID: "memory-os",
        text: "Memory OS has itself.",
        confidence: 0.9,
        evidenceSpanIDs: []
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities, evidenceSpanIDs: [])
    let codes = Set(issues.map(\.code))

    #expect(!codes.contains("missing_relation_evidence"))
    #expect(codes.contains("l4_relation_self_loop"))
}

@Test func l4RelationConstraintValidatorAllowsWeakRelationsWithoutReason() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(localID: "memory-os", name: "Memory OS", conceptType: "system"),
        MemoryOSExtractedConceptEntity(localID: "graph", name: "Graph", conceptType: "concept")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectLocalID: "memory-os",
        predicate: .relatedTo,
        objectLocalID: "graph",
        text: "Memory OS relates to graph.",
        confidence: 0.7,
        evidenceSpanIDs: ["span-1"]
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities, evidenceSpanIDs: ["span-1"])

    #expect(issues.isEmpty)
}

@Test func l4RelationConstraintValidatorAllowsCausalRelationsWithoutBasis() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(localID: "tool-loop", name: "Tool Loop", conceptType: "mechanism"),
        MemoryOSExtractedConceptEntity(localID: "quality", name: "Memory Quality", conceptType: "outcome")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectLocalID: "tool-loop",
        predicate: .causes,
        objectLocalID: "quality",
        text: "Tool loops cause quality.",
        confidence: 0.9,
        evidenceSpanIDs: ["span-1"]
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities, evidenceSpanIDs: ["span-1"])

    #expect(issues.isEmpty)
}

@Test func l4RelationConstraintValidatorAllowsStrictIdentityBelowConfidence() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(localID: "a", name: "Memory OS", conceptType: "system"),
        MemoryOSExtractedConceptEntity(localID: "b", name: "Memory System", conceptType: "system")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectLocalID: "a",
        predicate: .sameAs,
        objectLocalID: "b",
        text: "Memory OS is the same as Memory System.",
        confidence: 0.1,
        evidenceSpanIDs: ["missing-span"]
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities, evidenceSpanIDs: [])

    #expect(issues.isEmpty)
}

@Test func l4RelationConstraintValidatorRejectsTaxonomyObjectThatIsNotTypeLike() {
    let validator = MemoryOSL4RelationConstraintValidator()
    let entities = [
        MemoryOSExtractedConceptEntity(localID: "memory-os", name: "Memory OS", conceptType: "system"),
        MemoryOSExtractedConceptEntity(localID: "sqlite", name: "SQLite", conceptType: "technology")
    ]
    let relation = MemoryOSExtractedConceptRelation(
        subjectLocalID: "memory-os",
        predicate: .instanceOf,
        objectLocalID: "sqlite",
        text: "Memory OS is an instance of SQLite.",
        confidence: 0.9,
        evidenceSpanIDs: ["span-1"]
    )

    let issues = validator.validate(relation: relation, conceptEntities: entities, evidenceSpanIDs: ["span-1"])

    #expect(issues.contains { $0.code == "l4_relation_object_type_not_allowed" })
}
