import Foundation
import ConnorGraphCore

public struct MemoryOSKnowledgePromotionPolicy: Sendable {
    public init() {}

    public func evaluate(_ candidate: MemoryOSKnowledgeCandidate) -> MemoryOSKnowledgePromotionDecision {
        var rejected: [MemoryOSKnowledgeSignalDimension] = []
        let assessment = candidate.signalAssessment

        if !assessment.signalQualityAccepted { rejected.append(.signalQuality) }
        if !assessment.reuseScopeAccepted { rejected.append(.reuseScope) }
        if !assessment.noveltyAccepted { rejected.append(.novelty) }
        if !assessment.structurabilityAccepted { rejected.append(.structurability) }

        if !hasRequiredStructure(candidate) && !rejected.contains(.structurability) {
            rejected.append(.structurability)
        }

        return MemoryOSKnowledgePromotionDecision(
            candidateID: candidate.id,
            accepted: rejected.isEmpty,
            rejectedDimensions: rejected,
            reasons: assessment.reasons
        )
    }

    public func makeKnowledgeBelief(
        from candidate: MemoryOSKnowledgeCandidate,
        decision: MemoryOSKnowledgePromotionDecision? = nil,
        sourceArtifactID: String? = nil,
        now: Date = Date()
    ) -> MemoryOSBelief? {
        let resolvedDecision = decision ?? evaluate(candidate)
        guard resolvedDecision.accepted else { return nil }
        guard hasRequiredStructure(candidate) else { return nil }
        guard !candidate.evidenceStatementIDs.isEmpty else { return nil }

        var metadata = candidate.metadata
        metadata["category"] = candidate.category
        metadata["knowledge_type"] = candidate.knowledgeType
        metadata["scope"] = candidate.scope
        metadata["domain"] = candidate.domain
        metadata["work_object_id"] = candidate.workObjectID
        metadata["related_entity_ids"] = candidate.relatedEntityIDs.joined(separator: ",")
        metadata["evidence_span_ids"] = candidate.evidenceSpanIDs.joined(separator: ",")
        metadata["projection_reason"] = "knowledge_promotion_policy_accepted"
        metadata["signal_quality_accepted"] = String(candidate.signalAssessment.signalQualityAccepted)
        metadata["reuse_scope_accepted"] = String(candidate.signalAssessment.reuseScopeAccepted)
        metadata["novelty_accepted"] = String(candidate.signalAssessment.noveltyAccepted)
        metadata["structurability_accepted"] = String(candidate.signalAssessment.structurabilityAccepted)

        return MemoryOSBelief(
            id: "l3-knowledge:\(candidate.id)",
            topic: knowledgeTopic(for: candidate),
            statement: candidate.claim,
            projectionKind: .summarized,
            confidence: candidate.confidence,
            evidenceStatementIDs: candidate.evidenceStatementIDs,
            validAt: now,
            projectedAt: now,
            sourceArtifactID: sourceArtifactID,
            metadata: metadata
        )
    }

    private func hasRequiredStructure(_ candidate: MemoryOSKnowledgeCandidate) -> Bool {
        !isBlank(candidate.category) &&
        !isBlank(candidate.knowledgeType) &&
        !isBlank(candidate.scope) &&
        !isBlank(candidate.domain)
    }

    private func knowledgeTopic(for candidate: MemoryOSKnowledgeCandidate) -> String {
        let domain = normalized(candidate.domain) ?? "general"
        let type = normalized(candidate.knowledgeType) ?? "knowledge"
        return "\(domain):\(type)"
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isBlank(_ value: String?) -> Bool {
        normalized(value) == nil
    }
}
