import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory

@Test func familyOfCanonicalizesToRelatedToWithKinshipMetadata() {
    let result = MemoryOSCanonicalizer.canonicalizeL4Predicate("FAMILY_OF")

    #expect(result.value.predicate == .relatedTo)
    #expect(result.value.metadata["semantic_family"] == "kinship")
    #expect(result.value.metadata["kinship_role"] == "family")
    #expect(result.acceptanceMode == .degradedAccepted)
}

@Test func writtenByCanonicalizesToAuthoredBy() {
    let result = MemoryOSCanonicalizer.canonicalizeL4Predicate("WRITTEN_BY")

    #expect(result.value.predicate == .authoredBy)
    #expect(result.value.metadata["semantic_family"] == "authorship")
    #expect(result.acceptanceMode == .normalizedAccepted)
}

@Test func separatorVariantCanonicalizesToControlledPredicate() {
    let result = MemoryOSCanonicalizer.canonicalizeL4Predicate("created by")

    #expect(result.value.predicate == .createdBy)
    #expect(result.value.metadata["normalization_strategy"] == "separator_variant")
    #expect(result.acceptanceMode == .normalizedAccepted)
}

@Test func unknownL4PredicateFallsBackToRelatedTo() {
    let result = MemoryOSCanonicalizer.canonicalizeL4Predicate("TOTALLY_UNKNOWN_RELATION")

    #expect(result.value.predicate == .relatedTo)
    #expect(result.value.metadata["normalization_strategy"] == "fallback")
    #expect(result.acceptanceMode == .degradedAccepted)
}

@Test func l2RelationCanonicalizesCaseAndSeparatorVariants() {
    #expect(MemoryOSCanonicalizer.canonicalizeL2Relation("related_to") == GraphPredicate.relatedTo.rawValue)
    #expect(MemoryOSCanonicalizer.canonicalizeL2Relation("related to") == GraphPredicate.relatedTo.rawValue)
    #expect(MemoryOSCanonicalizer.canonicalizeL2Relation(nil) == GraphPredicate.relatedTo.rawValue)
}

@Test func l2FactTypeCanonicalizesLowercaseAndRejectsUnknown() {
    #expect(MemoryOSCanonicalizer.canonicalizeL2FactType("PROFILE_PREFERENCE") == "profile_preference")
    #expect(MemoryOSCanonicalizer.canonicalizeL2FactType("relationship") == "relationship")
    #expect(MemoryOSCanonicalizer.canonicalizeL2FactType("not_real") == nil)
}

@Test func graphPredicateCanonicalizerReturnsControlledPredicate() {
    #expect(MemoryOSCanonicalizer.canonicalizeGraphPredicate("prefers") == .prefers)
    #expect(MemoryOSCanonicalizer.canonicalizeGraphPredicate("has goal") == .hasGoal)
    #expect(MemoryOSCanonicalizer.canonicalizeGraphPredicate("unknown") == nil)
}
