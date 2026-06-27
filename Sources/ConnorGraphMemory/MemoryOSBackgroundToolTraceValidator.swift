import Foundation
import ConnorGraphCore

public enum MemoryOSBackgroundToolTraceValidationMode: String, Codable, Sendable, Equatable {
    case warning
    case hardReject
}

public struct MemoryOSBackgroundToolTraceValidationResult: Sendable, Codable, Equatable {
    public var accepted: Bool
    public var issues: [MemoryOSValidationIssue]

    public init(accepted: Bool, issues: [MemoryOSValidationIssue]) {
        self.accepted = accepted
        self.issues = issues
    }
}

public struct MemoryOSBackgroundToolTraceValidator: Sendable {
    public var mode: MemoryOSBackgroundToolTraceValidationMode

    public init(mode: MemoryOSBackgroundToolTraceValidationMode = .warning) {
        self.mode = mode
    }

    public func validate(
        schemaName: String,
        rawArtifactJSON: String,
        toolCalls: [MemoryOSBackgroundToolCallRecord]
    ) -> MemoryOSBackgroundToolTraceValidationResult {
        let issues = issuesFor(schemaName: schemaName, rawArtifactJSON: rawArtifactJSON, toolCalls: toolCalls)
        let hasErrors = issues.contains { $0.severity == "error" }
        return MemoryOSBackgroundToolTraceValidationResult(accepted: !hasErrors, issues: issues)
    }

    private func issuesFor(schemaName: String, rawArtifactJSON: String, toolCalls: [MemoryOSBackgroundToolCallRecord]) -> [MemoryOSValidationIssue] {
        guard let data = rawArtifactJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else {
            return [issue(code: "tool_trace_artifact_json_unreadable", message: "Cannot inspect artifact JSON for tool trace requirements.", severity: modeSeverity)]
        }

        let succeededToolNames = Set(toolCalls.filter { $0.status == .succeeded }.map(\.toolName))
        var issues: [MemoryOSValidationIssue] = []

        if schemaName == "MemoryOSL1UnifiedProjectionOutput" {
            let hasKnowledge = nonEmptyArray(dict["knowledgeCandidates"])
            let hasConceptEntities = nonEmptyArray(dict["conceptEntities"])
            let hasConceptRelations = nonEmptyArray(dict["conceptRelations"])
            if (hasKnowledge || hasConceptEntities || hasConceptRelations), !succeededToolNames.contains("memory_os_search") {
                issues.append(issue(code: "missing_l1_knowledge_search_trace", message: "L1->Knowledge artifact emits L3/L4 knowledge outputs without a successful memory_os_search trace.", severity: modeSeverity))
            }
            if containsProfileOrPersonFacts(dict), !succeededToolNames.contains("memory_os_read_provenance") {
                issues.append(issue(code: "missing_l1_person_provenance_trace", message: "L1->Knowledge artifact appears to emit person/profile facts without a successful memory_os_read_provenance trace.", severity: modeSeverity))
            }
        }

        if schemaName == "MemoryOSKnowledgeExtractionOutput" {
            let hasAcceptedKnowledge = acceptedKnowledgeCandidateCount(dict) > 0
            if hasAcceptedKnowledge, !succeededToolNames.contains("memory_os_search") {
                issues.append(issue(code: "missing_l2_knowledge_search_trace", message: "L2->Knowledge artifact accepts L3 knowledge without a successful memory_os_search trace.", severity: modeSeverity))
            }
            if nonEmptyArray(dict["conceptRelations"]), !(succeededToolNames.contains("memory_os_expand_l4") || succeededToolNames.contains("memory_os_l4_find_entity") || succeededToolNames.contains("memory_os_l4_neighbors")) {
                issues.append(issue(code: "missing_l4_relation_trace", message: "Knowledge artifact emits L4 relations without successful L4 graph lookup/expansion trace.", severity: modeSeverity))
            }
            if containsHighRiskL4Relation(dict), !succeededToolNames.contains("memory_os_search") {
                issues.append(issue(code: "missing_high_risk_l4_relation_search_trace", message: "Knowledge artifact emits high-risk L4 relation predicates without a successful memory_os_search trace.", severity: modeSeverity))
            }
        }

        return issues
    }

    private var modeSeverity: String {
        mode == .hardReject ? "error" : "warning"
    }

    private func nonEmptyArray(_ value: Any?) -> Bool {
        guard let array = value as? [Any] else { return false }
        return !array.isEmpty
    }

    private func acceptedKnowledgeCandidateCount(_ dict: [String: Any]) -> Int {
        guard let candidates = dict["knowledgeCandidates"] as? [[String: Any]] else { return 0 }
        return candidates.filter { candidate in
            if let status = candidate["status"] as? String { return status == "accepted" }
            if let decision = candidate["decision"] as? String { return decision == "accept" || decision == "accepted" }
            if let assessment = candidate["signalAssessment"] as? [String: Any] {
                let bools = ["signalQualityAccepted", "reuseScopeAccepted", "noveltyAccepted", "structurabilityAccepted"]
                return bools.allSatisfy { assessment[$0] as? Bool == true }
            }
            return false
        }.count
    }

    private func containsHighRiskL4Relation(_ dict: [String: Any]) -> Bool {
        guard let relations = dict["conceptRelations"] as? [[String: Any]] else { return false }
        let highRisk: Set<String> = [
            MemoryOSL4RelationPredicate.sameAs.rawValue,
            MemoryOSL4RelationPredicate.equivalentTo.rawValue,
            MemoryOSL4RelationPredicate.exactMatch.rawValue,
            MemoryOSL4RelationPredicate.causes.rawValue,
            MemoryOSL4RelationPredicate.risks.rawValue,
            MemoryOSL4RelationPredicate.supersedes.rawValue,
            MemoryOSL4RelationPredicate.deprecates.rawValue
        ]
        return relations.contains { relation in
            guard let predicate = relation["predicate"] as? String else { return false }
            return highRisk.contains(predicate)
        }
    }

    private func containsProfileOrPersonFacts(_ dict: [String: Any]) -> Bool {
        let sections = ["operationalStatements", "knowledgeCandidates", "conceptEntities"]
        return sections.contains { key in
            guard let values = dict[key] as? [Any] else { return false }
            return values.contains { value in
                let string = String(describing: value).lowercased()
                return string.contains("current_user") || string.contains("profile") || string.contains("person_role") || string.contains("preference")
            }
        }
    }

    private func issue(code: String, message: String, severity: String) -> MemoryOSValidationIssue {
        MemoryOSValidationIssue(code: code, message: message, severity: severity)
    }
}
