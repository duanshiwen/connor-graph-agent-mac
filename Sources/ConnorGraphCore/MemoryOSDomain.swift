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

public enum MemoryOSAcceptanceMode: String, Codable, Sendable, Equatable, CaseIterable {
    case strictAccepted = "strict_accepted"
    case normalizedAccepted = "normalized_accepted"
    case repairedAccepted = "repaired_accepted"
    case degradedAccepted = "degraded_accepted"
    case rejected

    public var isAccepted: Bool {
        self != .rejected
    }
}

public enum MemoryOSIssueSeverity: String, Codable, Sendable, Equatable, CaseIterable {
    case fatal
    case warning
    case informational
}

public enum MemoryOSIssueDisposition: String, Codable, Sendable, Equatable, CaseIterable {
    case rejectArtifact = "reject_artifact"
    case normalizeAndKeep = "normalize_and_keep"
    case repairAndKeep = "repair_and_keep"
    case dropRecord = "drop_record"
    case keepWithWarning = "keep_with_warning"
}

public struct MemoryOSValidationIssue: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var code: String
    public var message: String
    public var severity: String
    public var scope: String?
    public var disposition: String?
    public var recordReference: String?
    public var repairHint: String?

    public var severityKind: MemoryOSIssueSeverity {
        MemoryOSIssueSeverity(rawValue: severity) ?? .warning
    }

    public var dispositionKind: MemoryOSIssueDisposition? {
        disposition.flatMap(MemoryOSIssueDisposition.init(rawValue:))
    }

    public init(id: String = UUID().uuidString, code: String, message: String, severity: String = MemoryOSIssueSeverity.warning.rawValue, scope: String? = nil, disposition: String? = nil, recordReference: String? = nil, repairHint: String? = nil) {
        self.id = id
        self.code = code
        self.message = message
        self.severity = severity
        self.scope = scope
        self.disposition = disposition
        self.recordReference = recordReference
        self.repairHint = repairHint
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
    public var acceptanceMode: String
    public var issues: [MemoryOSValidationIssue]
    public var normalizedRecordCount: Int
    public var acceptedRecordCount: Int
    public var repairedRecordCount: Int
    public var degradedRecordCount: Int
    public var droppedRecordCount: Int

    public var acceptanceModeKind: MemoryOSAcceptanceMode {
        MemoryOSAcceptanceMode(rawValue: acceptanceMode) ?? (accepted ? .strictAccepted : .rejected)
    }

    public init(artifactID: String, accepted: Bool, acceptanceMode: String? = nil, issues: [MemoryOSValidationIssue] = [], normalizedRecordCount: Int = 0, acceptedRecordCount: Int? = nil, repairedRecordCount: Int = 0, degradedRecordCount: Int = 0, droppedRecordCount: Int = 0) {
        let resolvedMode = acceptanceMode ?? (accepted ? MemoryOSAcceptanceMode.strictAccepted.rawValue : MemoryOSAcceptanceMode.rejected.rawValue)
        let resolvedAcceptedRecordCount = acceptedRecordCount ?? normalizedRecordCount
        self.artifactID = artifactID
        self.accepted = accepted
        self.acceptanceMode = resolvedMode
        self.issues = issues
        self.normalizedRecordCount = normalizedRecordCount
        self.acceptedRecordCount = resolvedAcceptedRecordCount
        self.repairedRecordCount = repairedRecordCount
        self.degradedRecordCount = degradedRecordCount
        self.droppedRecordCount = droppedRecordCount
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
    public var schemaName: String
    public var artifactType: String
    public var metadata: [String: String]

    public init(rawContent: String, modelID: String, processingRunID: String? = nil, schemaName: String = "GraphStructuredExtractionOutput", artifactType: String = "graph_structured_extraction", metadata: [String: String] = [:]) {
        self.rawContent = rawContent
        self.modelID = modelID
        self.processingRunID = processingRunID
        self.schemaName = schemaName
        self.artifactType = artifactType
        self.metadata = metadata
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

public enum MemoryOSQueueEnqueueResult: Sendable, Equatable {
    case inserted(MemoryOSQueueItem)
    case existing(MemoryOSQueueItem)
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

public enum MemoryOSKnowledgeSignalDimension: String, Codable, Sendable, Equatable, CaseIterable {
    case signalQuality = "signal_quality"
    case reuseScope = "reuse_scope"
    case novelty
    case structurability
}

public struct MemoryOSKnowledgeSignalAssessment: Codable, Sendable, Equatable {
    public var signalQualityAccepted: Bool
    public var reuseScopeAccepted: Bool
    public var noveltyAccepted: Bool
    public var structurabilityAccepted: Bool
    public var reasons: [String]

    public init(signalQualityAccepted: Bool = false, reuseScopeAccepted: Bool = false, noveltyAccepted: Bool = false, structurabilityAccepted: Bool = false, reasons: [String] = []) {
        self.signalQualityAccepted = signalQualityAccepted
        self.reuseScopeAccepted = reuseScopeAccepted
        self.noveltyAccepted = noveltyAccepted
        self.structurabilityAccepted = structurabilityAccepted
        self.reasons = reasons
    }
}

public struct MemoryOSKnowledgeCandidate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var claim: String
    public var category: String?
    public var knowledgeType: String?
    public var scope: String?
    public var domain: String?
    public var workObjectID: String?
    public var signalAssessment: MemoryOSKnowledgeSignalAssessment
    public var confidence: Double
    public var evidenceStatementIDs: [String]
    public var evidenceSpanIDs: [String]
    public var relatedEntityNames: [String]
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, title: String, claim: String, category: String? = nil, knowledgeType: String? = nil, scope: String? = nil, domain: String? = nil, workObjectID: String? = nil, signalAssessment: MemoryOSKnowledgeSignalAssessment = MemoryOSKnowledgeSignalAssessment(), confidence: Double = 0.5, evidenceStatementIDs: [String] = [], evidenceSpanIDs: [String] = [], relatedEntityNames: [String] = [], metadata: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.claim = claim
        self.category = category
        self.knowledgeType = knowledgeType
        self.scope = scope
        self.domain = domain
        self.workObjectID = workObjectID
        self.signalAssessment = signalAssessment
        self.confidence = confidence
        self.evidenceStatementIDs = evidenceStatementIDs
        self.evidenceSpanIDs = evidenceSpanIDs
        self.relatedEntityNames = relatedEntityNames
        self.metadata = metadata
    }
}

public struct MemoryOSKnowledgePromotionDecision: Codable, Sendable, Equatable {
    public var candidateID: String
    public var accepted: Bool
    public var rejectedDimensions: [MemoryOSKnowledgeSignalDimension]
    public var reasons: [String]

    public init(candidateID: String, accepted: Bool, rejectedDimensions: [MemoryOSKnowledgeSignalDimension] = [], reasons: [String] = []) {
        self.candidateID = candidateID
        self.accepted = accepted
        self.rejectedDimensions = rejectedDimensions
        self.reasons = reasons
    }
}

public struct MemoryOSKnowledgeEvidenceSpan: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var startOffset: Int?
    public var endOffset: Int?

    public init(id: String, text: String, startOffset: Int? = nil, endOffset: Int? = nil) {
        self.id = id
        self.text = text
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public enum MemoryOSEntityType: String, Codable, Sendable, Equatable, CaseIterable {
    case person
    case organization
    case group
    case role
    case population
    case place
    case facility
    case spatialObject = "spatial_object"
    case concept
    case theory
    case framework
    case discipline
    case standard
    case language
    case metric
    case identifierScheme = "identifier_scheme"
    case creativeWork = "creative_work"
    case document
    case dataset
    case software
    case product
    case mediaObject = "media_object"
    case website
    case project
    case event
    case process
    case decision
    case task
    case rule
    case agreement
    case physicalObject = "physical_object"
    case device
    case vehicle
    case biologicalEntity = "biological_entity"
    case medicalEntity = "medical_entity"
    case chemicalEntity = "chemical_entity"
    case economicEntity = "economic_entity"
    case award
    case unknown

    public static func normalizeRawType(_ raw: String) -> String {
        fromRawType(raw).rawValue
    }

    public static func fromRawType(_ raw: String) -> MemoryOSEntityType {
        let normalized = normalizeToken(raw)
        if let exact = MemoryOSEntityType(rawValue: normalized) {
            return exact
        }
        return aliases[normalized] ?? .unknown
    }

    private static func normalizeToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static let aliases: [String: MemoryOSEntityType] = [
        "human": .person,
        "scientist": .person,
        "author": .person,
        "researcher": .person,
        "individual": .person,
        "org": .organization,
        "company": .organization,
        "institution": .organization,
        "university": .organization,
        "school": .organization,
        "college": .organization,
        "agency": .organization,
        "team": .group,
        "community": .group,
        "audience": .population,
        "segment": .population,
        "location": .place,
        "geo": .place,
        "gpe": .place,
        "city": .place,
        "country": .place,
        "building": .facility,
        "campus": .facility,
        "space": .spatialObject,
        "region": .spatialObject,
        "area": .spatialObject,
        "class": .concept,
        "type": .concept,
        "category": .concept,
        "taxonomy_class": .concept,
        "ontology_class": .concept,
        "kind": .concept,
        "concept_type": .concept,
        "entity_type": .concept,
        "principle": .concept,
        "pattern": .concept,
        "method": .framework,
        "methodology": .framework,
        "model": .framework,
        "domain": .discipline,
        "field": .discipline,
        "policy": .rule,
        "constraint": .rule,
        "requirement": .rule,
        "law": .rule,
        "regulation": .rule,
        "sop": .standard,
        "runbook": .standard,
        "knowledge_type": .standard,
        "parameter": .metric,
        "variable": .metric,
        "indicator": .metric,
        "measure": .metric,
        "index": .metric,
        "id_scheme": .identifierScheme,
        "identifier": .identifierScheme,
        "identifier_type": .identifierScheme,
        "work": .creativeWork,
        "book": .creativeWork,
        "article": .document,
        "paper": .document,
        "report": .document,
        "file": .document,
        "data": .dataset,
        "database": .dataset,
        "app": .software,
        "application": .software,
        "tool": .software,
        "service": .software,
        "media": .mediaObject,
        "image": .mediaObject,
        "video": .mediaObject,
        "site": .website,
        "workflow": .process,
        "procedure": .process,
        "operation": .process,
        "choice": .decision,
        "job": .task,
        "contract": .agreement,
        "treaty": .agreement,
        "object": .physicalObject,
        "artifact": .physicalObject,
        "machine": .device,
        "organism": .biologicalEntity,
        "species": .biologicalEntity,
        "disease": .medicalEntity,
        "condition": .medicalEntity,
        "drug": .chemicalEntity,
        "compound": .chemicalEntity,
        "market": .economicEntity,
        "currency": .economicEntity,
        "prize": .award
    ]
}

public struct MemoryOSExtractedConceptEntity: Codable, Sendable, Equatable {
    public var name: String
    public var conceptType: String
    public var domain: String?
    public var summary: String
    public var aliases: [String]
    public var metadata: [String: String]

    public init(name: String, conceptType: String = "concept", domain: String? = nil, summary: String = "", aliases: [String] = [], metadata: [String: String] = [:]) {
        self.name = name
        self.conceptType = conceptType
        self.domain = domain
        self.summary = summary
        self.aliases = aliases
        self.metadata = metadata
    }
}

public struct MemoryOSExtractedConceptRelation: Codable, Sendable, Equatable {
    public var subjectName: String
    public var predicate: MemoryOSL4RelationPredicate
    public var objectName: String
    public var text: String
    public var metadata: [String: String]

    public init(subjectName: String, predicate: MemoryOSL4RelationPredicate, objectName: String, text: String, metadata: [String: String] = [:]) {
        self.subjectName = subjectName
        self.predicate = predicate
        self.objectName = objectName
        self.text = text
        self.metadata = metadata
    }
}

public struct MemoryOSKnowledgeExtractionOutput: Codable, Sendable, Equatable {
    public var knowledgeCandidates: [MemoryOSKnowledgeCandidate]
    public var conceptEntities: [MemoryOSExtractedConceptEntity]
    public var conceptRelations: [MemoryOSExtractedConceptRelation]
    public var evidenceSpans: [MemoryOSKnowledgeEvidenceSpan]
    public var warnings: [String]
    public var metadata: [String: String]

    public init(knowledgeCandidates: [MemoryOSKnowledgeCandidate] = [], conceptEntities: [MemoryOSExtractedConceptEntity] = [], conceptRelations: [MemoryOSExtractedConceptRelation] = [], evidenceSpans: [MemoryOSKnowledgeEvidenceSpan] = [], warnings: [String] = [], metadata: [String: String] = [:]) {
        self.knowledgeCandidates = knowledgeCandidates
        self.conceptEntities = conceptEntities
        self.conceptRelations = conceptRelations
        self.evidenceSpans = evidenceSpans
        self.warnings = warnings
        self.metadata = metadata
    }
}

public struct MemoryOSL1PromotionDecision: Codable, Sendable, Equatable, Identifiable {
    public var id: String { candidateID }
    public var candidateID: String
    public var accepted: Bool
    public var signalQualityAccepted: Bool
    public var reuseScopeAccepted: Bool
    public var noveltyAccepted: Bool
    public var structurabilityAccepted: Bool
    public var reasons: [String]
    public var evidenceStatementIDs: [String]
    public var evidenceSpanIDs: [String]
    public var metadata: [String: String]

    public init(candidateID: String, accepted: Bool, signalQualityAccepted: Bool = false, reuseScopeAccepted: Bool = false, noveltyAccepted: Bool = false, structurabilityAccepted: Bool = false, reasons: [String] = [], evidenceStatementIDs: [String] = [], evidenceSpanIDs: [String] = [], metadata: [String: String] = [:]) {
        self.candidateID = candidateID
        self.accepted = accepted
        self.signalQualityAccepted = signalQualityAccepted
        self.reuseScopeAccepted = reuseScopeAccepted
        self.noveltyAccepted = noveltyAccepted
        self.structurabilityAccepted = structurabilityAccepted
        self.reasons = reasons
        self.evidenceStatementIDs = evidenceStatementIDs
        self.evidenceSpanIDs = evidenceSpanIDs
        self.metadata = metadata
    }
}

public struct MemoryOSL1UnifiedProjectionOutput: Codable, Sendable, Equatable {
    public var operationalEntities: [GraphStructuredExtractedEntity]
    public var operationalStatements: [GraphStructuredExtractedStatement]
    public var evidenceSpans: [GraphStructuredEvidenceSpan]
    public var knowledgeCandidates: [MemoryOSKnowledgeCandidate]
    public var conceptEntities: [MemoryOSExtractedConceptEntity]
    public var conceptRelations: [MemoryOSExtractedConceptRelation]
    public var promotionDecisions: [MemoryOSL1PromotionDecision]
    public var warnings: [GraphStructuredExtractionWarning]
    public var metadata: [String: String]
    public init(operationalEntities: [GraphStructuredExtractedEntity] = [], operationalStatements: [GraphStructuredExtractedStatement] = [], evidenceSpans: [GraphStructuredEvidenceSpan] = [], knowledgeCandidates: [MemoryOSKnowledgeCandidate] = [], conceptEntities: [MemoryOSExtractedConceptEntity] = [], conceptRelations: [MemoryOSExtractedConceptRelation] = [], promotionDecisions: [MemoryOSL1PromotionDecision] = [], warnings: [GraphStructuredExtractionWarning] = [], metadata: [String: String] = [:]) {
        self.operationalEntities = operationalEntities
        self.operationalStatements = operationalStatements
        self.evidenceSpans = evidenceSpans
        self.knowledgeCandidates = knowledgeCandidates
        self.conceptEntities = conceptEntities
        self.conceptRelations = conceptRelations
        self.promotionDecisions = promotionDecisions
        self.warnings = warnings
        self.metadata = metadata
    }
}

public struct MemoryOSBelief: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var statement: String
    public var domain: String
    public var relatedObjectNames: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, statement: String, domain: String, relatedObjectNames: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.statement = statement
        self.domain = Self.normalizedDisciplineDomain(domain)
        self.relatedObjectNames = Self.normalizedRelatedConceptNames(relatedObjectNames)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func normalizedDisciplineDomain(_ value: String?) -> String {
        let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "general-knowledge" }
        let slug = raw
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let aliases = [
            "cs": "computer-science",
            "ai": "artificial-intelligence",
            "ml": "artificial-intelligence",
            "software": "software-engineering",
            "knowledge-base": "knowledge-management",
            "memory-os": "knowledge-management",
            "agent-os": "software-engineering"
        ]
        return aliases[slug] ?? slug
    }

    public static func normalizedRelatedConceptNames(_ raw: String) -> String {
        var seen: Set<String> = []
        var values: [String] = []
        for part in raw.split(whereSeparator: { char in
            char == "," || char == "，" || char == "、" || char == ";" || char == "\n"
        }) {
            let value = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            values.append(value)
        }
        return values.joined(separator: ", ")
    }
}

public struct MemoryOSL3DomainSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { domain }
    public var domain: String
    public var beliefCount: Int
    public var latestUpdatedAt: Date?

    public init(domain: String, beliefCount: Int, latestUpdatedAt: Date? = nil) {
        self.domain = MemoryOSBelief.normalizedDisciplineDomain(domain)
        self.beliefCount = beliefCount
        self.latestUpdatedAt = latestUpdatedAt
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
    public var predicate: MemoryOSL4RelationPredicate
    public var objectEntityID: String?
    public var text: String
    public var assertionKind: MemoryOSAssertionKind
    public var confidence: Double
    public var validAt: Date
    public var committedAt: Date
    public var evidenceSpanIDs: [String]
    public var sourceArtifactID: String?
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, entityID: String, predicate: MemoryOSL4RelationPredicate, objectEntityID: String? = nil, text: String, assertionKind: MemoryOSAssertionKind = .observed, confidence: Double = 0.5, validAt: Date = Date(), committedAt: Date = Date(), evidenceSpanIDs: [String] = [], sourceArtifactID: String? = nil, metadata: [String: String] = [:]) {
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
    public var acceptanceMode: String
    public var batch: MemoryOSProjectionBatch?
    public var validation: MemoryOSArtifactValidationResult

    public var acceptanceModeKind: MemoryOSAcceptanceMode {
        MemoryOSAcceptanceMode(rawValue: acceptanceMode) ?? validation.acceptanceModeKind
    }

    public init(accepted: Bool, acceptanceMode: String? = nil, batch: MemoryOSProjectionBatch? = nil, validation: MemoryOSArtifactValidationResult) {
        self.accepted = accepted
        self.acceptanceMode = acceptanceMode ?? validation.acceptanceMode
        self.batch = batch
        self.validation = validation
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
    public var acceptanceMode: String
    public var nodeCount: Int
    public var statementCount: Int
    public var entityCount: Int
    public var entityStatementCount: Int
    public var beliefCount: Int
    public var repairedRecordCount: Int
    public var degradedRecordCount: Int
    public var droppedRecordCount: Int
    public var issues: [MemoryOSValidationIssue]

    public var acceptanceModeKind: MemoryOSAcceptanceMode {
        MemoryOSAcceptanceMode(rawValue: acceptanceMode) ?? (accepted ? .strictAccepted : .rejected)
    }

    public init(artifactID: String, accepted: Bool, acceptanceMode: String? = nil, nodeCount: Int = 0, statementCount: Int = 0, entityCount: Int = 0, entityStatementCount: Int = 0, beliefCount: Int = 0, repairedRecordCount: Int = 0, degradedRecordCount: Int = 0, droppedRecordCount: Int = 0, issues: [MemoryOSValidationIssue] = []) {
        self.artifactID = artifactID
        self.accepted = accepted
        self.acceptanceMode = acceptanceMode ?? (accepted ? MemoryOSAcceptanceMode.strictAccepted.rawValue : MemoryOSAcceptanceMode.rejected.rawValue)
        self.nodeCount = nodeCount
        self.statementCount = statementCount
        self.entityCount = entityCount
        self.entityStatementCount = entityStatementCount
        self.beliefCount = beliefCount
        self.repairedRecordCount = repairedRecordCount
        self.degradedRecordCount = degradedRecordCount
        self.droppedRecordCount = droppedRecordCount
        self.issues = issues
    }

    public init(artifactID: String, accepted: Bool, nodeCount: Int, statementCount: Int, entityCount: Int, entityStatementCount: Int, beliefCount: Int, issues: [MemoryOSValidationIssue]) {
        self.init(
            artifactID: artifactID,
            accepted: accepted,
            acceptanceMode: accepted ? MemoryOSAcceptanceMode.strictAccepted.rawValue : MemoryOSAcceptanceMode.rejected.rawValue,
            nodeCount: nodeCount,
            statementCount: statementCount,
            entityCount: entityCount,
            entityStatementCount: entityStatementCount,
            beliefCount: beliefCount,
            repairedRecordCount: 0,
            degradedRecordCount: 0,
            droppedRecordCount: 0,
            issues: issues
        )
    }
}

public enum MemoryOSStableKeyBuilder {
    public static func stableKey(type: String, name: String, scope: String = "default") -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        let safe = normalized.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return [scope, type, safe.isEmpty ? "unnamed" : safe].joined(separator: ":")
    }
}
