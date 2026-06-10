import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct GraphStoreSnapshot: Sendable, Equatable {
    public var entities: [GraphEntity]
    public var statements: [GraphStatement]
    public var episodes: [GraphEpisodeV3]
    public var observeLogEntries: [ObserveLogEntry]

    public init(
        entities: [GraphEntity],
        statements: [GraphStatement],
        episodes: [GraphEpisodeV3] = [],
        observeLogEntries: [ObserveLogEntry]
    ) {
        self.entities = entities
        self.statements = statements
        self.episodes = episodes
        self.observeLogEntries = observeLogEntries
    }
}
