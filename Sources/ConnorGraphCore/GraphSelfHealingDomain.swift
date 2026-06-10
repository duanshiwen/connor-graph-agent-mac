import Foundation

public enum GraphAnomalyType: String, Codable, Sendable, CaseIterable, Equatable {
    case directContradiction = "direct_contradiction"
    case inferredContradiction = "inferred_contradiction"
    case commonSenseViolation = "common_sense_violation"
    case temporalConflict = "temporal_conflict"
    case duplicateEntity = "duplicate_entity"
    case scopeConflict = "scope_conflict"
}

public enum GraphAnomalySeverity: String, Codable, Sendable, CaseIterable, Equatable {
    case low
    case medium
    case high
    case critical
}

public enum GraphAnomalyStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case open
    case investigating
    case resolved
    case dismissed
}

public struct GraphAnomaly: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var graphID: String
    public var anomalyType: GraphAnomalyType
    public var statementID: String
    public var relatedStatementIDs: [String]
    public var severity: GraphAnomalySeverity
    public var status: GraphAnomalyStatus
    public var detectedAt: Date
    public var resolvedAt: Date?
    public var resolution: [String: String]
    public var metadata: [String: String]

    public init(
        id: String,
        graphID: String,
        anomalyType: GraphAnomalyType,
        statementID: String,
        relatedStatementIDs: [String] = [],
        severity: GraphAnomalySeverity,
        status: GraphAnomalyStatus = .open,
        detectedAt: Date = Date(),
        resolvedAt: Date? = nil,
        resolution: [String: String] = [:],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.graphID = graphID
        self.anomalyType = anomalyType
        self.statementID = statementID
        self.relatedStatementIDs = relatedStatementIDs
        self.severity = severity
        self.status = status
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
        self.resolution = resolution
        self.metadata = metadata
    }
}

public enum GraphJobV3Type: String, Codable, Sendable, CaseIterable, Equatable {
    case extraction
    case groundingCheck = "grounding_check"
    case confidenceDecay = "confidence_decay"
    case anomalyResolution = "anomaly_resolution"
    case ontologyPromotion = "ontology_promotion"
    case entityMergeReview = "entity_merge_review"
    case indexRefresh = "index_refresh"
}

public enum GraphJobV3Status: String, Codable, Sendable, CaseIterable, Equatable {
    case queued
    case running
    case succeeded
    case failed
    case paused
    case cancelled
    case deadLetter = "dead_letter"
}

public struct GraphJobV3: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var graphID: String
    public var type: GraphJobV3Type
    public var status: GraphJobV3Status
    public var priority: Int
    public var payload: [String: String]
    public var attemptCount: Int
    public var maxAttempts: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var nextRunAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var errorCode: String?
    public var errorMessage: String?
    public var metadata: [String: String]

    public init(
        id: String,
        graphID: String,
        type: GraphJobV3Type,
        status: GraphJobV3Status = .queued,
        priority: Int = 0,
        payload: [String: String] = [:],
        attemptCount: Int = 0,
        maxAttempts: Int = 3,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        nextRunAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.graphID = graphID
        self.type = type
        self.status = status
        self.priority = priority
        self.payload = payload
        self.attemptCount = attemptCount
        self.maxAttempts = maxAttempts
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.nextRunAt = nextRunAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}

public struct GraphInferredStatement: Sendable, Equatable, Identifiable {
    public var id: String { "inferred:\(subjectEntityID):\(predicate.rawValue):\(objectEntityID):\(inferencePath.joined(separator: ">"))" }
    public var subjectEntityID: String
    public var predicate: GraphPredicate
    public var objectEntityID: String
    public var confidence: Double
    public var inferencePath: [String]
    public var generatedAt: Date

    public init(subjectEntityID: String, predicate: GraphPredicate, objectEntityID: String, confidence: Double, inferencePath: [String], generatedAt: Date = Date()) {
        self.subjectEntityID = subjectEntityID
        self.predicate = predicate
        self.objectEntityID = objectEntityID
        self.confidence = confidence
        self.inferencePath = inferencePath
        self.generatedAt = generatedAt
    }
}
