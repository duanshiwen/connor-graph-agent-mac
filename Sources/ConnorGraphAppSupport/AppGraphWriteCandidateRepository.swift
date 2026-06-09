import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public struct AppGraphWriteCandidateRepository: @unchecked Sendable {
    public let store: SQLiteGraphStore
    public var committer: GraphWriteCandidateCommitService
    public var validator: GraphWriteCandidateValidator
    private let auditLog: any AgentAuditLog
    private let policyEngine: AgentPolicyEngine

    public init(
        store: SQLiteGraphStore,
        committer: GraphWriteCandidateCommitService = GraphWriteCandidateCommitService(),
        validator: GraphWriteCandidateValidator = GraphWriteCandidateValidator(),
        permissionMode: AgentPermissionMode = .trustedWrite,
        auditLog: (any AgentAuditLog)? = nil
    ) {
        self.store = store
        self.committer = committer
        self.validator = validator
        let resolvedAuditLog = auditLog ?? SQLiteAgentAuditLog(store: store)
        self.auditLog = resolvedAuditLog
        self.policyEngine = AgentPolicyEngine(permissionMode: permissionMode, auditLog: resolvedAuditLog)
    }

    public func loadCandidates(status: GraphWriteCandidateStatus? = nil, limit: Int = 100) throws -> [GraphWriteCandidate] {
        try store.graphWriteCandidates(status: status, limit: limit)
    }

    public func loadAuditTimeline(for candidate: GraphWriteCandidate) throws -> [GraphWriteCandidateAuditPresentation] {
        try store.agentAuditEvents(runID: candidate.proposedByRunID)
            .filter { event in
                guard let payload = try? Self.payloadDictionary(from: event.payloadJSON) else { return false }
                return payload["candidateID"] as? String == candidate.id
            }
            .map(GraphWriteCandidateAuditPresentation.init(event:))
    }

    public func loadAuditTimelines(for candidates: [GraphWriteCandidate]) throws -> [String: [GraphWriteCandidateAuditPresentation]] {
        var grouped: [String: [GraphWriteCandidateAuditPresentation]] = [:]
        for candidate in candidates {
            grouped[candidate.id] = try loadAuditTimeline(for: candidate)
        }
        return grouped
    }

    private static func payloadDictionary(from json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    @discardableResult
    public func approve(_ candidate: GraphWriteCandidate) throws -> GraphWriteCandidate {
        var updated = candidate
        updated.status = .approved
        updated.updatedAt = Date()
        try store.upsert(graphWriteCandidate: updated)
        return updated
    }

    @discardableResult
    public func approveGoverned(_ candidate: GraphWriteCandidate, actor: String = "human-reviewer") async throws -> GraphWriteCandidate {
        let validated = try await validateGoverned(candidate, actor: actor)
        guard validated.validation.isValid else {
            throw GraphWriteCandidateCommitError.validationFailed(validated.validation.errors)
        }
        let updated = try approve(validated.candidate)
        await auditLog.record(AgentAuditEvent(
            runID: candidate.proposedByRunID,
            sessionID: candidate.groupID,
            eventType: .graphWriteCandidateApproved,
            actor: actor,
            capability: .commitGraphWrite,
            payloadJSON: auditPayload(candidate: updated)
        ))
        return updated
    }

    @discardableResult
    public func reject(_ candidate: GraphWriteCandidate, reason: String? = nil) throws -> GraphWriteCandidate {
        var updated = candidate
        updated.status = .rejected
        updated.updatedAt = Date()
        if let reason, !reason.isEmpty {
            updated.validationErrors.append(reason)
        }
        try store.upsert(graphWriteCandidate: updated)
        return updated
    }

    @discardableResult
    public func rejectGoverned(_ candidate: GraphWriteCandidate, reason: String? = nil, actor: String = "human-reviewer") async throws -> GraphWriteCandidate {
        let updated = try reject(candidate, reason: reason)
        await auditLog.record(AgentAuditEvent(
            runID: candidate.proposedByRunID,
            sessionID: candidate.groupID,
            eventType: .graphWriteCandidateRejected,
            actor: actor,
            capability: .commitGraphWrite,
            payloadJSON: auditPayload(candidate: updated, extra: ["reason": reason ?? ""])
        ))
        return updated
    }

    @discardableResult
    public func commit(_ candidate: GraphWriteCandidate) throws -> GraphWriteCandidateCommitResult {
        let approved = candidate.status == .approved ? candidate : try approve(candidate)
        let result = try committer.commit(approved, store: store)
        var updated = approved
        updated.status = .committed
        updated.updatedAt = Date()
        try store.upsert(graphWriteCandidate: updated)
        return result
    }

    @discardableResult
    public func validateGoverned(_ candidate: GraphWriteCandidate, actor: String = "agent-runtime") async throws -> (candidate: GraphWriteCandidate, validation: GraphWriteCandidateValidationResult) {
        await auditLog.record(AgentAuditEvent(
            runID: candidate.proposedByRunID,
            sessionID: candidate.groupID,
            eventType: .graphWriteValidationStarted,
            actor: actor,
            capability: .commitGraphWrite,
            payloadJSON: auditPayload(candidate: candidate)
        ))
        let validation = validator.validate(candidate, store: store)
        var updated = candidate
        updated.validationErrors = validation.errors
        updated.updatedAt = Date()
        if validation.isValid {
            if updated.status == .pendingValidation || updated.status == .validationFailed {
                updated.status = .pendingReview
            }
            try store.upsert(graphWriteCandidate: updated)
            await auditLog.record(AgentAuditEvent(
                runID: candidate.proposedByRunID,
                sessionID: candidate.groupID,
                eventType: .graphWriteValidationFinished,
                actor: actor,
                capability: .commitGraphWrite,
                payloadJSON: auditPayload(candidate: updated, extra: ["result": "valid"])
            ))
        } else {
            updated.status = .validationFailed
            try store.upsert(graphWriteCandidate: updated)
            await auditLog.record(AgentAuditEvent(
                runID: candidate.proposedByRunID,
                sessionID: candidate.groupID,
                eventType: .graphWriteValidationFailed,
                actor: actor,
                capability: .commitGraphWrite,
                payloadJSON: auditPayload(candidate: updated, extra: ["errors": validation.errors.joined(separator: " | ")])
            ))
        }
        return (updated, validation)
    }

    @discardableResult
    public func commitGoverned(_ candidate: GraphWriteCandidate, actor: String = "human-reviewer") async throws -> GraphWriteCandidateCommitResult {
        let validated = try await validateGoverned(candidate, actor: actor)
        guard validated.validation.isValid else {
            throw GraphWriteCandidateCommitError.validationFailed(validated.validation.errors)
        }
        let candidate = validated.candidate
        let payload = auditPayload(candidate: candidate)
        let decision = await policyEngine.evaluate(
            capability: .commitGraphWrite,
            runID: candidate.proposedByRunID,
            sessionID: candidate.groupID,
            toolName: "graph_write_candidate_commit",
            payloadJSON: payload
        )
        guard decision.outcome != .denied else {
            await auditLog.record(AgentAuditEvent(
                runID: candidate.proposedByRunID,
                sessionID: candidate.groupID,
                eventType: .graphWriteCommitFailed,
                actor: actor,
                capability: .commitGraphWrite,
                decision: decision,
                payloadJSON: auditPayload(candidate: candidate, extra: ["error": GraphWriteCandidateCommitError.permissionDenied(decision.reason).description])
            ))
            throw GraphWriteCandidateCommitError.permissionDenied(decision.reason)
        }

        await auditLog.record(AgentAuditEvent(
            runID: candidate.proposedByRunID,
            sessionID: candidate.groupID,
            eventType: .graphWriteCommitStarted,
            actor: actor,
            capability: .commitGraphWrite,
            decision: decision,
            payloadJSON: payload
        ))
        do {
            guard candidate.status == .approved else {
                throw GraphWriteCandidateCommitError.notApproved(candidate.id)
            }
            let result = try committer.commit(candidate, store: store)
            var updated = candidate
            updated.status = .committed
            updated.updatedAt = Date()
            try store.upsert(graphWriteCandidate: updated)
            await auditLog.record(AgentAuditEvent(
                runID: candidate.proposedByRunID,
                sessionID: candidate.groupID,
                eventType: .graphWriteCommitFinished,
                actor: actor,
                capability: .commitGraphWrite,
                decision: decision,
                payloadJSON: auditPayload(candidate: updated, result: result)
            ))
            return result
        } catch {
            await auditLog.record(AgentAuditEvent(
                runID: candidate.proposedByRunID,
                sessionID: candidate.groupID,
                eventType: .graphWriteCommitFailed,
                actor: actor,
                capability: .commitGraphWrite,
                decision: decision,
                payloadJSON: auditPayload(candidate: candidate, extra: ["error": String(describing: error)])
            ))
            throw error
        }
    }

    private func auditPayload(candidate: GraphWriteCandidate, result: GraphWriteCandidateCommitResult? = nil, extra: [String: String] = [:]) -> String {
        var payload: [String: Any] = [
            "candidateID": candidate.id,
            "groupID": candidate.groupID,
            "kind": candidate.kind.rawValue,
            "status": candidate.status.rawValue,
            "proposedByRunID": candidate.proposedByRunID,
            "confidence": candidate.confidence
        ]
        if let result {
            payload["createdNodeIDs"] = result.createdNodeIDs
            payload["createdFactIDs"] = result.createdFactIDs
            payload["updatedFactIDs"] = result.updatedFactIDs
            payload["attachedEvidenceFactIDs"] = result.attachedEvidenceFactIDs
        }
        extra.forEach { payload[$0.key] = $0.value }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

public enum GraphWriteCandidateAuditSeverity: String, Sendable, Equatable {
    case info
    case success
    case warning
    case error
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
        self.id = event.id
        self.actor = event.actor
        self.createdAt = event.createdAt
        switch event.eventType {
        case .permissionDecision:
            self.title = "Permission decision"
            let outcome = event.decision?.outcome.rawValue ?? "unknown"
            self.detail = "\(event.capability?.rawValue ?? "capability") → \(outcome). \(event.decision?.reason ?? "")"
            self.severity = event.decision?.outcome == .denied ? .error : (event.decision?.outcome == .needsApproval ? .warning : .success)
        case .graphWriteCandidateApproved:
            self.title = "Candidate approved"
            self.detail = "Human reviewer approved this candidate."
            self.severity = .success
        case .graphWriteCandidateRejected:
            self.title = "Candidate rejected"
            self.detail = Self.payloadValue("reason", from: event.payloadJSON) ?? "Human reviewer rejected this candidate."
            self.severity = .error
        case .graphWriteValidationStarted:
            self.title = "Validation started"
            self.detail = "Typed schema and graph integrity checks started."
            self.severity = .info
        case .graphWriteValidationFinished:
            self.title = "Validation passed"
            self.detail = "Candidate is valid and ready for review."
            self.severity = .success
        case .graphWriteValidationFailed:
            self.title = "Validation failed"
            self.detail = Self.payloadValue("errors", from: event.payloadJSON) ?? "Validation failed."
            self.severity = .error
        case .graphWriteCommitStarted:
            self.title = "Commit started"
            self.detail = "Durable graph mutation started after permission governance."
            self.severity = .info
        case .graphWriteCommitFinished:
            self.title = "Commit finished"
            self.detail = Self.commitSummary(from: event.payloadJSON)
            self.severity = .success
        case .graphWriteCommitFailed:
            self.title = "Commit failed"
            self.detail = Self.payloadValue("error", from: event.payloadJSON) ?? "Commit failed."
            self.severity = .error
        case .toolStarted, .toolFinished, .toolFailed:
            self.title = event.eventType.rawValue
            self.detail = event.toolName ?? event.payloadJSON
            self.severity = event.eventType == .toolFailed ? .error : .info
        }
    }

    private static func payloadValue(_ key: String, from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object[key] as? String
    }

    private static func commitSummary(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "Commit finished." }
        let createdNodes = object["createdNodeIDs"] as? [String] ?? []
        let createdFacts = object["createdFactIDs"] as? [String] ?? []
        let updatedFacts = object["updatedFactIDs"] as? [String] ?? []
        let attachedEvidence = object["attachedEvidenceFactIDs"] as? [String] ?? []
        return "nodes +\(createdNodes.count), facts +\(createdFacts.count), updated facts \(updatedFacts.count), evidence links \(attachedEvidence.count)"
    }
}

public struct GraphWriteCandidateCommitResult: Sendable, Equatable {
    public var candidateID: String
    public var createdNodeIDs: [String]
    public var createdFactIDs: [String]
    public var updatedFactIDs: [String]
    public var attachedEvidenceFactIDs: [String]

    public init(candidateID: String, createdNodeIDs: [String] = [], createdFactIDs: [String] = [], updatedFactIDs: [String] = [], attachedEvidenceFactIDs: [String] = []) {
        self.candidateID = candidateID
        self.createdNodeIDs = createdNodeIDs
        self.createdFactIDs = createdFactIDs
        self.updatedFactIDs = updatedFactIDs
        self.attachedEvidenceFactIDs = attachedEvidenceFactIDs
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
    private let decoder: JSONDecoder

    public init() {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func validate(_ candidate: GraphWriteCandidate, store: SQLiteGraphStore) -> GraphWriteCandidateValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        if candidate.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("rationale is required")
        }
        if !(0...1).contains(candidate.confidence) {
            errors.append("confidence must be between 0 and 1")
        }
        if candidate.payloadJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("payloadJSON is required")
        }

        do {
            switch candidate.kind {
            case .createNode:
                let payload = try decoder.decode(CreateNodePayload.self, from: Data(candidate.payloadJSON.utf8))
                validateNonEmpty(payload.canonicalName, field: "canonicalName", errors: &errors)
                validateNonEmpty(payload.title, field: "title", errors: &errors)
                if let confidence = payload.confidence, !(0...1).contains(confidence) {
                    errors.append("payload.confidence must be between 0 and 1")
                }
                if let id = payload.id, let existing = try store.graphNodeV2(id: id) {
                    errors.append("node id already exists: \(existing.id)")
                }

            case .createFact:
                let payload = try decoder.decode(CreateFactPayload.self, from: Data(candidate.payloadJSON.utf8))
                validateNonEmpty(payload.sourceNodeID, field: "sourceNodeID", errors: &errors)
                validateNonEmpty(payload.targetNodeID, field: "targetNodeID", errors: &errors)
                validateNonEmpty(payload.fact, field: "fact", errors: &errors)
                if payload.sourceNodeID == payload.targetNodeID {
                    warnings.append("sourceNodeID and targetNodeID are identical; verify self-relation is intentional")
                }
                if let confidence = payload.confidence, !(0...1).contains(confidence) {
                    errors.append("payload.confidence must be between 0 and 1")
                }
                if let source = try store.graphNodeV2(id: payload.sourceNodeID) {
                    if source.groupID != candidate.groupID { errors.append("source node belongs to another group: \(payload.sourceNodeID)") }
                } else {
                    errors.append("missing source node: \(payload.sourceNodeID)")
                }
                if let target = try store.graphNodeV2(id: payload.targetNodeID) {
                    if target.groupID != candidate.groupID { errors.append("target node belongs to another group: \(payload.targetNodeID)") }
                } else {
                    errors.append("missing target node: \(payload.targetNodeID)")
                }
                if let id = payload.id, try store.graphFact(id: id) != nil {
                    errors.append("fact id already exists: \(id)")
                }
                try validateEpisodeIDs(candidate.sourceEpisodeIDs + payload.sourceEpisodeIDs, store: store, errors: &errors)

            case .invalidateFact:
                let payload = try decoder.decode(InvalidateFactPayload.self, from: Data(candidate.payloadJSON.utf8))
                validateNonEmpty(payload.factID, field: "factID", errors: &errors)
                if let fact = try store.graphFact(id: payload.factID) {
                    if fact.groupID != candidate.groupID { errors.append("fact belongs to another group: \(payload.factID)") }
                    if fact.status != .active { warnings.append("fact is not active: \(payload.factID)") }
                } else {
                    errors.append("missing fact: \(payload.factID)")
                }
                if let invalidatedByFactID = payload.invalidatedByFactID, try store.graphFact(id: invalidatedByFactID) == nil {
                    errors.append("missing invalidatedByFactID: \(invalidatedByFactID)")
                }

            case .attachEvidence:
                let payload = try decoder.decode(AttachEvidencePayload.self, from: Data(candidate.payloadJSON.utf8))
                validateNonEmpty(payload.factID, field: "factID", errors: &errors)
                if let fact = try store.graphFact(id: payload.factID) {
                    if fact.groupID != candidate.groupID { errors.append("fact belongs to another group: \(payload.factID)") }
                } else {
                    errors.append("missing fact: \(payload.factID)")
                }
                let episodeIDs = candidate.sourceEpisodeIDs + payload.episodeIDs
                if episodeIDs.isEmpty { errors.append("at least one episodeID is required") }
                try validateEpisodeIDs(episodeIDs, store: store, errors: &errors)

            case .updateNode, .updateFact, .createMention:
                errors.append("unsupported candidate kind for validation/commit: \(candidate.kind.rawValue)")
            }
        } catch let decodingError as DecodingError {
            errors.append("invalid payload schema: \(decodingError)")
        } catch {
            errors.append("validation failed: \(error)")
        }

        return GraphWriteCandidateValidationResult(errors: errors, warnings: warnings)
    }

    private func validateNonEmpty(_ value: String, field: String, errors: inout [String]) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("\(field) is required")
        }
    }

    private func validateEpisodeIDs(_ episodeIDs: [String], store: SQLiteGraphStore, errors: inout [String]) throws {
        for episodeID in Set(episodeIDs) where !episodeID.isEmpty {
            if try store.graphEpisode(id: episodeID) == nil {
                errors.append("missing source episode: \(episodeID)")
            }
        }
    }
}

public struct GraphWriteCandidateCommitService: Sendable {
    private let decoder: JSONDecoder

    public init() {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func commit(_ candidate: GraphWriteCandidate, store: SQLiteGraphStore) throws -> GraphWriteCandidateCommitResult {
        guard candidate.status == .approved else {
            throw GraphWriteCandidateCommitError.notApproved(candidate.id)
        }
        switch candidate.kind {
        case .createNode:
            let payload = try decoder.decode(CreateNodePayload.self, from: Data(candidate.payloadJSON.utf8))
            let node = GraphNodeV2(
                id: payload.id ?? UUID().uuidString,
                groupID: candidate.groupID,
                stableKey: payload.stableKey,
                type: payload.nodeType,
                canonicalName: payload.canonicalName,
                title: payload.title,
                summary: payload.summary,
                labels: payload.labels,
                attributes: payload.attributes,
                confidence: payload.confidence ?? candidate.confidence,
                metadata: payload.metadata.merging(["committedFromCandidateID": candidate.id]) { current, _ in current }
            )
            try store.upsert(nodeV2: node)
            return GraphWriteCandidateCommitResult(candidateID: candidate.id, createdNodeIDs: [node.id])

        case .createFact:
            let payload = try decoder.decode(CreateFactPayload.self, from: Data(candidate.payloadJSON.utf8))
            guard try store.graphNodeV2(id: payload.sourceNodeID) != nil else { throw GraphWriteCandidateCommitError.missingNode(payload.sourceNodeID) }
            guard try store.graphNodeV2(id: payload.targetNodeID) != nil else { throw GraphWriteCandidateCommitError.missingNode(payload.targetNodeID) }
            let fact = GraphFact(
                id: payload.id ?? UUID().uuidString,
                groupID: candidate.groupID,
                sourceNodeID: payload.sourceNodeID,
                targetNodeID: payload.targetNodeID,
                relation: payload.relation,
                fact: payload.fact,
                confidence: payload.confidence ?? candidate.confidence,
                validAt: payload.validAt,
                referenceTime: payload.referenceTime,
                attributes: payload.attributes,
                metadata: payload.metadata.merging(["committedFromCandidateID": candidate.id]) { current, _ in current }
            )
            try store.upsert(fact: fact, sourceEpisodeIDs: candidate.sourceEpisodeIDs + payload.sourceEpisodeIDs)
            return GraphWriteCandidateCommitResult(candidateID: candidate.id, createdFactIDs: [fact.id])

        case .invalidateFact:
            let payload = try decoder.decode(InvalidateFactPayload.self, from: Data(candidate.payloadJSON.utf8))
            guard var fact = try store.graphFact(id: payload.factID) else { throw GraphWriteCandidateCommitError.missingFact(payload.factID) }
            fact.status = .invalidated
            fact.invalidAt = payload.invalidAt ?? Date()
            fact.invalidatedByFactID = payload.invalidatedByFactID
            fact.updatedAt = Date()
            fact.metadata["invalidatedFromCandidateID"] = candidate.id
            if let reason = payload.reason { fact.metadata["invalidationReason"] = reason }
            try store.upsert(fact: fact)
            return GraphWriteCandidateCommitResult(candidateID: candidate.id, updatedFactIDs: [fact.id])

        case .attachEvidence:
            let payload = try decoder.decode(AttachEvidencePayload.self, from: Data(candidate.payloadJSON.utf8))
            guard let fact = try store.graphFact(id: payload.factID) else { throw GraphWriteCandidateCommitError.missingFact(payload.factID) }
            try store.upsert(fact: fact, sourceEpisodeIDs: candidate.sourceEpisodeIDs + payload.episodeIDs)
            return GraphWriteCandidateCommitResult(candidateID: candidate.id, attachedEvidenceFactIDs: [fact.id])

        case .updateNode, .updateFact, .createMention:
            throw GraphWriteCandidateCommitError.unsupportedCandidateKind(candidate.kind)
        }
    }
}

public enum GraphWriteCandidateCommitError: Error, Sendable, Equatable, CustomStringConvertible {
    case notApproved(String)
    case permissionDenied(String)
    case validationFailed([String])
    case unsupportedCandidateKind(GraphWriteCandidateKind)
    case missingNode(String)
    case missingFact(String)

    public var description: String {
        switch self {
        case .notApproved(let id): return "Candidate must be approved before commit: \(id)"
        case .permissionDenied(let reason): return "Permission denied for graph write commit: \(reason)"
        case .validationFailed(let errors): return "Graph write candidate validation failed: \(errors.joined(separator: "; "))"
        case .unsupportedCandidateKind(let kind): return "Unsupported candidate kind for commit: \(kind.rawValue)"
        case .missingNode(let id): return "Missing graph node: \(id)"
        case .missingFact(let id): return "Missing graph fact: \(id)"
        }
    }
}

private struct CreateNodePayload: Decodable {
    var id: String?
    var stableKey: String?
    var nodeType: NodeType
    var canonicalName: String
    var title: String
    var summary: String
    var labels: [String]
    var attributes: [String: String]
    var confidence: Double?
    var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, stableKey, nodeType, canonicalName, title, summary, labels, attributes, confidence, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        stableKey = try c.decodeIfPresent(String.self, forKey: .stableKey)
        nodeType = try c.decode(NodeType.self, forKey: .nodeType)
        canonicalName = try c.decode(String.self, forKey: .canonicalName)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
        attributes = try c.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

private struct CreateFactPayload: Decodable {
    var id: String?
    var sourceNodeID: String
    var targetNodeID: String
    var relation: RelationType
    var fact: String
    var confidence: Double?
    var validAt: Date?
    var referenceTime: Date?
    var sourceEpisodeIDs: [String]
    var attributes: [String: String]
    var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, sourceNodeID, targetNodeID, relation, fact, confidence, validAt, referenceTime, sourceEpisodeIDs, attributes, metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        sourceNodeID = try c.decode(String.self, forKey: .sourceNodeID)
        targetNodeID = try c.decode(String.self, forKey: .targetNodeID)
        relation = try c.decode(RelationType.self, forKey: .relation)
        fact = try c.decode(String.self, forKey: .fact)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        validAt = try c.decodeIfPresent(Date.self, forKey: .validAt)
        referenceTime = try c.decodeIfPresent(Date.self, forKey: .referenceTime)
        sourceEpisodeIDs = try c.decodeIfPresent([String].self, forKey: .sourceEpisodeIDs) ?? []
        attributes = try c.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        metadata = try c.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

private struct InvalidateFactPayload: Decodable {
    var factID: String
    var reason: String?
    var invalidAt: Date?
    var invalidatedByFactID: String?
}

private struct AttachEvidencePayload: Decodable {
    var factID: String
    var episodeIDs: [String]
}
