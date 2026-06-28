import Foundation
import ConnorGraphCore

public struct MemoryOSL4RelationConstraint: Sendable, Equatable {
    public var predicate: MemoryOSL4RelationPredicate
    public var allowedSubjectTypes: Set<String>
    public var allowedObjectTypes: Set<String>
    public var notes: String

    public init(
        predicate: MemoryOSL4RelationPredicate,
        allowedSubjectTypes: Set<String> = [],
        allowedObjectTypes: Set<String> = [],
        notes: String = ""
    ) {
        self.predicate = predicate
        self.allowedSubjectTypes = allowedSubjectTypes
        self.allowedObjectTypes = allowedObjectTypes
        self.notes = notes
    }
}

public enum MemoryOSL4RelationConstraintRegistry {
    public static func constraint(for predicate: MemoryOSL4RelationPredicate) -> MemoryOSL4RelationConstraint {
        switch predicate {
        case .sameAs:
            return MemoryOSL4RelationConstraint(predicate: predicate, notes: "Identity relation; confidence and evidence are optional annotations, not validation gates.")
        case .instanceOf:
            return MemoryOSL4RelationConstraint(predicate: predicate, allowedObjectTypes: typeLikeConceptTypes)
        case .subclassOf:
            return MemoryOSL4RelationConstraint(predicate: predicate, allowedSubjectTypes: typeLikeConceptTypes, allowedObjectTypes: typeLikeConceptTypes)
        case .broaderThan, .narrowerThan:
            return MemoryOSL4RelationConstraint(predicate: predicate, allowedSubjectTypes: conceptLikeTypes, allowedObjectTypes: conceptLikeTypes)
        case .governs, .compliesWith, .violates:
            return MemoryOSL4RelationConstraint(predicate: predicate, notes: "Governance relation; at least one side should be rule/policy/standard/decision-like.")
        default:
            return MemoryOSL4RelationConstraint(predicate: predicate)
        }
    }

    private static let typeLikeConceptTypes: Set<String> = [
        MemoryOSEntityType.concept.rawValue,
        MemoryOSEntityType.role.rawValue,
        MemoryOSEntityType.framework.rawValue,
        MemoryOSEntityType.standard.rawValue
    ]

    private static let conceptLikeTypes: Set<String> = [
        MemoryOSEntityType.concept.rawValue,
        MemoryOSEntityType.framework.rawValue,
        MemoryOSEntityType.standard.rawValue,
        MemoryOSEntityType.theory.rawValue,
        MemoryOSEntityType.discipline.rawValue,
        MemoryOSEntityType.rule.rawValue
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

        // L4 is a relaxed entity graph layer. Confidence and evidence span references are
        // optional annotations produced by upstream extraction; they are not treated as
        // validation gates for whether a relation can participate in the L4 graph.
        _ = evidenceSpanIDs

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
        let normalized = MemoryOSEntityType.normalizeRawType(type)
        return allowed.contains(normalized)
    }

    private func compatibleIdentityTypes(_ lhs: String, _ rhs: String) -> Bool {
        MemoryOSEntityType.normalizeRawType(lhs) == MemoryOSEntityType.normalizeRawType(rhs)
    }

    private func isGovernanceLike(_ type: String) -> Bool {
        let normalized = MemoryOSEntityType.normalizeRawType(type)
        return [
            MemoryOSEntityType.decision.rawValue,
            MemoryOSEntityType.rule.rawValue,
            MemoryOSEntityType.standard.rawValue
        ].contains(normalized)
    }
}
