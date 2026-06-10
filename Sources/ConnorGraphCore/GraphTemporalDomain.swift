import Foundation

public enum GraphIndexOwnerType: String, Codable, Sendable, CaseIterable, Equatable {
    case entity
    case statement
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
    public var graphID: String
    public var ownerType: GraphIndexOwnerType
    public var ownerID: String
    public var embeddingModel: String
    public var vector: [Double]
    public var vectorNorm: Double
    public var contentHash: String
    public var createdAt: Date

    public init(
        id: String,
        graphID: String,
        ownerType: GraphIndexOwnerType,
        ownerID: String,
        embeddingModel: String,
        vector: [Double],
        contentHash: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.graphID = graphID
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
    public var graphID: String
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
        graphID: String,
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
        self.graphID = graphID
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
    public var graphID: String
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
        graphID: String,
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
        self.graphID = graphID
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
