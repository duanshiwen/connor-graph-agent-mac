import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public struct AppGraphWriteCandidateRepository: @unchecked Sendable {
    public let store: SQLiteGraphKernelStore
    public var committer: GraphWriteCandidateCommitService
    public var validator: GraphWriteCandidateValidator
    public var permissionMode: AgentPermissionMode

    public init(
        store: SQLiteGraphKernelStore,
        committer: GraphWriteCandidateCommitService = GraphWriteCandidateCommitService(),
        validator: GraphWriteCandidateValidator = GraphWriteCandidateValidator(),
        permissionMode: AgentPermissionMode = .trustedWrite
    ) {
        self.store = store
        self.committer = committer
        self.validator = validator
        self.permissionMode = permissionMode
    }

    public func loadCandidates(status: GraphWriteCandidateStatus? = nil, limit: Int = 100) throws -> [GraphWriteCandidate] {
        try store.writeCandidates(groupID: "default", status: status, limit: limit)
    }

    public func loadAuditTimeline(for candidate: GraphWriteCandidate) throws -> [GraphWriteCandidateAuditPresentation] {
        try store.agentAuditEvents(runID: candidate.proposedByRunID)
            .filter { event in
                event.payloadJSON.contains(candidate.id) || event.eventType == .permissionDecision
            }
            .map(GraphWriteCandidateAuditPresentation.init(event:))
    }

    public func loadAuditTimelines(for candidates: [GraphWriteCandidate]) throws -> [String: [GraphWriteCandidateAuditPresentation]] {
        try candidates.reduce(into: [String: [GraphWriteCandidateAuditPresentation]]()) { partial, candidate in
            partial[candidate.id] = try loadAuditTimeline(for: candidate)
        }
    }

    public func approve(_ candidate: GraphWriteCandidate) throws -> GraphWriteCandidate {
        var copy = candidate
        copy.status = .approved
        copy.updatedAt = Date()
        try store.upsertWriteCandidate(copy)
        return copy
    }

    public func approveGoverned(_ candidate: GraphWriteCandidate, actor: String = "human-reviewer") async throws -> GraphWriteCandidate {
        let approved = try approve(candidate)
        try store.append(auditEvent: auditEvent(
            candidate: approved,
            eventType: .graphWriteCandidateApproved,
            actor: actor,
            payload: ["candidate_id": approved.id, "status": approved.status.rawValue]
        ))
        return approved
    }

    public func reject(_ candidate: GraphWriteCandidate, reason: String? = nil) throws -> GraphWriteCandidate {
        var copy = candidate
        copy.status = .rejected
        copy.updatedAt = Date()
        if let reason { copy.validationErrors.append(reason) }
        try store.upsertWriteCandidate(copy)
        return copy
    }

    public func rejectGoverned(_ candidate: GraphWriteCandidate, reason: String? = nil, actor: String = "human-reviewer") async throws -> GraphWriteCandidate {
        let rejected = try reject(candidate, reason: reason)
        try store.append(auditEvent: auditEvent(
            candidate: rejected,
            eventType: .graphWriteCandidateRejected,
            actor: actor,
            payload: ["candidate_id": rejected.id, "status": rejected.status.rawValue, "reason": reason ?? ""]
        ))
        return rejected
    }

    public func commit(_ candidate: GraphWriteCandidate) throws -> GraphWriteCandidateCommitResult {
        try committer.commit(candidate, store: store)
    }

    public func validateGoverned(_ candidate: GraphWriteCandidate, actor: String = "agent-runtime") async throws -> (candidate: GraphWriteCandidate, validation: GraphWriteCandidateValidationResult) {
        try store.append(auditEvent: auditEvent(
            candidate: candidate,
            eventType: .graphWriteValidationStarted,
            actor: actor,
            payload: ["candidate_id": candidate.id]
        ))
        let validation = validator.validate(candidate, store: store)
        var copy = candidate
        copy.validationErrors = validation.errors
        copy.status = validation.isValid ? .pendingReview : .validationFailed
        copy.updatedAt = Date()
        try store.upsertWriteCandidate(copy)
        try store.append(auditEvent: auditEvent(
            candidate: copy,
            eventType: validation.isValid ? .graphWriteValidationFinished : .graphWriteValidationFailed,
            actor: actor,
            payload: [
                "candidate_id": copy.id,
                "status": copy.status.rawValue,
                "errors": validation.errors.joined(separator: "; "),
                "warnings": validation.warnings.joined(separator: "; ")
            ]
        ))
        return (copy, validation)
    }

    public func commitGoverned(_ candidate: GraphWriteCandidate, actor: String = "human-reviewer") async throws -> GraphWriteCandidateCommitResult {
        let policy = AgentPolicyEngine(permissionMode: permissionMode, auditLog: SQLiteAgentAuditLog(store: store))
        let decision = await policy.evaluate(
            capability: .commitGraphWrite,
            runID: candidate.proposedByRunID,
            sessionID: candidate.proposedByRunID,
            toolName: "graph_write_candidate_commit",
            payloadJSON: candidate.payloadJSON
        )
        guard decision.outcome == .approved else {
            try store.append(auditEvent: auditEvent(
                candidate: candidate,
                eventType: .graphWriteCommitFailed,
                actor: actor,
                payload: ["candidate_id": candidate.id, "reason": decision.reason]
            ))
            throw GraphWriteCandidateCommitError.permissionDenied(decision.reason)
        }

        try store.append(auditEvent: auditEvent(
            candidate: candidate,
            eventType: .graphWriteCommitStarted,
            actor: actor,
            payload: ["candidate_id": candidate.id]
        ))
        do {
            let result = try commit(candidate)
            try store.append(auditEvent: auditEvent(
                candidate: candidate,
                eventType: .graphWriteCommitFinished,
                actor: actor,
                payload: [
                    "candidate_id": candidate.id,
                    "created_entity_ids": result.createdEntityIDs.joined(separator: ","),
                    "created_statement_ids": result.createdStatementIDs.joined(separator: ",")
                ]
            ))
            return result
        } catch {
            try store.append(auditEvent: auditEvent(
                candidate: candidate,
                eventType: .graphWriteCommitFailed,
                actor: actor,
                payload: ["candidate_id": candidate.id, "error": String(describing: error)]
            ))
            throw error
        }
    }

    private func auditEvent(candidate: GraphWriteCandidate, eventType: AgentAuditEventType, actor: String = "agent-runtime", payload: [String: String]) throws -> AgentAuditEvent {
        AgentAuditEvent(
            runID: candidate.proposedByRunID,
            sessionID: candidate.proposedByRunID,
            eventType: eventType,
            actor: actor,
            capability: eventType == .permissionDecision ? .commitGraphWrite : nil,
            toolName: "graph_write_candidate",
            payloadJSON: try Self.renderJSON(payload)
        )
    }

    private static func renderJSON(_ dictionary: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public enum GraphWriteCandidateAuditSeverity: String, Sendable, Equatable {
    case info
    case warning
    case error
    case success
}

public struct GraphWriteCandidateAuditPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var actor: String
    public var severity: GraphWriteCandidateAuditSeverity
    public var createdAt: Date

    public init(id: String, title: String, detail: String, actor: String, severity: GraphWriteCandidateAuditSeverity, createdAt: Date) {
        self.id = id
        self.title = title
        self.detail = detail
        self.actor = actor
        self.severity = severity
        self.createdAt = createdAt
    }

    public init(event: AgentAuditEvent) {
        self.init(
            id: event.id,
            title: Self.title(for: event.eventType),
            detail: event.payloadJSON,
            actor: event.actor,
            severity: Self.severity(for: event.eventType),
            createdAt: event.createdAt
        )
    }

    private static func title(for eventType: AgentAuditEventType) -> String {
        switch eventType {
        case .permissionDecision: "Permission decision"
        case .toolStarted: "Tool started"
        case .toolFinished: "Tool finished"
        case .toolFailed: "Tool failed"
        case .graphWriteCandidateApproved: "Candidate approved"
        case .graphWriteCandidateRejected: "Candidate rejected"
        case .graphWriteValidationStarted: "Validation started"
        case .graphWriteValidationFinished: "Validation finished"
        case .graphWriteValidationFailed: "Validation failed"
        case .graphWriteCommitStarted: "Commit started"
        case .graphWriteCommitFinished: "Commit finished"
        case .graphWriteCommitFailed: "Commit failed"
        case .localFileReadStarted: "Local file read started"
        case .localFileReadFinished: "Local file read finished"
        case .localFileReadFailed: "Local file read failed"
        case .localFileWriteStarted: "Local file write started"
        case .localFileWriteFinished: "Local file write finished"
        case .localFileWriteFailed: "Local file write failed"
        case .localShellStarted: "Local shell started"
        case .localShellFinished: "Local shell finished"
        case .localShellFailed: "Local shell failed"
        case .localWorkspacePolicyDenied: "Local workspace policy denied"
        }
    }

    private static func severity(for eventType: AgentAuditEventType) -> GraphWriteCandidateAuditSeverity {
        switch eventType {
        case .graphWriteCommitFinished, .graphWriteValidationFinished, .graphWriteCandidateApproved:
            return .success
        case .graphWriteValidationFailed, .graphWriteCommitFailed, .graphWriteCandidateRejected, .toolFailed, .localFileReadFailed, .localFileWriteFailed, .localShellFailed, .localWorkspacePolicyDenied:
            return .error
        case .permissionDecision:
            return .warning
        default:
            return .info
        }
    }
}

public struct GraphWriteCandidateCommitResult: Sendable, Equatable {
    public var candidateID: String
    public var createdEntityIDs: [String]
    public var createdStatementIDs: [String]
    public var updatedStatementIDs: [String]
    public var attachedEvidenceStatementIDs: [String]

    public init(
        candidateID: String,
        createdEntityIDs: [String] = [],
        createdStatementIDs: [String] = [],
        updatedStatementIDs: [String] = [],
        attachedEvidenceStatementIDs: [String] = []
    ) {
        self.candidateID = candidateID
        self.createdEntityIDs = createdEntityIDs
        self.createdStatementIDs = createdStatementIDs
        self.updatedStatementIDs = updatedStatementIDs
        self.attachedEvidenceStatementIDs = attachedEvidenceStatementIDs
    }
}

public struct GraphWriteCandidateValidationResult: Sendable, Equatable {
    public var errors: [String]
    public var warnings: [String]
    public var isValid: Bool { errors.isEmpty }

    public init(errors: [String] = [], warnings: [String] = []) {
        self.errors = errors
        self.warnings = warnings
    }
}

public struct GraphWriteCandidateValidator: Sendable {
    public init() {}

    public func validate(_ candidate: GraphWriteCandidate, store: SQLiteGraphKernelStore) -> GraphWriteCandidateValidationResult {
        do {
            _ = try GraphWriteCandidateDraftBuilder(store: store).draft(for: candidate)
            return GraphWriteCandidateValidationResult(warnings: ["Reviewed candidate will be routed through resolver/admission/optimistic write before commit."])
        } catch {
            return GraphWriteCandidateValidationResult(errors: [String(describing: error)])
        }
    }
}

public struct GraphWriteCandidateCommitService: Sendable {
    public var admissionPolicy: GraphWriteAdmissionPolicy

    public init(admissionPolicy: GraphWriteAdmissionPolicy = GraphWriteAdmissionPolicy()) {
        self.admissionPolicy = admissionPolicy
    }

    public func commit(_ candidate: GraphWriteCandidate, store: SQLiteGraphKernelStore) throws -> GraphWriteCandidateCommitResult {
        guard candidate.status == .approved else {
            throw GraphWriteCandidateCommitError.notApproved(candidate.id)
        }
        let draftBuilder = GraphWriteCandidateDraftBuilder(store: store)
        let extractedDraft = try draftBuilder.draft(for: candidate)
        let optimisticWriter = GraphOptimisticWriteService(store: store)
        let resolutionPlan = try GraphEntityResolutionPlanner(resolver: optimisticWriter.resolver).plan(for: extractedDraft)
        let conflictPreview = try GraphExtractionConflictPreflight(store: store, detector: optimisticWriter.contradictionDetector)
            .preview(draft: extractedDraft, resolutionPlan: resolutionPlan)
        let draft = extractedDraft
            .withEntityResolutionPlanMetadata(resolutionPlan)
            .withConflictPreviewMetadata(conflictPreview)
        let admission = try admissionPolicy.decide(draft: draft, resolutionPlan: resolutionPlan, conflictPreview: conflictPreview)
        guard admission.action == .autoCommit else {
            throw GraphWriteCandidateCommitError.admissionRejected(admission.action, admission.reasons)
        }
        let writeResult = try optimisticWriter.commit(try draft.toOptimisticWriteBatch())
        var committed = candidate
        committed.status = .committed
        committed.updatedAt = Date()
        try store.upsertWriteCandidate(committed)
        return GraphWriteCandidateCommitResult(
            candidateID: candidate.id,
            createdEntityIDs: writeResult.committedEntityIDs,
            createdStatementIDs: writeResult.committedStatementIDs,
            updatedStatementIDs: [],
            attachedEvidenceStatementIDs: writeResult.committedEpisodeID.map { [$0] } ?? []
        )
    }
}

public enum GraphWriteCandidateCommitError: Error, Sendable, Equatable, CustomStringConvertible {
    case notApproved(String)
    case permissionDenied(String)
    case validationFailed([String])
    case unsupportedCandidateKind(GraphWriteCandidateKind)
    case admissionRejected(GraphWriteAdmissionDecisionAction, [GraphWriteAdmissionReason])
    case missingEntity(String)
    case missingStatement(String)
    case invalidPayload(String)

    public var description: String {
        switch self {
        case .notApproved(let id): return "Candidate must be approved before commit: \(id)"
        case .permissionDenied(let reason): return "Permission denied for graph write commit: \(reason)"
        case .validationFailed(let errors): return "Graph write candidate validation failed: \(errors.joined(separator: "; "))"
        case .unsupportedCandidateKind(let kind): return "Reviewed graph write candidate kind is not yet supported by resolver-backed commit: \(kind.rawValue)"
        case .admissionRejected(let action, let reasons): return "Graph write candidate did not pass admission policy: \(action.rawValue) / \(reasons.map(\.rawValue).joined(separator: ", "))"
        case .missingEntity(let id): return "Missing graph entity: \(id)"
        case .missingStatement(let id): return "Missing graph statement: \(id)"
        case .invalidPayload(let message): return "Invalid graph write candidate payload: \(message)"
        }
    }
}

private struct GraphWriteCandidateDraftBuilder: Sendable {
    var store: SQLiteGraphKernelStore

    func draft(for candidate: GraphWriteCandidate) throws -> GraphExtractionDraft {
        let payload = try payloadDictionary(candidate.payloadJSON)
        let source = GraphExtractionSource(
            id: "candidate-\(candidate.id)",
            graphID: candidate.groupID,
            sourceType: .manual,
            title: candidate.rationale,
            content: candidate.payloadJSON,
            occurredAt: candidate.createdAt,
            metadata: [
                "candidate_id": candidate.id,
                "candidate_kind": candidate.kind.rawValue,
                "proposed_by_run_id": candidate.proposedByRunID
            ]
        )
        switch candidate.kind {
        case .createNode, .updateNode:
            return GraphExtractionDraft(source: source, entities: [try entityDraft(from: payload, fallbackID: candidate.id, confidence: candidate.confidence)])
        case .createFact, .updateFact:
            let subjectID = try requiredString(payload, keys: ["subjectEntityID", "sourceEntityID", "sourceNodeID", "subjectNodeID"])
            let objectID = try requiredString(payload, keys: ["objectEntityID", "targetEntityID", "targetNodeID", "objectNodeID"])
            let subject = try existingEntityDraft(id: subjectID, localID: "subject")
            let object = try existingEntityDraft(id: objectID, localID: "object")
            let predicateRaw = try requiredString(payload, keys: ["predicate", "relation"])
            guard let predicate = GraphPredicate(rawValue: predicateRaw) else {
                throw GraphWriteCandidateCommitError.invalidPayload("Unsupported predicate/relation: \(predicateRaw)")
            }
            let text = (payload["statementText"] as? String) ?? (payload["fact"] as? String) ?? candidate.rationale
            let statement = GraphExtractedStatementDraft(
                subjectLocalID: subject.localID,
                predicate: predicate,
                objectLocalID: object.localID,
                statementText: text,
                confidence: candidate.confidence,
                metadata: ["evidence_text": candidate.rationale, "candidate_id": candidate.id]
            )
            return GraphExtractionDraft(source: source, entities: [subject, object], statements: [statement])
        case .invalidateFact, .attachEvidence, .createMention:
            throw GraphWriteCandidateCommitError.unsupportedCandidateKind(candidate.kind)
        }
    }

    private func entityDraft(from payload: [String: Any], fallbackID: String, confidence: Double) throws -> GraphExtractedEntityDraft {
        let name = (payload["name"] as? String)
            ?? (payload["canonicalName"] as? String)
            ?? (payload["title"] as? String)
            ?? (payload["label"] as? String)
        guard let name, !name.isEmpty else {
            throw GraphWriteCandidateCommitError.invalidPayload("createNode requires name/canonicalName/title")
        }
        let localID = (payload["localID"] as? String) ?? (payload["id"] as? String) ?? fallbackID
        return GraphExtractedEntityDraft(
            localID: localID,
            name: name,
            entityKind: graphEntityKind(from: payload["entityKind"] as? String ?? payload["nodeType"] as? String),
            scope: GraphScope(rawValue: payload["scope"] as? String ?? "project") ?? .project,
            canonicalClassID: payload["canonicalClassID"] as? String,
            aliases: payload["aliases"] as? [String] ?? [],
            summary: payload["summary"] as? String ?? "",
            confidence: confidence,
            metadata: ["candidate_payload_id": payload["id"] as? String ?? localID]
        )
    }

    private func existingEntityDraft(id: String, localID: String) throws -> GraphExtractedEntityDraft {
        guard let entity = try store.entity(id: id) else { throw GraphWriteCandidateCommitError.missingEntity(id) }
        return GraphExtractedEntityDraft(
            localID: localID,
            name: entity.name,
            entityKind: entity.entityKind,
            scope: entity.scope,
            canonicalClassID: entity.canonicalClassID,
            aliases: entity.aliases,
            summary: entity.summary,
            confidence: entity.confidence,
            metadata: ["existing_entity_id": entity.id]
        )
    }

    private func payloadDictionary(_ json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let dictionary = object as? [String: Any] else {
            throw GraphWriteCandidateCommitError.invalidPayload("payloadJSON must be a JSON object")
        }
        return dictionary
    }

    private func requiredString(_ payload: [String: Any], keys: [String]) throws -> String {
        for key in keys {
            if let value = payload[key] as? String, !value.isEmpty { return value }
        }
        throw GraphWriteCandidateCommitError.invalidPayload("Missing required field: \(keys.joined(separator: "/"))")
    }

    private func graphEntityKind(from rawValue: String?) -> GraphEntityKind {
        guard let rawValue else { return .entity }
        return GraphEntityKind(rawValue: rawValue) ?? .entity
    }
}
