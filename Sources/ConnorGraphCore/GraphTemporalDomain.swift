import Foundation

public enum GraphEpisodeSourceType: String, Codable, Sendable, CaseIterable, Equatable {
    case chatMessage = "chat_message"
    case observeLog = "observe_log"
    case file
    case manual
    case system
}

public enum GraphTemporalStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active
    case draft
    case archived
    case superseded
    case dismissed
    case invalidated
}

public struct GraphEpisode: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var groupID: String
    public var sourceType: GraphEpisodeSourceType
    public var sourceID: String?
    public var name: String
    public var content: String
    public var sourceDescription: String
    public var occurredAt: Date
    public var ingestedAt: Date
    public var sessionID: String?
    public var workObjectID: String?
    public var status: GraphTemporalStatus
    public var metadata: [String: String]

    public init(
        id: String,
        groupID: String,
        sourceType: GraphEpisodeSourceType,
        sourceID: String? = nil,
        name: String,
        content: String,
        sourceDescription: String,
        occurredAt: Date = Date(),
        ingestedAt: Date = Date(),
        sessionID: String? = nil,
        workObjectID: String? = nil,
        status: GraphTemporalStatus = .active,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.groupID = groupID
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.name = name
        self.content = content
        self.sourceDescription = sourceDescription
        self.occurredAt = occurredAt
        self.ingestedAt = ingestedAt
        self.sessionID = sessionID
        self.workObjectID = workObjectID
        self.status = status
        self.metadata = metadata
    }
}

public struct GraphNodeV2: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var groupID: String
    public var stableKey: String?
    public var type: NodeType
    public var canonicalName: String
    public var title: String
    public var summary: String
    public var labels: [String]
    public var attributes: [String: String]
    public var status: GraphTemporalStatus
    public var confidence: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var validFrom: Date?
    public var validUntil: Date?
    public var supersededByNodeID: String?
    public var metadata: [String: String]

    public init(
        id: String,
        groupID: String,
        stableKey: String? = nil,
        type: NodeType,
        canonicalName: String,
        title: String,
        summary: String = "",
        labels: [String] = [],
        attributes: [String: String] = [:],
        status: GraphTemporalStatus = .active,
        confidence: Double = 1.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        supersededByNodeID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.groupID = groupID
        self.stableKey = stableKey
        self.type = type
        self.canonicalName = canonicalName
        self.title = title
        self.summary = summary
        self.labels = labels
        self.attributes = attributes
        self.status = status
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.supersededByNodeID = supersededByNodeID
        self.metadata = metadata
    }
}

public struct GraphFact: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var groupID: String
    public var sourceNodeID: String
    public var targetNodeID: String
    public var relation: RelationType
    public var fact: String
    public var confidence: Double
    public var status: GraphTemporalStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var validAt: Date?
    public var invalidAt: Date?
    public var expiredAt: Date?
    public var referenceTime: Date?
    public var invalidatedByFactID: String?
    public var attributes: [String: String]
    public var metadata: [String: String]

    public init(
        id: String,
        groupID: String,
        sourceNodeID: String,
        targetNodeID: String,
        relation: RelationType,
        fact: String,
        confidence: Double = 1.0,
        status: GraphTemporalStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        validAt: Date? = nil,
        invalidAt: Date? = nil,
        expiredAt: Date? = nil,
        referenceTime: Date? = nil,
        invalidatedByFactID: String? = nil,
        attributes: [String: String] = [:],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.groupID = groupID
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.relation = relation
        self.fact = fact
        self.confidence = confidence
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.validAt = validAt
        self.invalidAt = invalidAt
        self.expiredAt = expiredAt
        self.referenceTime = referenceTime
        self.invalidatedByFactID = invalidatedByFactID
        self.attributes = attributes
        self.metadata = metadata
    }
}

public enum GraphIndexOwnerType: String, Codable, Sendable, CaseIterable, Equatable {
    case node
    case fact
    case episode
}

public enum GraphIndexTaskType: String, Codable, Sendable, CaseIterable, Equatable {
    case ftsUpsert = "fts_upsert"
    case embeddingUpsert = "embedding_upsert"
    case delete
    case rebuild
}

public struct GraphEmbedding: Sendable, Equatable, Identifiable {
    public var id: String
    public var groupID: String
    public var ownerType: GraphIndexOwnerType
    public var ownerID: String
    public var embeddingModel: String
    public var vector: [Double]
    public var vectorNorm: Double
    public var contentHash: String
    public var createdAt: Date

    public init(
        id: String,
        groupID: String,
        ownerType: GraphIndexOwnerType,
        ownerID: String,
        embeddingModel: String,
        vector: [Double],
        contentHash: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.groupID = groupID
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.embeddingModel = embeddingModel
        self.vector = vector
        self.vectorNorm = Self.norm(vector)
        self.contentHash = contentHash
        self.createdAt = createdAt
    }

    public static func norm(_ vector: [Double]) -> Double {
        sqrt(vector.reduce(0.0) { $0 + ($1 * $1) })
    }
}

public struct GraphEmbeddingSearchResult: Sendable, Equatable {
    public var embedding: GraphEmbedding
    public var score: Double

    public init(embedding: GraphEmbedding, score: Double) {
        self.embedding = embedding
        self.score = score
    }
}

public enum GraphJobStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case queued
    case running
    case succeeded
    case failed
    case paused
    case cancelled
    case deadLetter = "dead_letter"
}

public enum GraphCostBudgetScopeType: String, Codable, Sendable, CaseIterable, Equatable {
    case global
    case group
    case jobType = "job_type"
    case session
}

public enum GraphCostBudgetPeriod: String, Codable, Sendable, CaseIterable, Equatable {
    case daily
    case monthly
    case run
}

public enum GraphCostBudgetDecision: Sendable, Equatable {
    case allowed
    case blocked(reason: String)
}

public struct GraphCostBudget: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var scopeType: GraphCostBudgetScopeType
    public var scopeID: String
    public var period: GraphCostBudgetPeriod
    public var tokenLimit: Int?
    public var costLimitMicrounits: Int?
    public var usedPromptTokens: Int
    public var usedCompletionTokens: Int
    public var usedCostMicrounits: Int
    public var resetAt: Date?
    public var metadata: [String: String]

    public init(
        id: String,
        scopeType: GraphCostBudgetScopeType,
        scopeID: String,
        period: GraphCostBudgetPeriod,
        tokenLimit: Int? = nil,
        costLimitMicrounits: Int? = nil,
        usedPromptTokens: Int = 0,
        usedCompletionTokens: Int = 0,
        usedCostMicrounits: Int = 0,
        resetAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.scopeType = scopeType
        self.scopeID = scopeID
        self.period = period
        self.tokenLimit = tokenLimit
        self.costLimitMicrounits = costLimitMicrounits
        self.usedPromptTokens = usedPromptTokens
        self.usedCompletionTokens = usedCompletionTokens
        self.usedCostMicrounits = usedCostMicrounits
        self.resetAt = resetAt
        self.metadata = metadata
    }
}

public enum GraphJobType: String, Codable, Sendable, CaseIterable, Equatable {
    case generateGraphFromEpisode = "generate_graph_from_episode"
    case indexGraphOwner = "index_graph_owner"
    case rebuildGraphIndex = "rebuild_graph_index"
    case refreshEmbedding = "refresh_embedding"
}

public struct GraphJob: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var groupID: String
    public var type: GraphJobType
    public var status: GraphJobStatus
    public var priority: Int
    public var payload: [String: String]
    public var attemptCount: Int
    public var maxAttempts: Int
    public var nextRunAt: Date
    public var leaseOwner: String?
    public var leaseExpiresAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var errorCode: String?
    public var errorMessage: String?
    public var metadata: [String: String]

    public init(
        id: String,
        groupID: String,
        type: GraphJobType,
        status: GraphJobStatus = .queued,
        priority: Int = 0,
        payload: [String: String] = [:],
        attemptCount: Int = 0,
        maxAttempts: Int = 3,
        nextRunAt: Date = .distantPast,
        leaseOwner: String? = nil,
        leaseExpiresAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.groupID = groupID
        self.type = type
        self.status = status
        self.priority = priority
        self.payload = payload
        self.attemptCount = attemptCount
        self.maxAttempts = maxAttempts
        self.nextRunAt = nextRunAt
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}

public struct GraphIndexTask: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var groupID: String
    public var ownerType: GraphIndexOwnerType
    public var ownerID: String
    public var taskType: GraphIndexTaskType
    public var status: GraphJobStatus
    public var attemptCount: Int
    public var nextRunAt: Date
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        groupID: String,
        ownerType: GraphIndexOwnerType,
        ownerID: String,
        taskType: GraphIndexTaskType = .ftsUpsert,
        status: GraphJobStatus = .queued,
        attemptCount: Int = 0,
        nextRunAt: Date = Date(),
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.groupID = groupID
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.taskType = taskType
        self.status = status
        self.attemptCount = attemptCount
        self.nextRunAt = nextRunAt
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
