import Foundation

public struct GraphOptimisticWriteBatch: Sendable, Equatable {
    public var graphID: String
    public var episode: GraphEpisodeV3?
    public var entities: [GraphEntity]
    public var statements: [GraphStatement]
    public var now: Date

    public init(graphID: String, episode: GraphEpisodeV3? = nil, entities: [GraphEntity] = [], statements: [GraphStatement] = [], now: Date = Date()) {
        self.graphID = graphID
        self.episode = episode
        self.entities = entities
        self.statements = statements
        self.now = now
    }
}
