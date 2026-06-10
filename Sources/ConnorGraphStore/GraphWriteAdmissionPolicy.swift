import Foundation
import ConnorGraphCore

public enum GraphWriteAdmissionDecisionAction: String, Codable, Sendable, Equatable {
    case autoCommit = "auto_commit"
    case hold
    case askUser = "ask_user"
    case discard
}

public enum GraphWriteAdmissionReason: String, Codable, Sendable, Equatable {
    case emptyDraft = "empty_draft"
    case lowEntityConfidence = "low_entity_confidence"
    case lowStatementConfidence = "low_statement_confidence"
    case missingStatementEvidence = "missing_statement_evidence"
    case potentialDuplicateEntity = "potential_duplicate_entity"
    case statementConflict = "statement_conflict"
    case sensitivePersonalMemory = "sensitive_personal_memory"
    case highConfidenceEvidenceBacked = "high_confidence_evidence_backed"
}

public struct GraphWriteAdmissionDecision: Sendable, Equatable {
    public var action: GraphWriteAdmissionDecisionAction
    public var reasons: [GraphWriteAdmissionReason]
    public var message: String

    public init(action: GraphWriteAdmissionDecisionAction, reasons: [GraphWriteAdmissionReason] = [], message: String = "") {
        self.action = action
        self.reasons = reasons
        self.message = message
    }

    public var shouldCommit: Bool { action == .autoCommit }
}

public struct GraphWriteAdmissionPolicy: Sendable {
    public var minimumAutoCommitEntityConfidence: Double
    public var minimumAutoCommitStatementConfidence: Double
    public var requireStatementEvidence: Bool
    public var askUserForSensitivePersonalMemory: Bool

    public init(
        minimumAutoCommitEntityConfidence: Double = 0.65,
        minimumAutoCommitStatementConfidence: Double = 0.70,
        requireStatementEvidence: Bool = true,
        askUserForSensitivePersonalMemory: Bool = false
    ) {
        self.minimumAutoCommitEntityConfidence = minimumAutoCommitEntityConfidence
        self.minimumAutoCommitStatementConfidence = minimumAutoCommitStatementConfidence
        self.requireStatementEvidence = requireStatementEvidence
        self.askUserForSensitivePersonalMemory = askUserForSensitivePersonalMemory
    }

    public func decide(draft: GraphExtractionDraft, resolver: SQLiteGraphEntityResolver? = nil) throws -> GraphWriteAdmissionDecision {
        let resolutionPlan = try resolver.map { try GraphEntityResolutionPlanner(resolver: $0).plan(for: draft) }
        return try decide(draft: draft, resolutionPlan: resolutionPlan, conflictPreview: nil)
    }

    public func decide(
        draft: GraphExtractionDraft,
        resolutionPlan: GraphEntityResolutionPlan?,
        conflictPreview: GraphExtractionConflictPreview? = nil
    ) throws -> GraphWriteAdmissionDecision {
        guard !draft.entities.isEmpty || !draft.statements.isEmpty else {
            return GraphWriteAdmissionDecision(action: .discard, reasons: [.emptyDraft], message: "Extraction produced no graph candidates.")
        }

        var holdReasons: [GraphWriteAdmissionReason] = []
        var askReasons: [GraphWriteAdmissionReason] = []

        for entity in draft.entities {
            if entity.confidence < minimumAutoCommitEntityConfidence {
                holdReasons.append(.lowEntityConfidence)
            }
            if askUserForSensitivePersonalMemory, entity.scope == .personal, isSensitive(entity: entity) {
                askReasons.append(.sensitivePersonalMemory)
            }
        }

        if resolutionPlan?.hasPotentialDuplicates == true {
            holdReasons.append(.potentialDuplicateEntity)
        }
        if conflictPreview?.hasConflicts == true {
            askReasons.append(.statementConflict)
        }

        for statement in draft.statements {
            if statement.confidence < minimumAutoCommitStatementConfidence {
                holdReasons.append(.lowStatementConfidence)
            }
            if requireStatementEvidence, !hasEvidence(statement: statement) {
                holdReasons.append(.missingStatementEvidence)
            }
        }

        let uniqueAskReasons = uniqued(askReasons)
        if !uniqueAskReasons.isEmpty {
            return GraphWriteAdmissionDecision(
                action: .askUser,
                reasons: uniqueAskReasons,
                message: uniqueAskReasons.contains(.statementConflict)
                    ? "Candidate graph write conflicts with active memory and requires user or system resolution."
                    : "Candidate graph write affects sensitive personal memory and should ask the user only when needed."
            )
        }

        let uniqueHoldReasons = uniqued(holdReasons)
        if !uniqueHoldReasons.isEmpty {
            return GraphWriteAdmissionDecision(
                action: .hold,
                reasons: uniqueHoldReasons,
                message: "Candidate graph write was held by system admission policy."
            )
        }

        return GraphWriteAdmissionDecision(
            action: .autoCommit,
            reasons: [.highConfidenceEvidenceBacked],
            message: "Candidate graph write passed system admission policy."
        )
    }

    private func hasEvidence(statement: GraphExtractedStatementDraft) -> Bool {
        if statement.metadata["evidence_span_ids"]?.isEmpty == false { return true }
        if statement.metadata["evidence_spans_json"]?.isEmpty == false { return true }
        if statement.metadata["evidence_text"]?.isEmpty == false { return true }
        return false
    }

    private func isSensitive(entity: GraphExtractedEntityDraft) -> Bool {
        let text = ([entity.name, entity.summary] + entity.aliases + Array(entity.metadata.values))
            .joined(separator: " ")
            .lowercased()
        let markers = [
            "password", "secret", "token", "api key", "credential",
            "health", "medical", "diagnosis", "finance", "bank",
            "身份证", "护照", "密码", "密钥", "token", "健康", "医疗", "银行", "银行卡"
        ]
        return markers.contains { text.contains($0) }
    }

    private func uniqued(_ reasons: [GraphWriteAdmissionReason]) -> [GraphWriteAdmissionReason] {
        var seen = Set<GraphWriteAdmissionReason>()
        var result: [GraphWriteAdmissionReason] = []
        for reason in reasons where !seen.contains(reason) {
            seen.insert(reason)
            result.append(reason)
        }
        return result
    }
}
