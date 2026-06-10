import Foundation
import ConnorGraphCore

public struct GraphNeighbor: Sendable, Equatable {
    public var entityID: String
    public var viaStatementID: String
    public var predicate: GraphPredicate
    public var depth: Int

    public init(entityID: String, viaStatementID: String, predicate: GraphPredicate, depth: Int) {
        self.entityID = entityID
        self.viaStatementID = viaStatementID
        self.predicate = predicate
        self.depth = depth
    }
}

public protocol GraphTraversalStore: Sendable {
    func neighbors(of entityID: String, graphID: String, depth: Int, limit: Int) throws -> [GraphNeighbor]
    func shortestHopDistances(from centerEntityIDs: [String], to candidateEntityIDs: [String], graphID: String, maxDepth: Int) throws -> [String: Int]
    func statementsAdjacent(to entityID: String, graphID: String, limit: Int) throws -> [GraphStatement]
}

public struct SQLiteGraphTraversalStore: GraphTraversalStore, Sendable {
    public var store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func neighbors(of entityID: String, graphID: String, depth: Int, limit: Int) throws -> [GraphNeighbor] {
        guard depth > 0, limit > 0 else { return [] }
        var visited: Set<String> = [entityID]
        var frontier: Set<String> = [entityID]
        var results: [GraphNeighbor] = []

        for currentDepth in 1...depth {
            var nextFrontier: Set<String> = []
            for currentEntityID in frontier.sorted() {
                let statements = try statementsAdjacent(to: currentEntityID, graphID: graphID, limit: max(limit * 4, limit))
                for statement in statements {
                    let neighborID = statement.subjectEntityID == currentEntityID ? statement.objectEntityID : statement.subjectEntityID
                    guard !visited.contains(neighborID) else { continue }
                    visited.insert(neighborID)
                    nextFrontier.insert(neighborID)
                    results.append(GraphNeighbor(entityID: neighborID, viaStatementID: statement.id, predicate: statement.predicate, depth: currentDepth))
                    if results.count >= limit { return sorted(results) }
                }
            }
            frontier = nextFrontier
            if frontier.isEmpty { break }
        }

        return sorted(results)
    }

    public func shortestHopDistances(from centerEntityIDs: [String], to candidateEntityIDs: [String], graphID: String, maxDepth: Int) throws -> [String: Int] {
        guard maxDepth >= 0, !centerEntityIDs.isEmpty, !candidateEntityIDs.isEmpty else { return [:] }
        let candidates = Set(candidateEntityIDs)
        var distances: [String: Int] = [:]
        var visited = Set(centerEntityIDs)
        var frontier = Set(centerEntityIDs)

        for centerEntityID in centerEntityIDs where candidates.contains(centerEntityID) {
            distances[centerEntityID] = 0
        }
        guard maxDepth > 0 else { return distances }

        for depth in 1...maxDepth {
            var nextFrontier: Set<String> = []
            for entityID in frontier.sorted() {
                let statements = try statementsAdjacent(to: entityID, graphID: graphID, limit: 1_000)
                for statement in statements {
                    let neighborID = statement.subjectEntityID == entityID ? statement.objectEntityID : statement.subjectEntityID
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

    public func statementsAdjacent(to entityID: String, graphID: String, limit: Int) throws -> [GraphStatement] {
        Array(try store.statements(graphID: graphID)
            .filter { $0.subjectEntityID == entityID || $0.objectEntityID == entityID }
            .prefix(max(0, limit)))
    }

    private func sorted(_ neighbors: [GraphNeighbor]) -> [GraphNeighbor] {
        neighbors.sorted { lhs, rhs in
            if lhs.depth == rhs.depth {
                if lhs.entityID == rhs.entityID { return lhs.viaStatementID < rhs.viaStatementID }
                return lhs.entityID < rhs.entityID
            }
            return lhs.depth < rhs.depth
        }
    }
}
