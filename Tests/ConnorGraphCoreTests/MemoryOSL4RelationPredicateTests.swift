import Foundation
import Testing
import ConnorGraphCore

@Test func l4RelationPredicateDeclaresCompleteV1Vocabulary() {
    #expect(MemoryOSL4RelationPredicate.allCases.count == 75)

    let expected: Set<String> = [
        "SAME_AS", "ALIAS_OF", "EQUIVALENT_TO", "EXACT_MATCH", "CLOSE_MATCH",
        "INSTANCE_OF", "SUBCLASS_OF", "BROADER_THAN", "NARROWER_THAN",
        "HAS_PART", "PART_OF", "CONTAINS", "MEMBER_OF", "OVERLAPS_WITH",
        "DEPENDS_ON", "REQUIRES", "ENABLES", "PREVENTS", "CONSTRAINS",
        "SUPPORTS_CAPABILITY", "IMPLEMENTS", "USES",
        "APPLIES_TO", "USED_FOR", "SPECIALIZES", "GENERALIZES", "FIELD_OF_WORK", "IN_INDUSTRY",
        "DERIVED_FROM", "BASED_ON", "SUPPORTED_BY", "CITES", "QUOTES", "GENERATED_BY", "VALIDATED_BY", "ATTRIBUTED_TO",
        "DECIDES", "DECIDED_BY", "GOVERNS", "COMPLIES_WITH", "VIOLATES", "REPLACES", "SUPERSEDES", "DEPRECATES",
        "CAUSES", "INFLUENCES", "MITIGATES", "RISKS",
        "CREATED_BY", "MAINTAINED_BY", "OWNED_BY", "RESPONSIBLE_FOR", "CONTRIBUTED_BY", "REVIEWED_BY", "CURATED_BY", "AUTHORED_BY", "PUBLISHED_BY", "DEVELOPED_BY", "FOUNDED_BY", "STAKEHOLDER_OF", "WORKS_ON",
        "LOCATED_IN", "HAS_LOCATION", "HAS_COORDINATE",
        "DIFFERENT_FROM", "OPPOSITE_OF", "SAID_TO_BE_SAME_AS", "FACET_OF", "STUDIED_BY",
        "ABOUT", "MENTIONS", "HAS_OFFICIAL_WEBSITE", "HAS_IDENTIFIER", "RELATED_TO", "ASSOCIATED_WITH"
    ]

    #expect(Set(MemoryOSL4RelationPredicate.allCases.map(\.rawValue)) == expected)
}

@Test func l4RelationPredicateDeclaresRelationSemantics() {
    #expect(MemoryOSL4RelationPredicate.sameAs.category == .identity)
    #expect(MemoryOSL4RelationPredicate.sameAs.inverse == .sameAs)
    #expect(MemoryOSL4RelationPredicate.sameAs.isSymmetric)
    #expect(MemoryOSL4RelationPredicate.sameAs.isTransitive)
    #expect(MemoryOSL4RelationPredicate.sameAs.isStrict)
    #expect(MemoryOSL4RelationPredicate.sameAs.retrievalWeight == 1.0)

    #expect(MemoryOSL4RelationPredicate.hasPart.category == .composition)
    #expect(MemoryOSL4RelationPredicate.hasPart.inverse == .partOf)
    #expect(MemoryOSL4RelationPredicate.partOf.inverse == .hasPart)

    #expect(MemoryOSL4RelationPredicate.broaderThan.category == .taxonomy)
    #expect(MemoryOSL4RelationPredicate.broaderThan.inverse == .narrowerThan)
    #expect(MemoryOSL4RelationPredicate.narrowerThan.inverse == .broaderThan)

    #expect(MemoryOSL4RelationPredicate.locatedIn.category == .location)
    #expect(MemoryOSL4RelationPredicate.locatedIn.retrievalWeight > MemoryOSL4RelationPredicate.relatedTo.retrievalWeight)
    #expect(MemoryOSL4RelationPredicate.hasCoordinate.category == .location)

    #expect(MemoryOSL4RelationPredicate.fieldOfWork.category == .applicability)
    #expect(MemoryOSL4RelationPredicate.developedBy.category == .contribution)
    #expect(MemoryOSL4RelationPredicate.differentFrom.category == .reference)

    #expect(MemoryOSL4RelationPredicate.relatedTo.category == .reference)
    #expect(MemoryOSL4RelationPredicate.relatedTo.inverse == .relatedTo)
    #expect(MemoryOSL4RelationPredicate.relatedTo.isSymmetric)
    #expect(!MemoryOSL4RelationPredicate.relatedTo.isTransitive)
    #expect(!MemoryOSL4RelationPredicate.relatedTo.isStrict)
    #expect(MemoryOSL4RelationPredicate.relatedTo.retrievalWeight < MemoryOSL4RelationPredicate.subclassOf.retrievalWeight)
}

@Test func everyL4RelationPredicateHasDescriptionAndValidWeight() {
    for predicate in MemoryOSL4RelationPredicate.allCases {
        #expect(!predicate.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(predicate.retrievalWeight > 0)
        #expect(predicate.retrievalWeight <= 1)
    }
}
