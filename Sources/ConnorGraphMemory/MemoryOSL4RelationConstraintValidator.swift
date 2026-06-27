import Foundation
import ConnorGraphCore

public struct MemoryOSL4RelationConstraint: Sendable, Equatable {
    public var predicate: MemoryOSL4RelationPredicate
    public var allowedSubjectTypes: Set<String>
    public var allowedObjectTypes: Set<String>
    public var minConfidence: Double
    public var requiresEvidence: Bool
    public var requiresMetadataKeys: Set<String>
    public var notes: String

    public init(
        predicate: MemoryOSL4RelationPredicate,
        allowedSubjectTypes: Set<String> = [],
        allowedObjectTypes: Set<String> = [],
        minConfidence: Double = 0.5,
        requiresEvidence: Bool = true,
        requiresMetadataKeys: Set<String> = [],
        notes: String = ""
    ) {
        self.predicate = predicate
        self.allowedSubjectTypes = allowedSubjectTypes
        self.allowedObjectTypes = allowedObjectTypes
        self.minConfidence = minConfidence
        self.requiresEvidence = requiresEvidence
        self.requiresMetadataKeys = requiresMetadataKeys
        self.notes = notes
    }
}

public enum MemoryOSL4RelationConstraintRegistry {
    public static func constraint(for predicate: MemoryOSL4RelationPredicate) -> MemoryOSL4RelationConstraint {
        switch predicate {
        case .sameAs:
            return MemoryOSL4RelationConstraint(predicate: predicate, minConfidence: 0.95, notes: "Strong identity relation; use only with high confidence and compatible entity types.")
        case .exactMatch, .equivalentTo:
            return MemoryOSL4RelationConstraint(predicate: predicate, minConfidence: 0.9)
        case .closeMatch:
            return MemoryOSL4RelationConstraint(predicate: predicate, minConfidence: 0.75)
        case .instanceOf:
            return MemoryOSL4RelationConstraint(predicate: predicate, allowedObjectTypes: typeLikeConceptTypes, minConfidence: 0.7)
        case .subclassOf:
            return MemoryOSL4RelationConstraint(predicate: predicate, allowedSubjectTypes: typeLikeConceptTypes, allowedObjectTypes: typeLikeConceptTypes, minConfidence: 0.75)
        case .broaderThan, .narrowerThan:
            return MemoryOSL4RelationConstraint(predicate: predicate, allowedSubjectTypes: conceptLikeTypes, allowedObjectTypes: conceptLikeTypes, minConfidence: 0.65)
        case .hasPart, .partOf:
            return MemoryOSL4RelationConstraint(predicate: predicate, minConfidence: 0.7)
        case .dependsOn, .requires:
            return MemoryOSL4RelationConstraint(predicate: predicate, minConfidence: 0.7)
        case .relatedTo, .associatedWith:
            return MemoryOSL4RelationConstraint(predicate: predicate, minConfidence: 0.5, requiresMetadataKeys: ["reason"], notes: "Weak fallback relation; require reason metadata.")
        case .causes, .risks, .mitigates, .influences:
            return MemoryOSL4RelationConstraint(predicate: predicate, minConfidence: 0.85, requiresMetadataKeys: ["causal_basis"], notes: "Causal/influence relation; require explicit causal basis metadata.")
        case .governs, .compliesWith, .violates:
            return MemoryOSL4RelationConstraint(predicate: predicate, minConfidence: 0.75, notes: "Governance relation; at least one side should be rule/policy/standard/decision-like.")
        default:
            return MemoryOSL4RelationConstraint(predicate: predicate, minConfidence: predicate.isStrict ? 0.65 : 0.5)
        }
    }

    private static let typeLikeConceptTypes: Set<String> = [
        "class", "type", "concept_type", "entity_type", "category", "taxonomy_class", "ontology_class", "kind", "role", "framework_type"
    ]

    private static let conceptLikeTypes: Set<String> = [
        "concept", "class", "type", "category", "framework", "standard", "principle", "pattern", "method", "theory", "domain", "knowledge_type"
    ]
}

public struct MemoryOSL4RelationConstraintValidator: Sendable {
    public init() {}

    public func validate(
        relation: MemoryOSExtractedConceptRelation,
        conceptEntities: [MemoryOSExtractedConceptEntity],
        evidenceSpanIDs: Set<String>
    ) -> [MemoryOSValidationIssue] {
        var issues: [MemoryOSValidationIssue] = []
        let entityByID = Dictionary(uniqueKeysWithValues: conceptEntities.map { ($0.localID, $0) })

        guard let subject = entityByID[relation.subjectLocalID] else {
            issues.append(MemoryOSValidationIssue(code: "unknown_relation_subject", message: "Concept relation references unknown subject: \(relation.subjectLocalID)."))
            return issues
        }
        guard let object = entityByID[relation.objectLocalID] else {
            issues.append(MemoryOSValidationIssue(code: "unknown_relation_object", message: "Concept relation references unknown object: \(relation.objectLocalID)."))
            return issues
        }

        let constraint = MemoryOSL4RelationConstraintRegistry.constraint(for: relation.predicate)

        if constraint.requiresEvidence && relation.evidenceSpanIDs.isEmpty {
            issues.append(MemoryOSValidationIssue(code: "missing_relation_evidence", message: "Concept relation requires evidence spans: \(relation.id)."))
        }
        for spanID in relation.evidenceSpanIDs where !evidenceSpanIDs.contains(spanID) {
            issues.append(MemoryOSValidationIssue(code: "unknown_evidence_span", message: "Concept relation references unknown evidence span: \(spanID)."))
        }

        if relation.confidence < constraint.minConfidence {
            issues.append(MemoryOSValidationIssue(code: "l4_relation_confidence_too_low", message: "L4 relation \(relation.id) uses \(relation.predicate.rawValue) with confidence \(relation.confidence), below required minimum \(constraint.minConfidence)."))
        }

        if relation.subjectLocalID == relation.objectLocalID && forbidsSelfLoop(relation.predicate) {
            issues.append(MemoryOSValidationIssue(code: "l4_relation_self_loop", message: "L4 relation \(relation.predicate.rawValue) must not point an entity to itself: \(relation.subjectLocalID)."))
        }

        if !constraint.allowedSubjectTypes.isEmpty && !matchesType(subject.conceptType, allowed: constraint.allowedSubjectTypes) {
            issues.append(MemoryOSValidationIssue(code: "l4_relation_subject_type_not_allowed", message: "L4 relation \(relation.predicate.rawValue) does not allow subject type \(subject.conceptType)."))
        }
        if !constraint.allowedObjectTypes.isEmpty && !matchesType(object.conceptType, allowed: constraint.allowedObjectTypes) {
            issues.append(MemoryOSValidationIssue(code: "l4_relation_object_type_not_allowed", message: "L4 relation \(relation.predicate.rawValue) does not allow object type \(object.conceptType)."))
        }

        if relation.predicate == .sameAs && !compatibleIdentityTypes(subject.conceptType, object.conceptType) {
            issues.append(MemoryOSValidationIssue(code: "l4_relation_incompatible_identity_types", message: "SAME_AS requires compatible concept/entity types, got \(subject.conceptType) and \(object.conceptType)."))
        }

        for key in constraint.requiresMetadataKeys where relation.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            issues.append(MemoryOSValidationIssue(code: "missing_l4_relation_metadata", message: "L4 relation \(relation.predicate.rawValue) requires metadata.\(key)."))
        }

        if [.governs, .compliesWith, .violates].contains(relation.predicate), !isGovernanceLike(subject.conceptType) && !isGovernanceLike(object.conceptType) {
            issues.append(MemoryOSValidationIssue(code: "l4_relation_governance_type_required", message: "Governance relations require at least one decision/rule/policy/standard-like endpoint."))
        }

        return issues
    }

    private func forbidsSelfLoop(_ predicate: MemoryOSL4RelationPredicate) -> Bool {
        switch predicate {
        case .instanceOf, .subclassOf, .hasPart, .partOf, .dependsOn, .requires:
            return true
        default:
            return false
        }
    }

    private func matchesType(_ type: String, allowed: Set<String>) -> Bool {
        let normalized = normalizeType(type)
        if allowed.contains(normalized) { return true }
        return allowed.contains { normalized.contains($0) || $0.contains(normalized) }
    }

    private func compatibleIdentityTypes(_ lhs: String, _ rhs: String) -> Bool {
        normalizeType(lhs) == normalizeType(rhs)
    }

    private func isGovernanceLike(_ type: String) -> Bool {
        let normalized = normalizeType(type)
        return ["decision", "rule", "policy", "standard", "constraint", "requirement", "sop", "runbook"].contains { normalized.contains($0) }
    }

    private func normalizeType(_ type: String) -> String {
        type.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
