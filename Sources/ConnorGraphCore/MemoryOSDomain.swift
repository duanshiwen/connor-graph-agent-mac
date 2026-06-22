import Foundation

public enum MemoryOSConfidentiality: String, Codable, Sendable, Equatable, CaseIterable {
    case `public`
    case `internal`
    case personal
    case sensitive
    case secret
}

public enum MemoryOSRecordStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case active
    case proposed
    case deprecated
    case invalidated
    case archived
    case failed
}

public enum MemoryOSSourceType: String, Codable, Sendable, Equatable, CaseIterable {
    case chatMessage = "chat_message"
    case assistantMessage = "assistant_message"
    case attachment
    case sourceEvent = "source_event"
    case webPage = "web_page"
    case legacyGraphEpisode = "legacy_graph_episode"
    case manual
}

public enum MemoryOSQueueStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case leased
    case processing
    case succeeded
    case retryScheduled = "retry_scheduled"
    case failed
    case deadLetter = "dead_letter"
    case cancelled
}

public enum MemoryOSAssertionKind: String, Codable, Sendable, Equatable, CaseIterable {
    case observed
    case inferred
    case summarized
}

public enum MemoryOSProjectionKind: String, Codable, Sendable, Equatable, CaseIterable {
    case observed
    case inferred
    case summarized
}

public enum MemoryOSHealthStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case healthy
    case warning
    case migrationRequired = "migration_required"
    case failed
}

public struct MemoryOSValidationIssue: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var code: String
    public var message: String
    public var severity: String

    public init(id: String = UUID().uuidString, code: String, message: String, severity: String = "error") {
        self.id = id
        self.code = code
        self.message = message
        self.severity = severity
    }
}

public struct MemoryOSStoreHealthReport: Codable, Sendable, Equatable {
    public var expectedVersion: Int
    public var actualVersion: Int
    public var status: MemoryOSHealthStatus
    public var missingTables: [String]
    public var missingIndexes: [String]
    public var checkedAt: Date

    public init(expectedVersion: Int, actualVersion: Int, status: MemoryOSHealthStatus, missingTables: [String] = [], missingIndexes: [String] = [], checkedAt: Date = Date()) {
        self.expectedVersion = expectedVersion
        self.actualVersion = actualVersion
        self.status = status
        self.missingTables = missingTables
        self.missingIndexes = missingIndexes
        self.checkedAt = checkedAt
    }
}

public struct MemoryOSLLMArtifactEnvelope: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var queueItemID: String?
    public var processingRunID: String?
    public var artifactType: String
    public var schemaName: String
    public var schemaVersion: Int
    public var modelID: String
    public var rawContent: String
    public var contentHash: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, queueItemID: String? = nil, processingRunID: String? = nil, artifactType: String, schemaName: String, schemaVersion: Int = 1, modelID: String, rawContent: String, contentHash: String = "", createdAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id; self.queueItemID = queueItemID; self.processingRunID = processingRunID; self.artifactType = artifactType; self.schemaName = schemaName; self.schemaVersion = schemaVersion; self.modelID = modelID; self.rawContent = rawContent; self.contentHash = contentHash; self.createdAt = createdAt; self.metadata = metadata
    }
}

public struct MemoryOSArtifactValidationResult: Codable, Sendable, Equatable {
    public var artifactID: String
    public var accepted: Bool
    public var issues: [MemoryOSValidationIssue]
    public var normalizedRecordCount: Int

    public init(artifactID: String, accepted: Bool, issues: [MemoryOSValidationIssue] = [], normalizedRecordCount: Int = 0) {
        self.artifactID = artifactID; self.accepted = accepted; self.issues = issues; self.normalizedRecordCount = normalizedRecordCount
    }
}

public struct MemoryOSAuditEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var eventType: String
    public var actor: String
    public var subjectID: String?
    public var payload: [String: String]
    public var createdAt: Date

    public init(id: String = UUID().uuidString, eventType: String, actor: String = "memory-os", subjectID: String? = nil, payload: [String: String] = [:], createdAt: Date = Date()) {
        self.id = id; self.eventType = eventType; self.actor = actor; self.subjectID = subjectID; self.payload = payload; self.createdAt = createdAt
    }
}

public struct MemoryOSProcessingMetric: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var value: Double
    public var dimensions: [String: String]
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, value: Double, dimensions: [String: String] = [:], createdAt: Date = Date()) {
        self.id = id; self.name = name; self.value = value; self.dimensions = dimensions; self.createdAt = createdAt
    }
}

public struct MemoryOSProjectionQueuePayload: Codable, Sendable, Equatable {
    public var rawContent: String
    public var modelID: String
    public var processingRunID: String?
    public var metadata: [String: String]

    public init(rawContent: String, modelID: String, processingRunID: String? = nil, metadata: [String: String] = [:]) {
        self.rawContent = rawContent; self.modelID = modelID; self.processingRunID = processingRunID; self.metadata = metadata
    }
}

public struct MemoryOSQueueOperationalSnapshot: Codable, Sendable, Equatable {
    public var pending: Int
    public var leased: Int
    public var processing: Int
    public var retryScheduled: Int
    public var succeeded: Int
    public var failed: Int
    public var deadLetter: Int
    public var expiredLeases: Int
    public var checkedAt: Date

    public init(pending: Int = 0, leased: Int = 0, processing: Int = 0, retryScheduled: Int = 0, succeeded: Int = 0, failed: Int = 0, deadLetter: Int = 0, expiredLeases: Int = 0, checkedAt: Date = Date()) {
        self.pending = pending; self.leased = leased; self.processing = processing; self.retryScheduled = retryScheduled; self.succeeded = succeeded; self.failed = failed; self.deadLetter = deadLetter; self.expiredLeases = expiredLeases; self.checkedAt = checkedAt
    }
}

public struct MemoryOSProvenanceObject: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceType: MemoryOSSourceType
    public var sourceID: String?
    public var title: String
    public var content: String
    public var contentHash: String
    public var occurredAt: Date
    public var ingestedAt: Date
    public var sessionID: String?
    public var workObjectID: String?
    public var confidentiality: MemoryOSConfidentiality
    public var status: MemoryOSRecordStatus
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, sourceType: MemoryOSSourceType, sourceID: String? = nil, title: String, content: String, contentHash: String = "", occurredAt: Date, ingestedAt: Date = Date(), sessionID: String? = nil, workObjectID: String? = nil, confidentiality: MemoryOSConfidentiality = .personal, status: MemoryOSRecordStatus = .active, metadata: [String: String] = [:]) {
        self.id = id; self.sourceType = sourceType; self.sourceID = sourceID; self.title = title; self.content = content; self.contentHash = contentHash; self.occurredAt = occurredAt; self.ingestedAt = ingestedAt; self.sessionID = sessionID; self.workObjectID = workObjectID; self.confidentiality = confidentiality; self.status = status; self.metadata = metadata
    }
}

public struct MemoryOSProvenanceSpan: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var provenanceObjectID: String
    public var startOffset: Int?
    public var endOffset: Int?
    public var text: String
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, provenanceObjectID: String, startOffset: Int? = nil, endOffset: Int? = nil, text: String, metadata: [String: String] = [:]) {
        self.id = id; self.provenanceObjectID = provenanceObjectID; self.startOffset = startOffset; self.endOffset = endOffset; self.text = text; self.metadata = metadata
    }
}

public struct MemoryOSCaptureEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var provenanceObjectID: String
    public var eventType: String
    public var occurredAt: Date
    public var tokenEstimate: Int
    public var processingState: MemoryOSQueueStatus
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, provenanceObjectID: String, eventType: String, occurredAt: Date, tokenEstimate: Int = 0, processingState: MemoryOSQueueStatus = .pending, metadata: [String: String] = [:]) {
        self.id = id; self.provenanceObjectID = provenanceObjectID; self.eventType = eventType; self.occurredAt = occurredAt; self.tokenEstimate = tokenEstimate; self.processingState = processingState; self.metadata = metadata
    }
}

public struct MemoryOSTimeBlock: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var startedAt: Date
    public var endedAt: Date
    public var tokenEstimate: Int
    public var status: MemoryOSQueueStatus
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, title: String, startedAt: Date, endedAt: Date, tokenEstimate: Int = 0, status: MemoryOSQueueStatus = .pending, metadata: [String: String] = [:]) {
        self.id = id; self.title = title; self.startedAt = startedAt; self.endedAt = endedAt; self.tokenEstimate = tokenEstimate; self.status = status; self.metadata = metadata
    }
}

public struct MemoryOSQueueItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var status: MemoryOSQueueStatus
    public var priority: Int
    public var payloadJSON: String
    public var attemptCount: Int
    public var maxAttempts: Int
    public var nextRunAt: Date
    public var lockedAt: Date?
    public var lockedBy: String?
    public var leaseExpiresAt: Date?
    public var idempotencyKey: String
    public var payloadHash: String
    public var createdAt: Date
    public var updatedAt: Date
    public var errorCode: String?
    public var errorMessage: String?

    public init(id: String = UUID().uuidString, kind: String, status: MemoryOSQueueStatus = .pending, priority: Int = 0, payloadJSON: String = "{}", attemptCount: Int = 0, maxAttempts: Int = 3, nextRunAt: Date = Date(), lockedAt: Date? = nil, lockedBy: String? = nil, leaseExpiresAt: Date? = nil, idempotencyKey: String = UUID().uuidString, payloadHash: String = "", createdAt: Date = Date(), updatedAt: Date = Date(), errorCode: String? = nil, errorMessage: String? = nil) {
        self.id = id; self.kind = kind; self.status = status; self.priority = priority; self.payloadJSON = payloadJSON; self.attemptCount = attemptCount; self.maxAttempts = maxAttempts; self.nextRunAt = nextRunAt; self.lockedAt = lockedAt; self.lockedBy = lockedBy; self.leaseExpiresAt = leaseExpiresAt; self.idempotencyKey = idempotencyKey; self.payloadHash = payloadHash; self.createdAt = createdAt; self.updatedAt = updatedAt; self.errorCode = errorCode; self.errorMessage = errorMessage
    }
}

public struct MemoryOSNode: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var stableKey: String
    public var nodeType: String
    public var name: String
    public var summary: String
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, stableKey: String, nodeType: String, name: String, summary: String = "", createdAt: Date = Date(), updatedAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id; self.stableKey = stableKey; self.nodeType = nodeType; self.name = name; self.summary = summary; self.createdAt = createdAt; self.updatedAt = updatedAt; self.metadata = metadata
    }
}

public struct MemoryOSStatement: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var subjectID: String
    public var predicate: String
    public var objectID: String?
    public var text: String
    public var assertionKind: MemoryOSAssertionKind
    public var confidence: Double
    public var validAt: Date
    public var committedAt: Date
    public var evidenceSpanIDs: [String]
    public var sourceArtifactID: String?
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, subjectID: String, predicate: String, objectID: String? = nil, text: String, assertionKind: MemoryOSAssertionKind = .observed, confidence: Double = 0.5, validAt: Date = Date(), committedAt: Date = Date(), evidenceSpanIDs: [String] = [], sourceArtifactID: String? = nil, metadata: [String: String] = [:]) {
        self.id = id; self.subjectID = subjectID; self.predicate = predicate; self.objectID = objectID; self.text = text; self.assertionKind = assertionKind; self.confidence = confidence; self.validAt = validAt; self.committedAt = committedAt; self.evidenceSpanIDs = evidenceSpanIDs; self.sourceArtifactID = sourceArtifactID; self.metadata = metadata
    }
}

public struct MemoryOSBelief: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var topic: String
    public var statement: String
    public var projectionKind: MemoryOSProjectionKind
    public var confidence: Double
    public var evidenceStatementIDs: [String]
    public var validAt: Date
    public var projectedAt: Date
    public var sourceArtifactID: String?
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, topic: String, statement: String, projectionKind: MemoryOSProjectionKind = .observed, confidence: Double = 0.5, evidenceStatementIDs: [String] = [], validAt: Date = Date(), projectedAt: Date = Date(), sourceArtifactID: String? = nil, metadata: [String: String] = [:]) {
        self.id = id; self.topic = topic; self.statement = statement; self.projectionKind = projectionKind; self.confidence = confidence; self.evidenceStatementIDs = evidenceStatementIDs; self.validAt = validAt; self.projectedAt = projectedAt; self.sourceArtifactID = sourceArtifactID; self.metadata = metadata
    }
}

public struct MemoryOSEntity: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var stableKey: String
    public var entityType: String
    public var name: String
    public var aliases: [String]
    public var summary: String
    public var confidence: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var validFrom: Date?
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, stableKey: String, entityType: String, name: String, aliases: [String] = [], summary: String = "", confidence: Double = 0.5, createdAt: Date = Date(), updatedAt: Date = Date(), validFrom: Date? = nil, metadata: [String: String] = [:]) {
        self.id = id; self.stableKey = stableKey; self.entityType = entityType; self.name = name; self.aliases = aliases; self.summary = summary; self.confidence = confidence; self.createdAt = createdAt; self.updatedAt = updatedAt; self.validFrom = validFrom; self.metadata = metadata
    }
}

public struct MemoryOSEntityStatement: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var entityID: String
    public var predicate: String
    public var objectEntityID: String?
    public var text: String
    public var assertionKind: MemoryOSAssertionKind
    public var confidence: Double
    public var validAt: Date
    public var committedAt: Date
    public var evidenceSpanIDs: [String]
    public var sourceArtifactID: String?
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, entityID: String, predicate: String, objectEntityID: String? = nil, text: String, assertionKind: MemoryOSAssertionKind = .observed, confidence: Double = 0.5, validAt: Date = Date(), committedAt: Date = Date(), evidenceSpanIDs: [String] = [], sourceArtifactID: String? = nil, metadata: [String: String] = [:]) {
        self.id = id; self.entityID = entityID; self.predicate = predicate; self.objectEntityID = objectEntityID; self.text = text; self.assertionKind = assertionKind; self.confidence = confidence; self.validAt = validAt; self.committedAt = committedAt; self.evidenceSpanIDs = evidenceSpanIDs; self.sourceArtifactID = sourceArtifactID; self.metadata = metadata
    }
}

public struct MemoryOSProjectionBatch: Codable, Sendable, Equatable {
    public var artifactID: String
    public var nodes: [MemoryOSNode]
    public var statements: [MemoryOSStatement]
    public var entities: [MemoryOSEntity]
    public var entityStatements: [MemoryOSEntityStatement]
    public var beliefs: [MemoryOSBelief]

    public init(artifactID: String, nodes: [MemoryOSNode] = [], statements: [MemoryOSStatement] = [], entities: [MemoryOSEntity] = [], entityStatements: [MemoryOSEntityStatement] = [], beliefs: [MemoryOSBelief] = []) {
        self.artifactID = artifactID; self.nodes = nodes; self.statements = statements; self.entities = entities; self.entityStatements = entityStatements; self.beliefs = beliefs
    }
}

public struct MemoryOSProjectionBuildResult: Codable, Sendable, Equatable {
    public var accepted: Bool
    public var batch: MemoryOSProjectionBatch?
    public var validation: MemoryOSArtifactValidationResult

    public init(accepted: Bool, batch: MemoryOSProjectionBatch? = nil, validation: MemoryOSArtifactValidationResult) {
        self.accepted = accepted; self.batch = batch; self.validation = validation
    }
}

public struct MemoryOSCurrentViewDiagnostic: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var severity: String
    public var message: String
    public var candidateRecordIDs: [String]
    public var createdAt: Date

    public init(id: String = UUID().uuidString, kind: String, severity: String = "info", message: String, candidateRecordIDs: [String] = [], createdAt: Date = Date()) {
        self.id = id; self.kind = kind; self.severity = severity; self.message = message; self.candidateRecordIDs = candidateRecordIDs; self.createdAt = createdAt
    }
}

public struct MemoryOSCurrentViewRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var layer: String
    public var key: String
    public var value: String
    public var selectedRecordID: String
    public var validAt: Date
    public var confidence: Double
    public var evidenceIDs: [String]
    public var alternativeRecordIDs: [String]
    public var diagnostics: [MemoryOSCurrentViewDiagnostic]

    public init(id: String = UUID().uuidString, layer: String, key: String, value: String, selectedRecordID: String, validAt: Date, confidence: Double, evidenceIDs: [String] = [], alternativeRecordIDs: [String] = [], diagnostics: [MemoryOSCurrentViewDiagnostic] = []) {
        self.id = id; self.layer = layer; self.key = key; self.value = value; self.selectedRecordID = selectedRecordID; self.validAt = validAt; self.confidence = confidence; self.evidenceIDs = evidenceIDs; self.alternativeRecordIDs = alternativeRecordIDs; self.diagnostics = diagnostics
    }
}

public struct MemoryOSEntityCurrentProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var entityID: String
    public var generatedAt: Date
    public var records: [MemoryOSCurrentViewRecord]
    public var diagnostics: [MemoryOSCurrentViewDiagnostic]

    public init(id: String = UUID().uuidString, entityID: String, generatedAt: Date = Date(), records: [MemoryOSCurrentViewRecord] = [], diagnostics: [MemoryOSCurrentViewDiagnostic] = []) {
        self.id = id; self.entityID = entityID; self.generatedAt = generatedAt; self.records = records; self.diagnostics = diagnostics
    }
}

public struct MemoryOSProjectionRunSummary: Codable, Sendable, Equatable {
    public var artifactID: String
    public var accepted: Bool
    public var nodeCount: Int
    public var statementCount: Int
    public var entityCount: Int
    public var entityStatementCount: Int
    public var beliefCount: Int
    public var issues: [MemoryOSValidationIssue]

    public init(artifactID: String, accepted: Bool, nodeCount: Int = 0, statementCount: Int = 0, entityCount: Int = 0, entityStatementCount: Int = 0, beliefCount: Int = 0, issues: [MemoryOSValidationIssue] = []) {
        self.artifactID = artifactID; self.accepted = accepted; self.nodeCount = nodeCount; self.statementCount = statementCount; self.entityCount = entityCount; self.entityStatementCount = entityStatementCount; self.beliefCount = beliefCount; self.issues = issues
    }
}

public enum MemoryOSStableKeyBuilder {
    public static func stableKey(type: String, name: String, scope: String = "default") -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        let safe = normalized.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return [scope, type, safe.isEmpty ? "unnamed" : safe].joined(separator: ":")
    }
}
