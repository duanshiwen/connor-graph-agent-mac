import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct GraphStoreSnapshot: Sendable, Equatable {
    public var nodes: [GraphNode]
    public var edges: [SemanticEdge]
    public var observeLogEntries: [ObserveLogEntry]

    public init(nodes: [GraphNode], edges: [SemanticEdge], observeLogEntries: [ObserveLogEntry]) {
        self.nodes = nodes
        self.edges = edges
        self.observeLogEntries = observeLogEntries
    }
}
