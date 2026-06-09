import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct GraphStoreSnapshot: Sendable, Equatable {
    public var graphNodes: [GraphNodeV2]
    public var graphFacts: [GraphFact]
    public var graphEpisodes: [GraphEpisode]
    public var observeLogEntries: [ObserveLogEntry]

    public init(
        graphNodes: [GraphNodeV2],
        graphFacts: [GraphFact],
        graphEpisodes: [GraphEpisode] = [],
        observeLogEntries: [ObserveLogEntry]
    ) {
        self.graphNodes = graphNodes
        self.graphFacts = graphFacts
        self.graphEpisodes = graphEpisodes
        self.observeLogEntries = observeLogEntries
    }
}
