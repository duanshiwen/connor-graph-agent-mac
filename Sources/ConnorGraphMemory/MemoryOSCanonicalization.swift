import Foundation
import ConnorGraphCore

public struct MemoryOSCanonicalizationResult<T: Sendable & Equatable>: Sendable, Equatable {
    public var value: T
    public var issues: [MemoryOSValidationIssue]
    public var acceptanceMode: MemoryOSAcceptanceMode

    public init(value: T, issues: [MemoryOSValidationIssue] = [], acceptanceMode: MemoryOSAcceptanceMode = .strictAccepted) {
        self.value = value
        self.issues = issues
        self.acceptanceMode = acceptanceMode
    }
}

public struct MemoryOSL4PredicateCanonicalization: Sendable, Equatable {
    public var predicate: MemoryOSL4RelationPredicate
    public var metadata: [String: String]

    public init(predicate: MemoryOSL4RelationPredicate, metadata: [String: String] = [:]) {
        self.predicate = predicate
        self.metadata = metadata
    }
}

public enum MemoryOSCanonicalizer {
    public static let allowedL2FactTypes: Set<String> = [
        "profile_preference",
        "project_state",
        "task_commitment",
        "calendar_time",
        "communication",
        "source_document",
        "decision",
        "implementation",
        "environment_config",
        "relationship",
        "other"
    ]

    public static func canonicalizeL2FactType(_ raw: String?) -> String? {
        guard let value = raw?.nilIfBlank else { return nil }
        let normalized = value.lowercased()
        return allowedL2FactTypes.contains(normalized) ? normalized : nil
    }

    public static func canonicalizeL2Relation(_ raw: String?) -> String {
        guard let value = raw?.nilIfBlank else { return GraphPredicate.relatedTo.rawValue }
        let normalized = normalizedEnumCandidate(value)
        return GraphPredicate(rawValue: normalized)?.rawValue ?? GraphPredicate.relatedTo.rawValue
    }

    public static func canonicalizeGraphPredicate(_ raw: String?) -> GraphPredicate? {
        guard let value = raw?.nilIfBlank else { return nil }
        let normalized = normalizedEnumCandidate(value)
        return GraphPredicate(rawValue: normalized)
    }

    public static func canonicalizeL4Predicate(_ raw: String) -> MemoryOSCanonicalizationResult<MemoryOSL4PredicateCanonicalization> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = MemoryOSL4RelationPredicate(rawValue: trimmed) {
            return MemoryOSCanonicalizationResult(value: MemoryOSL4PredicateCanonicalization(predicate: exact))
        }

        let normalized = normalizedEnumCandidate(trimmed)
        if let exactNormalized = MemoryOSL4RelationPredicate(rawValue: normalized) {
            return MemoryOSCanonicalizationResult(
                value: MemoryOSL4PredicateCanonicalization(
                    predicate: exactNormalized,
                    metadata: normalized == trimmed ? [:] : [
                        "alias_predicate": trimmed,
                        "normalized_predicate": exactNormalized.rawValue,
                        "normalization_strategy": "separator_variant"
                    ]
                ),
                issues: normalized == trimmed ? [] : [
                    MemoryOSValidationIssue(
                        code: "separator_variant",
                        message: "Normalized L4 predicate \(trimmed) to \(exactNormalized.rawValue).",
                        severity: MemoryOSIssueSeverity.informational.rawValue,
                        scope: "relation",
                        disposition: MemoryOSIssueDisposition.normalizeAndKeep.rawValue,
                        recordReference: trimmed
                    )
                ],
                acceptanceMode: normalized == trimmed ? .strictAccepted : .normalizedAccepted
            )
        }

        if let alias = aliasMapping(for: normalized, raw: trimmed) {
            return alias
        }

        return MemoryOSCanonicalizationResult(
            value: MemoryOSL4PredicateCanonicalization(
                predicate: .relatedTo,
                metadata: [
                    "alias_predicate": trimmed,
                    "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                    "semantic_family": "unknown",
                    "normalization_strategy": "fallback"
                ]
            ),
            issues: [
                MemoryOSValidationIssue(
                    code: "unknown_l4_predicate_fallback",
                    message: "Fell back unknown L4 predicate \(trimmed) to RELATED_TO.",
                    severity: MemoryOSIssueSeverity.warning.rawValue,
                    scope: "relation",
                    disposition: MemoryOSIssueDisposition.repairAndKeep.rawValue,
                    recordReference: trimmed,
                    repairHint: "Prefer controlled MemoryOSL4RelationPredicate raw values when possible."
                )
            ],
            acceptanceMode: .degradedAccepted
        )
    }

    private static func normalizedEnumCandidate(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased()
    }

    private static func aliasMapping(for normalized: String, raw: String) -> MemoryOSCanonicalizationResult<MemoryOSL4PredicateCanonicalization>? {
        let base: [String: String] = [
            "alias_predicate": raw,
            "normalization_source": normalized
        ]

        func semanticAlias(_ predicate: MemoryOSL4RelationPredicate, metadata: [String: String]) -> MemoryOSCanonicalizationResult<MemoryOSL4PredicateCanonicalization> {
            let merged = base.merging(metadata) { _, new in new }
            return MemoryOSCanonicalizationResult(
                value: MemoryOSL4PredicateCanonicalization(predicate: predicate, metadata: merged),
                issues: [
                    MemoryOSValidationIssue(
                        code: "semantic_alias_normalized",
                        message: "Normalized L4 predicate \(raw) to \(predicate.rawValue).",
                        severity: MemoryOSIssueSeverity.informational.rawValue,
                        scope: "relation",
                        disposition: MemoryOSIssueDisposition.normalizeAndKeep.rawValue,
                        recordReference: raw
                    )
                ],
                acceptanceMode: predicate == .relatedTo ? .degradedAccepted : .normalizedAccepted
            )
        }

        switch normalized {
        case "FAMILY_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "family",
                "normalization_strategy": "semantic_alias"
            ])
        case "SIBLING_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "sibling",
                "normalization_strategy": "semantic_alias"
            ])
        case "BROTHER_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "sibling",
                "kinship_subrole": "brother",
                "normalization_strategy": "semantic_alias"
            ])
        case "SISTER_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "sibling",
                "kinship_subrole": "sister",
                "normalization_strategy": "semantic_alias"
            ])
        case "PARENT_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "parent",
                "normalization_strategy": "semantic_alias"
            ])
        case "MOTHER_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "parent",
                "kinship_subrole": "mother",
                "normalization_strategy": "semantic_alias"
            ])
        case "FATHER_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "parent",
                "kinship_subrole": "father",
                "normalization_strategy": "semantic_alias"
            ])
        case "CHILD_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "child",
                "normalization_strategy": "semantic_alias"
            ])
        case "SON_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "child",
                "kinship_subrole": "son",
                "normalization_strategy": "semantic_alias"
            ])
        case "DAUGHTER_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "child",
                "kinship_subrole": "daughter",
                "normalization_strategy": "semantic_alias"
            ])
        case "SPOUSE_OF", "HUSBAND_OF", "WIFE_OF":
            var metadata: [String: String] = [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "spouse",
                "normalization_strategy": "semantic_alias"
            ]
            if normalized == "HUSBAND_OF" { metadata["kinship_subrole"] = "husband" }
            if normalized == "WIFE_OF" { metadata["kinship_subrole"] = "wife" }
            return semanticAlias(.relatedTo, metadata: metadata)
        case "RELATIVE_OF", "KIN_OF":
            return semanticAlias(.relatedTo, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.relatedTo.rawValue,
                "semantic_family": "kinship",
                "kinship_role": "relative",
                "normalization_strategy": "semantic_alias"
            ])
        case "WRITTEN_BY", "AUTHOR_OF":
            return semanticAlias(.authoredBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.authoredBy.rawValue,
                "semantic_family": "authorship",
                "normalized_direction": normalized == "AUTHOR_OF" ? "inverted" : "same",
                "normalization_strategy": "semantic_alias"
            ])
        case "BUILT_BY", "MADE_BY", "CREATOR_OF", "MAKER_OF":
            return semanticAlias(.createdBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.createdBy.rawValue,
                "semantic_family": "creation",
                "normalized_direction": ["CREATOR_OF", "MAKER_OF"].contains(normalized) ? "inverted" : "same",
                "normalization_strategy": "semantic_alias"
            ])
        case "IMPLEMENTED_BY", "DEVELOPER_OF":
            return semanticAlias(.developedBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.developedBy.rawValue,
                "semantic_family": "development",
                "normalized_direction": normalized == "DEVELOPER_OF" ? "inverted" : "same",
                "normalization_strategy": "semantic_alias"
            ])
        case "OWNER_OF":
            return semanticAlias(.ownedBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.ownedBy.rawValue,
                "semantic_family": "ownership",
                "normalized_direction": "inverted",
                "normalization_strategy": "semantic_alias"
            ])
        case "MAINTAINER_OF":
            return semanticAlias(.maintainedBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.maintainedBy.rawValue,
                "semantic_family": "maintenance",
                "normalized_direction": "inverted",
                "normalization_strategy": "semantic_alias"
            ])
        case "PUBLISHER_OF":
            return semanticAlias(.publishedBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.publishedBy.rawValue,
                "semantic_family": "publication",
                "normalized_direction": "inverted",
                "normalization_strategy": "semantic_alias"
            ])
        case "CURATOR_OF":
            return semanticAlias(.curatedBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.curatedBy.rawValue,
                "semantic_family": "curation",
                "normalized_direction": "inverted",
                "normalization_strategy": "semantic_alias"
            ])
        case "REVIEWER_OF":
            return semanticAlias(.reviewedBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.reviewedBy.rawValue,
                "semantic_family": "review",
                "normalized_direction": "inverted",
                "normalization_strategy": "semantic_alias"
            ])
        case "CONTRIBUTOR_OF":
            return semanticAlias(.contributedBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.contributedBy.rawValue,
                "semantic_family": "contribution",
                "normalized_direction": "inverted",
                "normalization_strategy": "semantic_alias"
            ])
        case "FOUNDER_OF":
            return semanticAlias(.foundedBy, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.foundedBy.rawValue,
                "semantic_family": "founding",
                "normalized_direction": "inverted",
                "normalization_strategy": "semantic_alias"
            ])
        case "STAKEHOLDER_IN":
            return semanticAlias(.stakeholderOf, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.stakeholderOf.rawValue,
                "semantic_family": "stakeholder",
                "normalization_strategy": "semantic_alias"
            ])
        case "WORKING_ON":
            return semanticAlias(.worksOn, metadata: [
                "normalized_predicate": MemoryOSL4RelationPredicate.worksOn.rawValue,
                "semantic_family": "work",
                "normalization_strategy": "semantic_alias"
            ])
        default:
            return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
