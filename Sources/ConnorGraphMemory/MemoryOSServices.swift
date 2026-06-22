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
        if trimmed.count < 3 {
            return MemoryOSPreIngestionDecision(action: .discard, reason: "too_short", confidence: 0.9)
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

    public init(sourceType: MemoryOSSourceType, sourceID: String? = nil, title: String, content: String, occurredAt: Date = Date(), sessionID: String? = nil, workObjectID: String? = nil) {
        self.sourceType = sourceType; self.sourceID = sourceID; self.title = title; self.content = content; self.occurredAt = occurredAt; self.sessionID = sessionID; self.workObjectID = workObjectID
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
        let object = MemoryOSProvenanceObject(sourceType: input.sourceType, sourceID: input.sourceID, title: input.title, content: input.content, contentHash: hash, occurredAt: input.occurredAt, ingestedAt: now, sessionID: input.sessionID, workObjectID: input.workObjectID)
        let span = MemoryOSProvenanceSpan(provenanceObjectID: object.id, startOffset: 0, endOffset: input.content.count, text: input.content)
        let event = MemoryOSCaptureEvent(provenanceObjectID: object.id, eventType: input.sourceType.rawValue, occurredAt: input.occurredAt, tokenEstimate: max(1, input.content.count / 4), metadata: ["span_id": span.id])
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
        guard artifact.schemaName == "GraphStructuredExtractionOutput" else {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "unsupported_schema", message: "Unsupported artifact schema: \(artifact.schemaName).")])
        }
        guard let data = artifact.rawContent.data(using: .utf8) else {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "invalid_utf8", message: "Artifact content is not valid UTF-8.")])
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let output = try decoder.decode(GraphStructuredExtractionOutput.self, from: data)
            try output.validate(requireStatementEvidence: true)
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: true, normalizedRecordCount: output.entities.count + output.statements.count)
        } catch let error as GraphStructuredExtractionValidationError {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "schema_validation_failed", message: error.description)])
        } catch {
            return MemoryOSArtifactValidationResult(artifactID: artifact.id, accepted: false, issues: [MemoryOSValidationIssue(code: "json_decode_failed", message: String(describing: error))])
        }
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
        if let invalidAt = statement.invalidAt, invalidAt < statement.validAt { issues.append(MemoryOSValidationIssue(code: "invalid_temporal_range", message: "invalidAt must not be earlier than validAt.")) }
        if [.observed, .confirmed].contains(statement.status), statement.evidenceSpanIDs.isEmpty { issues.append(MemoryOSValidationIssue(code: "missing_evidence", message: "Observed or confirmed statements require evidence spans.")) }
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

    public func currentProjection(statements: [MemoryOSStatement]) -> [MemoryOSStatement] {
        let valid = statements.filter { ![.rejected, .invalidated, .superseded].contains($0.status) }
        return valid.sorted {
            if rank($0.status) != rank($1.status) { return rank($0.status) > rank($1.status) }
            return $0.committedAt > $1.committedAt
        }
    }

    private func rank(_ status: MemoryOSStatementStatus) -> Int {
        switch status { case .confirmed: 3; case .observed: 2; case .candidate: 1; case .rejected, .invalidated, .superseded: 0 }
    }
}

public struct MemoryOSBeliefValidator: Sendable {
    public init() {}
    public func validate(_ belief: MemoryOSBelief) -> [MemoryOSValidationIssue] {
        var issues: [MemoryOSValidationIssue] = []
        if belief.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(MemoryOSValidationIssue(code: "empty_belief", message: "Belief statement must not be empty.")) }
        if belief.confidence < 0 || belief.confidence > 1 { issues.append(MemoryOSValidationIssue(code: "confidence_out_of_range", message: "Confidence must be between 0 and 1.")) }
        if belief.status != .proposed && belief.evidenceStatementIDs.isEmpty { issues.append(MemoryOSValidationIssue(code: "missing_belief_evidence", message: "Non-proposed beliefs require evidence statements.")) }
        return issues
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
