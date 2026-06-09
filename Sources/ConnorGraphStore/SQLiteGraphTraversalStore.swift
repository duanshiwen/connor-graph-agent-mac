import Foundation
import ConnorGraphCore

public struct GraphNeighbor: Sendable, Equatable {
    public var nodeID: String
    public var viaFactID: String
    public var relation: RelationType
    public var depth: Int

    public init(nodeID: String, viaFactID: String, relation: RelationType, depth: Int) {
        self.nodeID = nodeID
        self.viaFactID = viaFactID
        self.relation = relation
        self.depth = depth
    }
}

public protocol GraphTraversalStore: Sendable {
    func neighbors(of nodeID: String, groupID: String, depth: Int, limit: Int) throws -> [GraphNeighbor]
    func shortestHopDistances(from centerNodeIDs: [String], to candidateNodeIDs: [String], groupID: String, maxDepth: Int) throws -> [String: Int]
    func factsAdjacent(to nodeID: String, groupID: String, limit: Int) throws -> [GraphFact]
}

public struct SQLiteGraphTraversalStore: GraphTraversalStore, Sendable {
    public var store: SQLiteGraphStore

    public init(store: SQLiteGraphStore) {
        self.store = store
    }

    public func neighbors(of nodeID: String, groupID: String, depth: Int, limit: Int) throws -> [GraphNeighbor] {
        guard depth > 0, limit > 0 else { return [] }
        var visited: Set<String> = [nodeID]
        var frontier: Set<String> = [nodeID]
        var results: [GraphNeighbor] = []

        for currentDepth in 1...depth {
            var nextFrontier: Set<String> = []
            for currentNodeID in frontier.sorted() {
                let facts = try factsAdjacent(to: currentNodeID, groupID: groupID, limit: max(limit * 4, limit))
                for fact in facts {
                    let neighborID = fact.sourceNodeID == currentNodeID ? fact.targetNodeID : fact.sourceNodeID
                    guard !visited.contains(neighborID) else { continue }
                    visited.insert(neighborID)
                    nextFrontier.insert(neighborID)
                    results.append(GraphNeighbor(nodeID: neighborID, viaFactID: fact.id, relation: fact.relation, depth: currentDepth))
                    if results.count >= limit { return sorted(results) }
                }
            }
            frontier = nextFrontier
            if frontier.isEmpty { break }
        }

        return sorted(results)
    }

    public func shortestHopDistances(from centerNodeIDs: [String], to candidateNodeIDs: [String], groupID: String, maxDepth: Int) throws -> [String: Int] {
        guard maxDepth >= 0, !centerNodeIDs.isEmpty, !candidateNodeIDs.isEmpty else { return [:] }
        let candidates = Set(candidateNodeIDs)
        var distances: [String: Int] = [:]
        var visited = Set(centerNodeIDs)
        var frontier = Set(centerNodeIDs)

        for centerNodeID in centerNodeIDs where candidates.contains(centerNodeID) {
            distances[centerNodeID] = 0
        }
        guard maxDepth > 0 else { return distances }

        for depth in 1...maxDepth {
            var nextFrontier: Set<String> = []
            for nodeID in frontier.sorted() {
                let facts = try factsAdjacent(to: nodeID, groupID: groupID, limit: 1_000)
                for fact in facts {
                    let neighborID = fact.sourceNodeID == nodeID ? fact.targetNodeID : fact.sourceNodeID
                    guard !visited.contains(neighborID) else { continue }
                    visited.insert(neighborID)
                    nextFrontier.insert(neighborID)
                    if candidates.contains(neighborID), distances[neighborID] == nil {
                        distances[neighborID] = depth
                    }
                }
            }
            if distances.count == candidates.count || nextFrontier.isEmpty { break }
            frontier = nextFrontier
        }
        return distances
    }

    public func factsAdjacent(to nodeID: String, groupID: String, limit: Int) throws -> [GraphFact] {
        try store.adjacentFacts(nodeID: nodeID, groupID: groupID, limit: limit)
            .filter { $0.status == .active }
    }

    private func sorted(_ neighbors: [GraphNeighbor]) -> [GraphNeighbor] {
        neighbors.sorted { lhs, rhs in
            if lhs.depth == rhs.depth {
                if lhs.nodeID == rhs.nodeID { return lhs.viaFactID < rhs.viaFactID }
                return lhs.nodeID < rhs.nodeID
            }
            return lhs.depth < rhs.depth
        }
    }
}
