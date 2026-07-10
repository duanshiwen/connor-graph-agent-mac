import Foundation
import CryptoKit
import ConnorGraphCore

public struct MemoryOSPreIngestionDecision: Sendable, Equatable {
    public enum Action: Sendable, Equatable { case archive, discard }
    public var action: Action
    public var reason: String
    public var confidence: Double

    public init(action: Action, reason: String, confidence: Double) {
        self.action = action
        self.reason = reason
        self.confidence = confidence
    }
}

public struct MemoryOSPreIngestionFilter: Sendable {
    public init() {}

    public func decide(content: String, sourceType: MemoryOSSourceType) -> MemoryOSPreIngestionDecision {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return MemoryOSPreIngestionDecision(action: .discard, reason: "empty_content", confidence: 1.0)
        }
        return MemoryOSPreIngestionDecision(action: .archive, reason: "archive_by_default_with_evidence", confidence: 0.8)
    }
}

public struct MemoryOSIngestionInput: Sendable, Equatable {
    public var sourceType: MemoryOSSourceType
    public var sourceID: String?
    public var title: String
    public var content: String
    public var occurredAt: Date
    public var sessionID: String?
    public var workObjectID: String?
    public var metadata: [String: String]

    public init(sourceType: MemoryOSSourceType, sourceID: String? = nil, title: String, content: String, occurredAt: Date = Date(), sessionID: String? = nil, workObjectID: String? = nil, metadata: [String: String] = [:]) {
        self.sourceType = sourceType; self.sourceID = sourceID; self.title = title; self.content = content; self.occurredAt = occurredAt; self.sessionID = sessionID; self.workObjectID = workObjectID; self.metadata = metadata
    }
}

public struct MemoryOSIngestionResult: Sendable, Equatable {
    public var decision: MemoryOSPreIngestionDecision
    public var provenanceObject: MemoryOSProvenanceObject?
    public var span: MemoryOSProvenanceSpan?
    public var captureEvent: MemoryOSCaptureEvent?
}

public struct MemoryOSIngestionService: Sendable {
    public var filter: MemoryOSPreIngestionFilter

    public init(filter: MemoryOSPreIngestionFilter = MemoryOSPreIngestionFilter()) {
        self.filter = filter
    }

    public func ingest(_ input: MemoryOSIngestionInput, now: Date = Date()) -> MemoryOSIngestionResult {
        let decision = filter.decide(content: input.content, sourceType: input.sourceType)
        guard decision.action == .archive else {
            return MemoryOSIngestionResult(decision: decision, provenanceObject: nil, span: nil, captureEvent: nil)
        }
        let hash = SHA256.hash(data: Data(input.content.utf8)).map { String(format: "%02x", $0) }.joined()
        let object = MemoryOSProvenanceObject(sourceType: input.sourceType, sourceID: input.sourceID, title: input.title, content: input.content, contentHash: hash, occurredAt: input.occurredAt, ingestedAt: now, sessionID: input.sessionID, workObjectID: input.workObjectID, metadata: input.metadata)
        let span = MemoryOSProvenanceSpan(provenanceObjectID: object.id, startOffset: 0, endOffset: input.content.count, text: input.content, metadata: input.metadata)
        let contentPreview = input.content.count > 200 ? String(input.content.prefix(200)) + "..." : input.content
        let event = MemoryOSCaptureEvent(provenanceObjectID: object.id, eventType: input.sourceType.rawValue, occurredAt: input.occurredAt, tokenEstimate: max(1, input.content.count / 4), metadata: input.metadata.merging(["span_id": span.id, "content_preview": contentPreview, "title": input.title]) { current, _ in current })
        return MemoryOSIngestionResult(decision: decision, provenanceObject: object, span: span, captureEvent: event)
    }
}

public struct MemoryOSTimeBlockBuilder: Sendable {
    public var hardTokenLimit: Int
    public var targetTokenLimit: Int

    public init(targetTokenLimit: Int = 60_000, hardTokenLimit: Int = 80_000) {
        self.targetTokenLimit = targetTokenLimit
        self.hardTokenLimit = hardTokenLimit
    }

    public func buildBlocks(from events: [MemoryOSCaptureEvent]) -> [MemoryOSTimeBlock] {
        let sorted = events.sorted { $0.occurredAt < $1.occurredAt }
        var blocks: [MemoryOSTimeBlock] = []
        var bucket: [MemoryOSCaptureEvent] = []
        var tokenCount = 0

        func flush() {
            guard let first = bucket.first, let last = bucket.last else { return }
            blocks.append(MemoryOSTimeBlock(title: "Memory block \(first.id.prefix(8))", startedAt: first.occurredAt, endedAt: last.occurredAt, tokenEstimate: tokenCount, metadata: ["event_count": "\(bucket.count)"]))
            bucket.removeAll(); tokenCount = 0
        }

        for event in sorted {
            if let last = bucket.last {
                let crossesDay = !Calendar(identifier: .gregorian).isDate(last.occurredAt, inSameDayAs: event.occurredAt)
                let gap = event.occurredAt.timeIntervalSince(last.occurredAt)
                if crossesDay || gap > 3 * 60 * 60 || tokenCount + event.tokenEstimate > hardTokenLimit {
                    flush()
                }
            }
            bucket.append(event)
            tokenCount += event.tokenEstimate
            if tokenCount >= targetTokenLimit { flush() }
        }
        flush()
        return blocks
    }
}

public struct MemoryOSArtifactEnvelopeService: Sendable {
    public init() {}

    public func envelope(rawContent: String, artifactType: String = "graph_structured_extraction", schemaName: String = "GraphStructuredExtractionOutput", schemaVersion: Int = 1, modelID: String, queueItemID: String? = nil, processingRunID: String? = nil, metadata: [String: String] = [:], now: Date = Date()) -> MemoryOSLLMArtifactEnvelope {
        let hash = SHA256.hash(data: Data(rawContent.utf8)).map { String(format: "%02x", $0) }.joined()
        return MemoryOSLLMArtifactEnvelope(queueItemID: queueItemID, processingRunID: processingRunID, artifactType: artifactType, schemaName: schemaName, schemaVersion: schemaVersion, modelID: modelID, rawContent: rawContent, contentHash: hash, createdAt: now, metadata: metadata)
    }
}

public struct MemoryOSLLMArtifactValidator: Sendable {
    public init() {}

    public func validateStructuredExtractionArtifact(_ artifact: MemoryOSLLMArtifactEnvelope) -> MemoryOSArtifactValidationResult {
        guard let data = artifact.rawContent.data(using: .utf8) else {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "invalid_utf8", message: "Artifact content is not valid UTF-8.")])
        }
        switch artifact.schemaName {
        case "GraphStructuredExtractionOutput":
            return validateGraphStructuredExtractionArtifact(artifact, data: data)
        case "MemoryOSKnowledgeExtractionOutput":
            return validateKnowledgeExtractionArtifact(artifact, data: data)
        case "MemoryOSL1UnifiedProjectionOutput":
            return validateL1UnifiedProjectionArtifact(artifact, data: data)
        default:
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "unsupported_schema", message: "Unsupported artifact schema: \(artifact.schemaName).")])
        }
    }

    private func validateGraphStructuredExtractionArtifact(_ artifact: MemoryOSLLMArtifactEnvelope, data: Data) -> MemoryOSArtifactValidationResult {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let output = try decoder.decode(GraphStructuredExtractionOutput.self, from: data)
            try output.validate(requireStatementEvidence: false)
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: true, normalizedRecordCount: output.entities.count + output.statements.count)
        } catch let error as GraphStructuredExtractionValidationError {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "schema_validation_failed", message: error.description)])
        } catch {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "json_decode_failed", message: String(describing: error))])
        }
    }

    private func validateKnowledgeExtractionArtifact(_ artifact: MemoryOSLLMArtifactEnvelope, data: Data) -> MemoryOSArtifactValidationResult {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let output = try decoder.decode(MemoryOSKnowledgeExtractionOutput.self, from: data)
            let issues = validateKnowledgeSections(
                candidates: output.knowledgeCandidates,
                conceptEntities: output.conceptEntities,
                conceptRelations: output.conceptRelations,
                evidenceSpanIDs: Set(output.evidenceSpans.map(\.id)),
                allowedEvidenceStatementIDs: nil
            )

            let fatal = fatalIssues(from: issues)
            let droppedCandidates = droppedKnowledgeCandidateIDs(from: issues)
            let droppedRelations = droppedRelationReferences(from: issues)
            let droppedCount = droppedCandidates.count + droppedRelations.count

            return MemoryOSArtifactValidationResult(
                artifactID: artifact.id,
                accepted: fatal.isEmpty,
                acceptanceMode: fatal.isEmpty ? (issues.isEmpty ? MemoryOSAcceptanceMode.strictAccepted.rawValue : MemoryOSAcceptanceMode.degradedAccepted.rawValue) : MemoryOSAcceptanceMode.rejected.rawValue,
                issues: issues,
                normalizedRecordCount: output.knowledgeCandidates.count + output.conceptEntities.count + output.conceptRelations.count,
                acceptedRecordCount: (output.knowledgeCandidates.count + output.conceptEntities.count + output.conceptRelations.count) - droppedCount,
                degradedRecordCount: issues.isEmpty ? 0 : droppedCount,
                droppedRecordCount: droppedCount
            )
        } catch {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "json_decode_failed", message: String(describing: error))])
        }
    }

    private func validateL1UnifiedProjectionArtifact(_ artifact: MemoryOSLLMArtifactEnvelope, data: Data) -> MemoryOSArtifactValidationResult {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let output = try decoder.decode(MemoryOSL1UnifiedProjectionOutput.self, from: data)
            let graphOutput = GraphStructuredExtractionOutput(
                entities: output.operationalEntities,
                statements: output.operationalStatements,
                evidenceSpans: output.evidenceSpans,
                warnings: output.warnings,
                confidence: nil,
                metadata: output.metadata
            )
            try graphOutput.validate(requireStatementEvidence: false)

            var issues = validatePersonProfileSections(
                entities: output.operationalEntities,
                statements: output.operationalStatements
            )
            issues.append(contentsOf: validateKnowledgeSections(
                candidates: output.knowledgeCandidates,
                conceptEntities: output.conceptEntities,
                conceptRelations: output.conceptRelations,
                evidenceSpanIDs: Set(output.evidenceSpans.map(\.id)),
                allowedEvidenceStatementIDs: Set(output.operationalStatements.map(\.id))
            ))

            let fatal = fatalIssues(from: issues)
            let droppedCandidates = droppedKnowledgeCandidateIDs(from: issues)
            let droppedRelations = droppedRelationReferences(from: issues)
            let droppedCount = droppedCandidates.count + droppedRelations.count
            let totalCount = output.operationalEntities.count + output.operationalStatements.count + output.knowledgeCandidates.count + output.conceptEntities.count + output.conceptRelations.count

            return MemoryOSArtifactValidationResult(
                artifactID: artifact.id,
                accepted: fatal.isEmpty,
                acceptanceMode: fatal.isEmpty ? (issues.isEmpty ? MemoryOSAcceptanceMode.strictAccepted.rawValue : MemoryOSAcceptanceMode.degradedAccepted.rawValue) : MemoryOSAcceptanceMode.rejected.rawValue,
                issues: issues,
                normalizedRecordCount: totalCount,
                acceptedRecordCount: totalCount - droppedCount,
                degradedRecordCount: issues.isEmpty ? 0 : droppedCount,
                droppedRecordCount: droppedCount
            )
        } catch let error as GraphStructuredExtractionValidationError {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "schema_validation_failed", message: error.description)])
        } catch {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "json_decode_failed", message: String(describing: error))])
        }
    }

    private func validatePersonProfileSections(entities: [GraphStructuredExtractedEntity], statements: [GraphStructuredExtractedStatement]) -> [MemoryOSValidationIssue] {
        var issues: [MemoryOSValidationIssue] = []
        let forbiddenCurrentUserAliases: Set<String> = ["user", "users", "用户", "当前用户", "current", "profile", "current user", "current_user"]

        for entity in entities {
            let isCurrentUser = entity.metadata["person_role"] == "current_user" || entity.metadata["role"] == "current_user" || entity.metadata["stable_key"] == "current_user"
            if isCurrentUser {
                for alias in entity.aliases {
                    let normalized = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if forbiddenCurrentUserAliases.contains(normalized) {
                        issues.append(MemoryOSValidationIssue(code: "current_user_generic_alias", message: "current_user entity must not use generic alias: \(alias).", severity: MemoryOSIssueSeverity.fatal.rawValue, scope: "current_user_fact", disposition: MemoryOSIssueDisposition.rejectArtifact.rawValue, recordReference: entity.localID))
                    }
                }
            }
        }

        for statement in statements where statement.metadata["l2_fact_type"] == "profile_preference" {
            let required = ["person_role", "person_resolution", "profile_dimension"]
            let missing = required.filter { (statement.metadata[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !missing.isEmpty {
                issues.append(MemoryOSValidationIssue(code: "missing_profile_person_metadata", message: "profile_preference statement \(statement.id) is missing metadata keys: \(missing.joined(separator: ", ")).", severity: MemoryOSIssueSeverity.fatal.rawValue, scope: "current_user_fact", disposition: MemoryOSIssueDisposition.rejectArtifact.rawValue, recordReference: statement.id))
            }
            if statement.metadata["person_role"] == "current_user" {
                let anchor = statement.metadata["identity_anchor"] ?? statement.metadata["identity_anchor_id"] ?? ""
                if anchor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(MemoryOSValidationIssue(code: "missing_current_user_identity_anchor", message: "current_user profile statement \(statement.id) must include identity_anchor or identity_anchor_id metadata.", severity: MemoryOSIssueSeverity.fatal.rawValue, scope: "current_user_fact", disposition: MemoryOSIssueDisposition.rejectArtifact.rawValue, recordReference: statement.id))
                }
            }
            if statement.metadata["person_role"] == "ambiguous_person" && statement.metadata["person_resolution"] != "needs_confirmation" {
                issues.append(MemoryOSValidationIssue(code: "ambiguous_person_requires_confirmation", message: "ambiguous person profile statement \(statement.id) must set person_resolution = needs_confirmation.", severity: MemoryOSIssueSeverity.fatal.rawValue, scope: "current_user_fact", disposition: MemoryOSIssueDisposition.rejectArtifact.rawValue, recordReference: statement.id))
            }
        }

        return issues
    }

    private func validateKnowledgeSections(candidates: [MemoryOSKnowledgeCandidate], conceptEntities: [MemoryOSExtractedConceptEntity], conceptRelations: [MemoryOSExtractedConceptRelation], evidenceSpanIDs: Set<String>, allowedEvidenceStatementIDs: Set<String>?) -> [MemoryOSValidationIssue] {
        let promotion = MemoryOSKnowledgePromotionPolicy()
        var issues: [MemoryOSValidationIssue] = []
        let entityNames = Set(conceptEntities.map(\.name))

        for candidate in candidates {
            let recordReference = candidate.id
            let decision = promotion.evaluate(candidate)
            if !decision.accepted {
                issues.append(MemoryOSValidationIssue(code: "knowledge_promotion_rejected", message: "Knowledge candidate rejected by promotion policy: \(candidate.title).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
            if candidate.evidenceStatementIDs.isEmpty {
                issues.append(MemoryOSValidationIssue(code: "missing_knowledge_evidence", message: "Knowledge candidate requires evidence statements: \(candidate.title).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
            if let allowedEvidenceStatementIDs {
                for statementID in candidate.evidenceStatementIDs where !allowedEvidenceStatementIDs.contains(statementID) {
                    issues.append(MemoryOSValidationIssue(code: "unknown_knowledge_evidence_statement", message: "Knowledge candidate references unknown L1 operational statement: \(statementID).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
                }
            }
            for entityName in candidate.relatedEntityNames where !entityNames.contains(entityName) {
                issues.append(MemoryOSValidationIssue(code: "unknown_knowledge_entity", message: "Knowledge candidate references unknown concept entity: \(entityName).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
            for spanID in candidate.evidenceSpanIDs where !evidenceSpanIDs.contains(spanID) {
                issues.append(MemoryOSValidationIssue(code: "unknown_evidence_span", message: "Knowledge candidate references unknown evidence span: \(spanID).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
        }

        let relationValidator = MemoryOSL4RelationConstraintValidator()
        for relation in conceptRelations {
            let relationReference = relationReferenceKey(relation)
            let relationIssues = relationValidator.validate(relation: relation, conceptEntities: conceptEntities).map { issue in
                MemoryOSValidationIssue(
                    id: issue.id,
                    code: issue.code,
                    message: issue.message,
                    severity: MemoryOSIssueSeverity.warning.rawValue,
                    scope: issue.scope ?? "relation",
                    disposition: issue.disposition ?? MemoryOSIssueDisposition.dropRecord.rawValue,
                    recordReference: issue.recordReference ?? relationReference,
                    repairHint: issue.repairHint
                )
            }
            issues.append(contentsOf: relationIssues)
        }

        return issues
    }

    private func relationReferenceKey(_ relation: MemoryOSExtractedConceptRelation) -> String {
        [relation.subjectName, relation.predicate.rawValue, relation.objectName].joined(separator: "|")
    }

    private func fatalIssues(from issues: [MemoryOSValidationIssue]) -> [MemoryOSValidationIssue] {
        issues.filter { issue in
            issue.severityKind == .fatal || issue.dispositionKind == .rejectArtifact
        }
    }

    private func droppedKnowledgeCandidateIDs(from issues: [MemoryOSValidationIssue]) -> Set<String> {
        Set(issues.compactMap { issue in
            guard issue.scope == "knowledge_candidate", issue.dispositionKind == .dropRecord else { return nil }
            return issue.recordReference
        })
    }

    private func droppedRelationReferences(from issues: [MemoryOSValidationIssue]) -> Set<String> {
        Set(issues.compactMap { issue in
            guard issue.scope == "relation", issue.dispositionKind == .dropRecord else { return nil }
            return issue.recordReference
        })
    }

    private func outputValidationIssues(_ output: MemoryOSKnowledgeExtractionOutput) -> [MemoryOSValidationIssue] {
        outputValidationIssues(
            knowledgeCandidates: output.knowledgeCandidates,
            conceptEntities: output.conceptEntities,
            conceptRelations: output.conceptRelations,
            evidenceSpanIDs: Set(output.evidenceSpans.map(\.id)),
            allowedEvidenceStatementIDs: nil
        )
    }

    private func outputValidationIssues(knowledgeCandidates: [MemoryOSKnowledgeCandidate], conceptEntities: [MemoryOSExtractedConceptEntity], conceptRelations: [MemoryOSExtractedConceptRelation], evidenceSpanIDs: Set<String>, allowedEvidenceStatementIDs: Set<String>?) -> [MemoryOSValidationIssue] {
        validateKnowledgeSections(
            candidates: knowledgeCandidates,
            conceptEntities: conceptEntities,
            conceptRelations: conceptRelations,
            evidenceSpanIDs: evidenceSpanIDs,
            allowedEvidenceStatementIDs: allowedEvidenceStatementIDs
        )
    }
}

public struct MemoryOSQueueTransitionService: Sendable {
    public init() {}

    public func markFailed(_ item: MemoryOSQueueItem, errorCode: String, errorMessage: String, now: Date = Date(), recovery: MemoryOSRecoveryService = MemoryOSRecoveryService()) -> MemoryOSQueueItem {
        var next = item
        next.attemptCount += 1
        next.errorCode = errorCode
        next.errorMessage = errorMessage
        next.lockedAt = nil
        next.lockedBy = nil
        next.leaseExpiresAt = nil
        next.updatedAt = now
        if next.attemptCount >= next.maxAttempts {
            next.status = .deadLetter
            next.nextRunAt = now
        } else {
            next.status = .retryScheduled
            next.nextRunAt = now.addingTimeInterval(recovery.nextRetryDelay(attemptCount: next.attemptCount))
        }
        return next
    }

    public func markSucceeded(_ item: MemoryOSQueueItem, now: Date = Date()) -> MemoryOSQueueItem {
        var next = item
        next.status = .succeeded
        next.lockedAt = nil
        next.lockedBy = nil
        next.leaseExpiresAt = nil
        next.updatedAt = now
        return next
    }
}

public struct MemoryOSStatementValidator: Sendable {
    public init() {}

    public func validate(_ statement: MemoryOSStatement) -> [MemoryOSValidationIssue] {
        var issues: [MemoryOSValidationIssue] = []
        if statement.confidence < 0 || statement.confidence > 1 { issues.append(MemoryOSValidationIssue(code: "confidence_out_of_range", message: "Confidence must be between 0 and 1.")) }
        if statement.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(MemoryOSValidationIssue(code: "empty_statement", message: "Statement text must not be empty.")) }
        return issues
    }
}

public struct MemoryOSEvidenceValidator: Sendable {
    public init() {}
    public func validateEvidenceRefs(_ refs: [String]) -> [MemoryOSValidationIssue] {
        refs.isEmpty ? [MemoryOSValidationIssue(code: "missing_evidence", message: "Evidence references are required.")] : []
    }
}

public struct MemoryOSProjectionService: Sendable {
    public init() {}

    private func relationReferenceKey(_ relation: MemoryOSExtractedConceptRelation) -> String {
        [relation.subjectName, relation.predicate.rawValue, relation.objectName].joined(separator: "|")
    }

    private func droppedKnowledgeCandidateIDs(from issues: [MemoryOSValidationIssue]) -> Set<String> {
        Set(issues.compactMap { issue in
            guard issue.scope == "knowledge_candidate", issue.dispositionKind == .dropRecord else { return nil }
            return issue.recordReference
        })
    }

    private func droppedRelationReferences(from issues: [MemoryOSValidationIssue]) -> Set<String> {
        Set(issues.compactMap { issue in
            guard issue.scope == "relation", issue.dispositionKind == .dropRecord else { return nil }
            return issue.recordReference
        })
    }

    private func outputValidationIssues(_ output: MemoryOSKnowledgeExtractionOutput) -> [MemoryOSValidationIssue] {
        let promotion = MemoryOSKnowledgePromotionPolicy()
        var issues: [MemoryOSValidationIssue] = []
        let entityNames = Set(output.conceptEntities.map(\.name))

        for candidate in output.knowledgeCandidates {
            let recordReference = candidate.id
            let decision = promotion.evaluate(candidate)
            if !decision.accepted {
                issues.append(MemoryOSValidationIssue(code: "knowledge_promotion_rejected", message: "Knowledge candidate rejected by promotion policy: \(candidate.title).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
            if candidate.evidenceStatementIDs.isEmpty {
                issues.append(MemoryOSValidationIssue(code: "missing_knowledge_evidence", message: "Knowledge candidate requires evidence statements: \(candidate.title).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
            for entityName in candidate.relatedEntityNames where !entityNames.contains(entityName) {
                issues.append(MemoryOSValidationIssue(code: "unknown_knowledge_entity", message: "Knowledge candidate references unknown concept entity: \(entityName).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
            for spanID in candidate.evidenceSpanIDs where !Set(output.evidenceSpans.map(\.id)).contains(spanID) {
                issues.append(MemoryOSValidationIssue(code: "unknown_evidence_span", message: "Knowledge candidate references unknown evidence span: \(spanID).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
        }

        let relationValidator = MemoryOSL4RelationConstraintValidator()
        for relation in output.conceptRelations {
            let relationReference = relationReferenceKey(relation)
            let relationIssues = relationValidator.validate(relation: relation, conceptEntities: output.conceptEntities).map { issue in
                MemoryOSValidationIssue(
                    id: issue.id,
                    code: issue.code,
                    message: issue.message,
                    severity: MemoryOSIssueSeverity.warning.rawValue,
                    scope: issue.scope ?? "relation",
                    disposition: issue.disposition ?? MemoryOSIssueDisposition.dropRecord.rawValue,
                    recordReference: issue.recordReference ?? relationReference,
                    repairHint: issue.repairHint
                )
            }
            issues.append(contentsOf: relationIssues)
        }

        return issues
    }

    private func outputValidationIssues(knowledgeCandidates: [MemoryOSKnowledgeCandidate], conceptEntities: [MemoryOSExtractedConceptEntity], conceptRelations: [MemoryOSExtractedConceptRelation], evidenceSpanIDs: Set<String>, allowedEvidenceStatementIDs: Set<String>?) -> [MemoryOSValidationIssue] {
        let promotion = MemoryOSKnowledgePromotionPolicy()
        var issues: [MemoryOSValidationIssue] = []
        let entityNames = Set(conceptEntities.map(\.name))

        for candidate in knowledgeCandidates {
            let recordReference = candidate.id
            let decision = promotion.evaluate(candidate)
            if !decision.accepted {
                issues.append(MemoryOSValidationIssue(code: "knowledge_promotion_rejected", message: "Knowledge candidate rejected by promotion policy: \(candidate.title).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
            if candidate.evidenceStatementIDs.isEmpty {
                issues.append(MemoryOSValidationIssue(code: "missing_knowledge_evidence", message: "Knowledge candidate requires evidence statements: \(candidate.title).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
            if let allowedEvidenceStatementIDs {
                for statementID in candidate.evidenceStatementIDs where !allowedEvidenceStatementIDs.contains(statementID) {
                    issues.append(MemoryOSValidationIssue(code: "unknown_knowledge_evidence_statement", message: "Knowledge candidate references unknown L1 operational statement: \(statementID).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
                }
            }
            for entityName in candidate.relatedEntityNames where !entityNames.contains(entityName) {
                issues.append(MemoryOSValidationIssue(code: "unknown_knowledge_entity", message: "Knowledge candidate references unknown concept entity: \(entityName).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
            for spanID in candidate.evidenceSpanIDs where !evidenceSpanIDs.contains(spanID) {
                issues.append(MemoryOSValidationIssue(code: "unknown_evidence_span", message: "Knowledge candidate references unknown evidence span: \(spanID).", severity: MemoryOSIssueSeverity.warning.rawValue, scope: "knowledge_candidate", disposition: MemoryOSIssueDisposition.dropRecord.rawValue, recordReference: recordReference))
            }
        }

        let relationValidator = MemoryOSL4RelationConstraintValidator()
        for relation in conceptRelations {
            let relationReference = relationReferenceKey(relation)
            let relationIssues = relationValidator.validate(relation: relation, conceptEntities: conceptEntities).map { issue in
                MemoryOSValidationIssue(
                    id: issue.id,
                    code: issue.code,
                    message: issue.message,
                    severity: MemoryOSIssueSeverity.warning.rawValue,
                    scope: issue.scope ?? "relation",
                    disposition: issue.disposition ?? MemoryOSIssueDisposition.dropRecord.rawValue,
                    recordReference: issue.recordReference ?? relationReference,
                    repairHint: issue.repairHint
                )
            }
            issues.append(contentsOf: relationIssues)
        }

        return issues
    }

    public func currentProjection(statements: [MemoryOSStatement]) -> [MemoryOSStatement] {
        statements.sorted {
            if $0.validAt != $1.validAt { return $0.validAt > $1.validAt }
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.committedAt > $1.committedAt
        }
    }

    public func projectionBatch(from artifact: MemoryOSLLMArtifactEnvelope, validation: MemoryOSArtifactValidationResult, now: Date = Date()) -> MemoryOSProjectionBuildResult {
        guard validation.accepted else { return MemoryOSProjectionBuildResult(accepted: false, acceptanceMode: validation.acceptanceMode, validation: validation) }
        guard let data = artifact.rawContent.data(using: .utf8) else {
            let rejected = MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "invalid_utf8", message: "Artifact content is not valid UTF-8.", severity: MemoryOSIssueSeverity.fatal.rawValue, disposition: MemoryOSIssueDisposition.rejectArtifact.rawValue)])
            return MemoryOSProjectionBuildResult(accepted: false, acceptanceMode: rejected.acceptanceMode, validation: rejected)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            switch artifact.schemaName {
            case "GraphStructuredExtractionOutput":
                let output = try decoder.decode(GraphStructuredExtractionOutput.self, from: data)
                try output.validate(requireStatementEvidence: false)
                let batch = projectionBatch(from: output, artifactID: artifact.id, now: now)
                return MemoryOSProjectionBuildResult(accepted: true, acceptanceMode: validation.acceptanceMode, batch: batch, validation: validation)
            case "MemoryOSKnowledgeExtractionOutput":
                let output = try decoder.decode(MemoryOSKnowledgeExtractionOutput.self, from: data)
                let batch = projectionBatch(from: output, artifactID: artifact.id, now: now)
                return MemoryOSProjectionBuildResult(accepted: true, acceptanceMode: validation.acceptanceMode, batch: batch, validation: validation)
            case "MemoryOSL1UnifiedProjectionOutput":
                let output = try decoder.decode(MemoryOSL1UnifiedProjectionOutput.self, from: data)
                let batch = projectionBatch(from: output, artifactID: artifact.id, now: now)
                return MemoryOSProjectionBuildResult(accepted: true, acceptanceMode: validation.acceptanceMode, batch: batch, validation: validation)
            default:
                let rejected = MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "unsupported_schema", message: "Unsupported artifact schema: \(artifact.schemaName).", severity: MemoryOSIssueSeverity.fatal.rawValue, disposition: MemoryOSIssueDisposition.rejectArtifact.rawValue)])
                return MemoryOSProjectionBuildResult(accepted: false, acceptanceMode: rejected.acceptanceMode, validation: rejected)
            }
        } catch let error as GraphStructuredExtractionValidationError {
            let rejected = MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "schema_validation_failed", message: error.description, severity: MemoryOSIssueSeverity.fatal.rawValue, disposition: MemoryOSIssueDisposition.rejectArtifact.rawValue)])
            return MemoryOSProjectionBuildResult(accepted: false, acceptanceMode: rejected.acceptanceMode, validation: rejected)
        } catch {
            let rejected = MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "json_decode_failed", message: String(describing: error), severity: MemoryOSIssueSeverity.fatal.rawValue, disposition: MemoryOSIssueDisposition.rejectArtifact.rawValue)])
            return MemoryOSProjectionBuildResult(accepted: false, acceptanceMode: rejected.acceptanceMode, validation: rejected)
        }
    }

    public func projectionBatch(from output: GraphStructuredExtractionOutput, artifactID: String, now: Date = Date()) -> MemoryOSProjectionBatch {
        let nodeByLocalID = Dictionary(uniqueKeysWithValues: output.entities.map { entity in
            let scope = entity.scope.rawValue
            let stableKey = MemoryOSStableKeyBuilder.stableKey(type: entity.entityKind.rawValue, name: entity.name, scope: scope)
            let id = "l2-node:\(stableKey)"
            let node = MemoryOSNode(
                id: id,
                stableKey: stableKey,
                nodeType: entity.entityKind.rawValue,
                name: entity.name,
                summary: entity.summary,
                createdAt: now,
                updatedAt: now,
                metadata: entity.metadata.merging([
                    "artifact_id": artifactID,
                    "local_id": entity.localID,
                    "scope": scope,
                    "confidence": String(entity.confidence)
                ]) { _, new in new }
            )
            return (entity.localID, node)
        })
        let entityByLocalID = Dictionary(uniqueKeysWithValues: output.entities.map { entity in
            let scope = entity.scope.rawValue
            let stableKey = MemoryOSStableKeyBuilder.stableKey(type: entity.entityKind.rawValue, name: entity.name, scope: scope)
            let stableEntity = MemoryOSEntity(
                id: "l4-entity:\(stableKey)",
                stableKey: stableKey,
                entityType: entity.entityKind.rawValue,
                name: entity.name,
                aliases: entity.aliases,
                summary: entity.summary,
                confidence: entity.confidence,
                createdAt: now,
                updatedAt: now,
                validFrom: now,
                metadata: entity.metadata.merging([
                    "artifact_id": artifactID,
                    "local_id": entity.localID,
                    "scope": scope
                ]) { _, new in new }
            )
            return (entity.localID, stableEntity)
        })
        let statements = output.statements.compactMap { statement -> MemoryOSStatement? in
            guard let subject = nodeByLocalID[statement.subjectLocalID] else { return nil }
            let object = nodeByLocalID[statement.objectLocalID]
            return MemoryOSStatement(
                id: "l2-statement:\(artifactID):\(statement.id)",
                subjectID: subject.id,
                predicate: statement.predicate.rawValue,
                objectID: object?.id,
                text: statement.statementText,
                assertionKind: .observed,
                confidence: statement.confidence,
                validAt: statement.validAt ?? statement.referenceTime ?? now,
                committedAt: now,
                evidenceSpanIDs: statement.evidenceSpanIDs,
                sourceArtifactID: artifactID,
                metadata: statement.metadata.merging([
                    "artifact_id": artifactID,
                    "source_statement_id": statement.id,
                    "subject_local_id": statement.subjectLocalID,
                    "object_local_id": statement.objectLocalID
                ]) { _, new in new }
            )
        }
        let entityStatements = output.statements.compactMap { statement -> MemoryOSEntityStatement? in
            guard let subject = entityByLocalID[statement.subjectLocalID],
                  let predicate = MemoryOSL4RelationPredicate(rawValue: statement.predicate.rawValue) else { return nil }
            let object = entityByLocalID[statement.objectLocalID]
            return MemoryOSEntityStatement(
                id: "l4-statement:\(artifactID):\(statement.id)",
                entityID: subject.id,
                predicate: predicate,
                objectEntityID: object?.id,
                text: statement.statementText,
                assertionKind: .observed,
                confidence: statement.confidence,
                validAt: statement.validAt ?? statement.referenceTime ?? now,
                committedAt: now,
                evidenceSpanIDs: statement.evidenceSpanIDs,
                sourceArtifactID: artifactID,
                metadata: statement.metadata.merging([
                    "artifact_id": artifactID,
                    "source_statement_id": statement.id
                ]) { _, new in new }
            )
        }
        // L3 is reserved for reusable knowledge/theory records. High-confidence
        // operational facts remain in L2/L4 and must not be promoted to L3 by
        // confidence alone.
        let beliefs: [MemoryOSBelief] = []
        return MemoryOSProjectionBatch(
            artifactID: artifactID,
            nodes: Array(nodeByLocalID.values).sorted { $0.id < $1.id },
            statements: statements,
            entities: Array(entityByLocalID.values).sorted { $0.id < $1.id },
            entityStatements: entityStatements,
            beliefs: beliefs
        )
    }

    public func projectionBatch(from output: MemoryOSL1UnifiedProjectionOutput, artifactID: String, now: Date = Date()) -> MemoryOSProjectionBatch {
        // 1. operational -> L2 only (nodes + statements), no dual projection to L4
        let operationalOutput = GraphStructuredExtractionOutput(
            entities: output.operationalEntities,
            statements: output.operationalStatements,
            evidenceSpans: output.evidenceSpans,
            warnings: output.warnings,
            confidence: nil,
            metadata: output.metadata
        )
        let operationalBatch = projectionBatch(from: operationalOutput, artifactID: artifactID, now: now)

        // 2. Map L2 statement IDs for knowledge candidate evidence references
        let localStatementIDMap = Dictionary(uniqueKeysWithValues: output.operationalStatements.map { statement in
            (statement.id, "l2-statement:\(artifactID):\(statement.id)")
        })

        let validationIssues = outputValidationIssues(knowledgeCandidates: output.knowledgeCandidates, conceptEntities: output.conceptEntities, conceptRelations: output.conceptRelations, evidenceSpanIDs: Set(output.evidenceSpans.map(\.id)), allowedEvidenceStatementIDs: Set(output.operationalStatements.map(\.id)))
        let droppedCandidateIDs = droppedKnowledgeCandidateIDs(from: validationIssues)
        let droppedRelationRefs = droppedRelationReferences(from: validationIssues)

        // 3. Build name index from conceptEntities for knowledge candidate resolution
        let conceptEntityByName = Dictionary(uniqueKeysWithValues: output.conceptEntities.map { concept in
            let scope = concept.domain ?? "knowledge"
            let entityType = MemoryOSEntityType.normalizeRawType(concept.conceptType)
            let stableKey = MemoryOSStableKeyBuilder.stableKey(type: entityType, name: concept.name, scope: scope)
            let entityID = "l4-entity:\(stableKey)"
            return (concept.name, entityID)
        })

        let remappedCandidates = output.knowledgeCandidates.filter { !droppedCandidateIDs.contains($0.id) }.map { candidate in
            var next = candidate
            next.evidenceStatementIDs = candidate.evidenceStatementIDs.map { localStatementIDMap[$0] ?? $0 }
            next.relatedEntityNames = candidate.relatedEntityNames.compactMap { conceptEntityByName[$0] }
            next.metadata = next.metadata.merging(["source_stage": "l1_unified_projection"]) { _, new in new }
            return next
        }

        // 4. concept entities/relations -> L4 (by name, not localID)
        let knowledgeOutput = MemoryOSKnowledgeExtractionOutput(
            knowledgeCandidates: remappedCandidates,
            conceptEntities: output.conceptEntities,
            conceptRelations: output.conceptRelations.filter { !droppedRelationRefs.contains(relationReferenceKey($0)) },
            evidenceSpans: output.evidenceSpans.map { MemoryOSKnowledgeEvidenceSpan(id: $0.id, text: $0.text, startOffset: $0.startOffset, endOffset: $0.endOffset) },
            warnings: output.warnings.map(\.message),
            metadata: output.metadata.merging(["source_stage": "l1_unified_projection"]) { _, new in new }
        )
        let knowledgeBatch = projectionBatch(from: knowledgeOutput, artifactID: artifactID, now: now)

        // 5. No dual projection: operational -> L2, concept -> L4
        return MemoryOSProjectionBatch(
            artifactID: artifactID,
            nodes: operationalBatch.nodes,
            statements: operationalBatch.statements,
            entities: knowledgeBatch.entities,
            entityStatements: knowledgeBatch.entityStatements,
            beliefs: knowledgeBatch.beliefs
        )
    }

    public func projectionBatch(from output: MemoryOSKnowledgeExtractionOutput, artifactID: String, now: Date = Date()) -> MemoryOSProjectionBatch {
        let validationIssues = outputValidationIssues(output)
        let droppedCandidateIDs = droppedKnowledgeCandidateIDs(from: validationIssues)
        let droppedRelationRefs = droppedRelationReferences(from: validationIssues)

        // Build L4 entities from conceptEntities, keyed by name (not localID)
        let entityByName: [String: MemoryOSEntity] = Dictionary(uniqueKeysWithValues: output.conceptEntities.map { concept in
            let scope = concept.domain ?? "knowledge"
            let entityType = MemoryOSEntityType.normalizeRawType(concept.conceptType)
            let stableKey = MemoryOSStableKeyBuilder.stableKey(type: entityType, name: concept.name, scope: scope)
            let entity = MemoryOSEntity(
                id: "l4-entity:\(stableKey)",
                stableKey: stableKey,
                entityType: entityType,
                name: concept.name,
                aliases: concept.aliases,
                summary: concept.summary,
                confidence: 1.0,
                createdAt: now,
                updatedAt: now,
                validFrom: now,
                metadata: concept.metadata.merging([
                    "artifact_id": artifactID,
                    "domain": concept.domain ?? ""
                ]) { _, new in new }
            )
            return (concept.name, entity)
        })

        // Build L4 entity statements from conceptRelations, resolving subject/object by name
        let entityStatements = output.conceptRelations.filter { !droppedRelationRefs.contains(relationReferenceKey($0)) }.compactMap { relation -> MemoryOSEntityStatement? in
            guard let subject = entityByName[relation.subjectName],
                  let object = entityByName[relation.objectName] else {
                return nil
            }
            return MemoryOSEntityStatement(
                id: "l4-concept-relation:\(artifactID):\(UUID().uuidString)",
                entityID: subject.id,
                predicate: relation.predicate,
                objectEntityID: object.id,
                text: relation.text,
                assertionKind: .summarized,
                confidence: 1.0,
                validAt: now,
                committedAt: now,
                evidenceSpanIDs: [],
                sourceArtifactID: artifactID,
                metadata: relation.metadata.merging([
                    "artifact_id": artifactID,
                    "relation_type": "concept_relation"
                ]) { _, new in new }
            )
        }

        // L3 beliefs from knowledge candidates (unchanged)
        let promotion = MemoryOSKnowledgePromotionPolicy()
        let beliefs = output.knowledgeCandidates.filter { !droppedCandidateIDs.contains($0.id) }.compactMap { candidate in
            promotion.makeKnowledgeBelief(
                from: candidate,
                decision: promotion.evaluate(candidate),
                sourceArtifactID: artifactID,
                now: now
            )
        }

        return MemoryOSProjectionBatch(
            artifactID: artifactID,
            nodes: [],
            statements: [],
            entities: Array(entityByName.values).sorted { $0.id < $1.id },
            entityStatements: entityStatements,
            beliefs: beliefs
        )
    }
}

public struct MemoryOSBeliefValidator: Sendable {
    public init() {}
    public func validate(_ belief: MemoryOSBelief) -> [MemoryOSValidationIssue] {
        var issues: [MemoryOSValidationIssue] = []
        if belief.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(MemoryOSValidationIssue(code: "empty_belief", message: "Belief statement must not be empty.")) }
        if belief.domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(MemoryOSValidationIssue(code: "missing_belief_domain", message: "Belief discipline domain must not be empty.")) }
        return issues
    }
}

public struct MemoryOSCurrentViewService: Sendable {
    public init() {}

    public func currentStatements(_ statements: [MemoryOSStatement], now: Date = Date()) -> [MemoryOSCurrentViewRecord] {
        let groups = Dictionary(grouping: statements) { statement in
            [statement.subjectID, statement.predicate, statement.objectID ?? ""].joined(separator: "|")
        }
        return groups.keys.sorted().compactMap { key in
            guard let candidates = groups[key], let selected = bestStatement(from: candidates) else { return nil }
            let alternatives = candidates.filter { $0.id != selected.id }.sorted { $0.validAt > $1.validAt }
            let diagnostics = ambiguityDiagnostics(selectedID: selected.id, candidates: candidates.map { ($0.id, $0.validAt, $0.confidence) }, now: now)
            return MemoryOSCurrentViewRecord(
                layer: "L2",
                key: key,
                value: selected.text,
                selectedRecordID: selected.id,
                validAt: selected.validAt,
                confidence: selected.confidence,
                evidenceIDs: selected.evidenceSpanIDs,
                alternativeRecordIDs: alternatives.map(\.id),
                diagnostics: diagnostics
            )
        }
    }

    public func currentBeliefs(_ beliefs: [MemoryOSBelief], now: Date = Date()) -> [MemoryOSCurrentViewRecord] {
        let groups = Dictionary(grouping: beliefs) { $0.domain }
        return groups.keys.sorted().compactMap { domain in
            guard let candidates = groups[domain], let selected = bestBelief(from: candidates) else { return nil }
            let alternatives = candidates.filter { $0.id != selected.id }.sorted { $0.updatedAt > $1.updatedAt }
            let diagnostics = ambiguityDiagnostics(selectedID: selected.id, candidates: candidates.map { ($0.id, $0.updatedAt, 1.0) }, now: now)
            return MemoryOSCurrentViewRecord(
                layer: "L3",
                key: domain,
                value: selected.statement,
                selectedRecordID: selected.id,
                validAt: selected.updatedAt,
                confidence: 1.0,
                evidenceIDs: [],
                alternativeRecordIDs: alternatives.map(\.id),
                diagnostics: diagnostics
            )
        }
    }

    public func currentEntityProfile(entityID: String, statements: [MemoryOSEntityStatement], now: Date = Date()) -> MemoryOSEntityCurrentProfile {
        let records = currentEntityStatements(statements.filter { $0.entityID == entityID }, now: now)
        return MemoryOSEntityCurrentProfile(entityID: entityID, generatedAt: now, records: records, diagnostics: records.flatMap(\.diagnostics))
    }

    public func currentEntityStatements(_ statements: [MemoryOSEntityStatement], now: Date = Date()) -> [MemoryOSCurrentViewRecord] {
        let groups = Dictionary(grouping: statements) { statement in
            [statement.entityID, statement.predicate.rawValue, statement.objectEntityID ?? ""].joined(separator: "|")
        }
        return groups.keys.sorted().compactMap { key in
            guard let candidates = groups[key], let selected = bestEntityStatement(from: candidates) else { return nil }
            let alternatives = candidates.filter { $0.id != selected.id }.sorted { lhs, rhs in
                if lhs.validAt != rhs.validAt { return lhs.validAt > rhs.validAt }
                if lhs.committedAt != rhs.committedAt { return lhs.committedAt > rhs.committedAt }
                return lhs.id < rhs.id
            }
            let diagnostics = l4AmbiguityDiagnostics(selectedID: selected.id, candidates: candidates.map { ($0.id, $0.validAt) }, now: now)
            return MemoryOSCurrentViewRecord(
                layer: "L4",
                key: key,
                value: selected.text,
                selectedRecordID: selected.id,
                validAt: selected.validAt,
                confidence: selected.confidence,
                evidenceIDs: selected.evidenceSpanIDs,
                alternativeRecordIDs: alternatives.map(\.id),
                diagnostics: diagnostics
            )
        }
    }

    private func bestStatement(from candidates: [MemoryOSStatement]) -> MemoryOSStatement? {
        candidates.sorted { lhs, rhs in
            if lhs.validAt != rhs.validAt { return lhs.validAt > rhs.validAt }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.committedAt > rhs.committedAt
        }.first
    }

    private func bestBelief(from candidates: [MemoryOSBelief]) -> MemoryOSBelief? {
        candidates.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.createdAt > rhs.createdAt
        }.first
    }

    private func bestEntityStatement(from candidates: [MemoryOSEntityStatement]) -> MemoryOSEntityStatement? {
        candidates.sorted { lhs, rhs in
            if lhs.validAt != rhs.validAt { return lhs.validAt > rhs.validAt }
            if lhs.committedAt != rhs.committedAt { return lhs.committedAt > rhs.committedAt }
            return lhs.id < rhs.id
        }.first
    }

    private func l4AmbiguityDiagnostics(selectedID: String, candidates: [(id: String, validAt: Date)], now: Date) -> [MemoryOSCurrentViewDiagnostic] {
        guard let selected = candidates.first(where: { $0.id == selectedID }) else { return [] }
        let close = candidates.filter { candidate in
            candidate.id != selectedID && abs(candidate.validAt.timeIntervalSince(selected.validAt)) <= 86_400
        }
        guard !close.isEmpty else { return [] }
        return [MemoryOSCurrentViewDiagnostic(kind: "ambiguous_current_value", severity: "info", message: "Multiple temporal L4 records are close enough to be considered alternatives; currentness remains query-derived.", candidateRecordIDs: [selectedID] + close.map(\.id), createdAt: now)]
    }

    private func ambiguityDiagnostics(selectedID: String, candidates: [(id: String, validAt: Date, confidence: Double)], now: Date) -> [MemoryOSCurrentViewDiagnostic] {
        guard let selected = candidates.first(where: { $0.id == selectedID }) else { return [] }
        let close = candidates.filter { candidate in
            candidate.id != selectedID && abs(candidate.validAt.timeIntervalSince(selected.validAt)) <= 86_400 && abs(candidate.confidence - selected.confidence) <= 0.1
        }
        guard !close.isEmpty else { return [] }
        return [MemoryOSCurrentViewDiagnostic(kind: "ambiguous_current_value", severity: "info", message: "Multiple temporal records are close enough to be considered alternatives; currentness remains query-derived.", candidateRecordIDs: [selectedID] + close.map(\.id), createdAt: now)]
    }
}

public struct MemoryOSEntityDisambiguationService: Sendable {
    public init() {}

    public func chooseExistingEntity(named name: String, type: String, candidates: [MemoryOSEntity]) -> MemoryOSEntity? {
        let key = MemoryOSStableKeyBuilder.stableKey(type: type, name: name)
        if let exact = candidates.first(where: { $0.stableKey == key }) { return exact }
        let normalized = name.lowercased()
        return candidates.first { candidate in
            candidate.aliases.map { $0.lowercased() }.contains(normalized) || candidate.name.lowercased() == normalized
        }
    }
}

public struct MemoryOSRecoveryService: Sendable {
    public init() {}

    public func shouldRecoverLease(status: MemoryOSQueueStatus, leaseExpiresAt: Date?, now: Date = Date()) -> Bool {
        guard status == .leased || status == .processing, let leaseExpiresAt else { return false }
        return leaseExpiresAt < now
    }

    public func nextRetryDelay(attemptCount: Int) -> TimeInterval {
        min(pow(2.0, Double(max(0, attemptCount))), 3_600)
    }
}
