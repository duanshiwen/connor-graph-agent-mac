import Foundation
import ConnorGraphCore

public enum GraphRerankerStrategy: String, Sendable, Codable, Equatable {
    case graphitiLocal = "graphiti_local"
    case maximalMarginalRelevance = "mmr"
    case episodeMentions = "episode_mentions"
    case crossEncoder = "cross_encoder"

    public static let canonicalExecutionOrder: [GraphRerankerStrategy] = [
        .graphitiLocal,
        .episodeMentions,
        .maximalMarginalRelevance,
        .crossEncoder
    ]
}

public struct GraphRerankingConfig: Sendable, Codable, Equatable {
    public var strategies: [GraphRerankerStrategy]
    public var mmrLambda: Double
    public var crossEncoderTopK: Int?
    public var episodeMentionEpisodeIDs: [String]

    public init(
        strategies: [GraphRerankerStrategy] = [.graphitiLocal],
        mmrLambda: Double = 0.5,
        crossEncoderTopK: Int? = nil,
        episodeMentionEpisodeIDs: [String] = []
    ) {
        self.strategies = strategies
        self.mmrLambda = mmrLambda
        self.crossEncoderTopK = crossEncoderTopK
        self.episodeMentionEpisodeIDs = episodeMentionEpisodeIDs
    }
}

public struct GraphCrossEncoderCandidate: Sendable, Equatable {
    public var ownerType: GraphIndexOwnerType
    public var ownerID: String
    public var title: String
    public var text: String
    public var metadata: [String: String]

    public init(ownerType: GraphIndexOwnerType, ownerID: String, title: String, text: String, metadata: [String: String] = [:]) {
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.title = title
        self.text = text
        self.metadata = metadata
    }
}

public struct GraphCrossEncoderScore: Sendable, Equatable {
    public var ownerType: GraphIndexOwnerType
    public var ownerID: String
    public var score: Double

    public init(ownerType: GraphIndexOwnerType, ownerID: String, score: Double) {
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.score = score
    }
}

public protocol GraphCrossEncoderReranker: Sendable {
    func scores(query: String, candidates: [GraphCrossEncoderCandidate]) async throws -> [GraphCrossEncoderScore]
}

public struct GraphSearchQuery: Sendable, Equatable {
    public var text: String
    public var graphID: String
    public var referenceTime: Date?
    public var includeEntities: Bool
    public var includeStatements: Bool
    public var includeEpisodes: Bool
    public var limit: Int
    public var beliefStatusFilter: Set<GraphBeliefStatus>
    public var embeddingModel: String?
    public var queryEmbedding: [Double]?
    public var centerEntityIDs: [String]
    public var reranking: GraphRerankingConfig

    public init(
        text: String,
        graphID: String,
        referenceTime: Date? = nil,
        includeEntities: Bool = true,
        includeStatements: Bool = true,
        includeEpisodes: Bool = true,
        limit: Int = 20,
        beliefStatusFilter: Set<GraphBeliefStatus> = [.active],
        embeddingModel: String? = nil,
        queryEmbedding: [Double]? = nil,
        centerEntityIDs: [String] = [],
        reranking: GraphRerankingConfig = GraphRerankingConfig()
    ) {
        self.text = text
        self.graphID = graphID
        self.referenceTime = referenceTime
        self.includeEntities = includeEntities
        self.includeStatements = includeStatements
        self.includeEpisodes = includeEpisodes
        self.limit = limit
        self.beliefStatusFilter = beliefStatusFilter
        self.embeddingModel = embeddingModel
        self.queryEmbedding = queryEmbedding
        self.centerEntityIDs = centerEntityIDs
        self.reranking = reranking
    }
}

public struct GraphSearchResponse: Sendable, Equatable {
    public var hits: [GraphSearchHit]

    public init(hits: [GraphSearchHit]) {
        self.hits = hits
    }
}

public struct GraphSearchHit: Sendable, Equatable, Identifiable {
    public var id: String { "\(ownerType.rawValue):\(ownerID)" }
    public var ownerType: GraphIndexOwnerType
    public var ownerID: String
    public var title: String
    public var text: String
    public var score: Double
    public var retrievalMethod: String
    public var sourceEpisodeIDs: [String]
    public var metadata: [String: String]

    public init(
        ownerType: GraphIndexOwnerType,
        ownerID: String,
        title: String,
        text: String,
        score: Double,
        retrievalMethod: String,
        sourceEpisodeIDs: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.title = title
        self.text = text
        self.score = score
        self.retrievalMethod = retrievalMethod
        self.sourceEpisodeIDs = sourceEpisodeIDs
        self.metadata = metadata
    }
}

public protocol GraphHybridSearchService: Sendable {
    func search(query: GraphSearchQuery) async throws -> GraphSearchResponse
}
