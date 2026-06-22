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

public enum MemoryOSStatementStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case candidate
    case observed
    case confirmed
    case rejected
    case invalidated
    case superseded
}

public enum MemoryOSBeliefStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case proposed
    case observed
    case userConfirmed = "user_confirmed"
    case deprecated
    case conflicted
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
    public var status: MemoryOSRecordStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, stableKey: String, nodeType: String, name: String, summary: String = "", status: MemoryOSRecordStatus = .active, createdAt: Date = Date(), updatedAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id; self.stableKey = stableKey; self.nodeType = nodeType; self.name = name; self.summary = summary; self.status = status; self.createdAt = createdAt; self.updatedAt = updatedAt; self.metadata = metadata
    }
}

public struct MemoryOSStatement: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var subjectID: String
    public var predicate: String
    public var objectID: String?
    public var text: String
    public var status: MemoryOSStatementStatus
    public var confidence: Double
    public var validAt: Date
    public var invalidAt: Date?
    public var committedAt: Date
    public var evidenceSpanIDs: [String]
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, subjectID: String, predicate: String, objectID: String? = nil, text: String, status: MemoryOSStatementStatus = .observed, confidence: Double = 0.5, validAt: Date = Date(), invalidAt: Date? = nil, committedAt: Date = Date(), evidenceSpanIDs: [String] = [], metadata: [String: String] = [:]) {
        self.id = id; self.subjectID = subjectID; self.predicate = predicate; self.objectID = objectID; self.text = text; self.status = status; self.confidence = confidence; self.validAt = validAt; self.invalidAt = invalidAt; self.committedAt = committedAt; self.evidenceSpanIDs = evidenceSpanIDs; self.metadata = metadata
    }
}

public struct MemoryOSBelief: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var topic: String
    public var statement: String
    public var status: MemoryOSBeliefStatus
    public var confidence: Double
    public var evidenceStatementIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, topic: String, statement: String, status: MemoryOSBeliefStatus = .proposed, confidence: Double = 0.5, evidenceStatementIDs: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date(), metadata: [String: String] = [:]) {
        self.id = id; self.topic = topic; self.statement = statement; self.status = status; self.confidence = confidence; self.evidenceStatementIDs = evidenceStatementIDs; self.createdAt = createdAt; self.updatedAt = updatedAt; self.metadata = metadata
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
    public var status: MemoryOSRecordStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var validFrom: Date?
    public var validUntil: Date?
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, stableKey: String, entityType: String, name: String, aliases: [String] = [], summary: String = "", confidence: Double = 0.5, status: MemoryOSRecordStatus = .active, createdAt: Date = Date(), updatedAt: Date = Date(), validFrom: Date? = nil, validUntil: Date? = nil, metadata: [String: String] = [:]) {
        self.id = id; self.stableKey = stableKey; self.entityType = entityType; self.name = name; self.aliases = aliases; self.summary = summary; self.confidence = confidence; self.status = status; self.createdAt = createdAt; self.updatedAt = updatedAt; self.validFrom = validFrom; self.validUntil = validUntil; self.metadata = metadata
    }
}

public enum MemoryOSStableKeyBuilder {
    public static func stableKey(type: String, name: String, scope: String = "default") -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        let safe = normalized.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return [scope, type, safe.isEmpty ? "unnamed" : safe].joined(separator: ":")
    }
}
