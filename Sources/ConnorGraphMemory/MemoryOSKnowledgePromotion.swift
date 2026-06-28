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

        return MemoryOSBelief(
            id: "l3-knowledge:\(candidate.id)",
            statement: candidate.claim,
            domain: MemoryOSBelief.normalizedDisciplineDomain(candidate.domain),
            relatedObjectNames: candidate.metadata["related_object_names"] ?? "",
            createdAt: now,
            updatedAt: now
        )
    }

    private func hasRequiredStructure(_ candidate: MemoryOSKnowledgeCandidate) -> Bool {
        !isBlank(candidate.claim) &&
        !isBlank(candidate.domain)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isBlank(_ value: String?) -> Bool {
        normalized(value) == nil
    }
}
