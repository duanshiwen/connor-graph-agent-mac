import Foundation
import ConnorGraphCore

public struct GraphSearchQuery: Sendable, Equatable {
    public var text: String
    public var groupID: String
    public var referenceTime: Date?
    public var includeNodes: Bool
    public var includeFacts: Bool
    public var includeEpisodes: Bool
    public var limit: Int
    public var statusFilter: Set<GraphTemporalStatus>
    public var embeddingModel: String?
    public var queryEmbedding: [Double]?
    public var centerNodeIDs: [String]

    public init(
        text: String,
        groupID: String,
        referenceTime: Date? = nil,
        includeNodes: Bool = true,
        includeFacts: Bool = true,
        includeEpisodes: Bool = true,
        limit: Int = 20,
        statusFilter: Set<GraphTemporalStatus> = [.active],
        embeddingModel: String? = nil,
        queryEmbedding: [Double]? = nil,
        centerNodeIDs: [String] = []
    ) {
        self.text = text
        self.groupID = groupID
        self.referenceTime = referenceTime
        self.includeNodes = includeNodes
        self.includeFacts = includeFacts
        self.includeEpisodes = includeEpisodes
        self.limit = limit
        self.statusFilter = statusFilter
        self.embeddingModel = embeddingModel
        self.queryEmbedding = queryEmbedding
        self.centerNodeIDs = centerNodeIDs
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
