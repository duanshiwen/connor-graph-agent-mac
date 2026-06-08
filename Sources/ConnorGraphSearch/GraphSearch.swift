import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public enum GraphSearchResultKind: String, Codable, Sendable, Equatable {
    case node
    case edge
    case observeLog
}

public enum GraphSearchResult: Sendable, Equatable, Identifiable {
    case node(GraphNode, score: Double, reason: String)
    case edge(SemanticEdge, score: Double, reason: String)
    case observeLog(ObserveLogEntry, score: Double, reason: String)

    public var id: String {
        switch self {
        case .node(let node, _, _): "node:\(node.id)"
        case .edge(let edge, _, _): "edge:\(edge.id)"
        case .observeLog(let entry, _, _): "observe:\(entry.id)"
        }
    }

    public var kind: GraphSearchResultKind {
        switch self {
        case .node: .node
        case .edge: .edge
        case .observeLog: .observeLog
        }
    }

    public var score: Double {
        switch self {
        case .node(_, let score, _), .edge(_, let score, _), .observeLog(_, let score, _): score
        }
    }

    public var reason: String {
        switch self {
        case .node(_, _, let reason), .edge(_, _, let reason), .observeLog(_, _, let reason): reason
        }
    }
}

public struct GraphSearchOptions: Sendable, Equatable {
    public var includeNodes: Bool
    public var includeEdges: Bool
    public var includeObserveLog: Bool
    public var includeNeighborhood: Bool
    public var limit: Int

    public init(
        includeNodes: Bool = true,
        includeEdges: Bool = true,
        includeObserveLog: Bool = true,
        includeNeighborhood: Bool = false,
        limit: Int = 20
    ) {
        self.includeNodes = includeNodes
        self.includeEdges = includeEdges
        self.includeObserveLog = includeObserveLog
        self.includeNeighborhood = includeNeighborhood
        self.limit = limit
    }
}

public struct InMemoryGraphSearchIndex: Sendable {
    public var nodes: [GraphNode]
    public var edges: [SemanticEdge]
    public var observeLogEntries: [ObserveLogEntry]

    public init(nodes: [GraphNode], edges: [SemanticEdge], observeLogEntries: [ObserveLogEntry]) {
        self.nodes = nodes
        self.edges = edges
        self.observeLogEntries = observeLogEntries
    }

    public func search(query: String, options: GraphSearchOptions = .init()) throws -> [GraphSearchResult] {
        let terms = tokenize(query)
        guard !terms.isEmpty else { return [] }

        var results: [GraphSearchResult] = []
        var seen = Set<String>()

        if options.includeNodes {
            for node in nodes {
                let haystack = "\(node.title) \(node.summary) \(node.type.rawValue)".lowercased()
                if let score = matchScore(terms, in: haystack) {
                    append(.node(node, score: score, reason: "matched node title/summary"), to: &results, seen: &seen)
                }
            }
        }

        if options.includeEdges {
            for edge in edges {
                let haystack = "\(edge.fact) \(edge.relation.rawValue)".lowercased()
                if let score = matchScore(terms, in: haystack) {
                    append(.edge(edge, score: score, reason: "matched edge fact"), to: &results, seen: &seen)
                }
            }
        }

        if options.includeObserveLog {
            for entry in observeLogEntries where entry.status == .active {
                let haystack = "\(entry.content) \(entry.normalizedSummary) \(entry.kind.rawValue)".lowercased()
                if let score = matchScore(terms, in: haystack) {
                    append(.observeLog(entry, score: score, reason: "matched observe log"), to: &results, seen: &seen)
                }
            }
        }

        if options.includeNeighborhood {
            expandNeighborhood(from: Array(results), into: &results, seen: &seen)
        }

        return Array(results.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.id < rhs.id }
            return lhs.score > rhs.score
        }.prefix(options.limit))
    }

    private func expandNeighborhood(from seeds: [GraphSearchResult], into results: inout [GraphSearchResult], seen: inout Set<String>) {
        let nodeIDs = Set(seeds.compactMap { result -> String? in
            if case .node(let node, _, _) = result { return node.id }
            return nil
        })
        guard !nodeIDs.isEmpty else { return }

        for edge in edges where nodeIDs.contains(edge.sourceNodeID) || nodeIDs.contains(edge.targetNodeID) {
            append(.edge(edge, score: 0.7, reason: "one-hop neighborhood edge"), to: &results, seen: &seen)
            for node in nodes where node.id == edge.sourceNodeID || node.id == edge.targetNodeID {
                append(.node(node, score: 0.6, reason: "one-hop neighborhood node"), to: &results, seen: &seen)
            }
        }
    }

    private func append(_ result: GraphSearchResult, to results: inout [GraphSearchResult], seen: inout Set<String>) {
        guard !seen.contains(result.id) else { return }
        seen.insert(result.id)
        results.append(result)
    }

    private func tokenize(_ query: String) -> [String] {
        query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func matchScore(_ terms: [String], in haystack: String) -> Double? {
        let matched = terms.filter { haystack.contains($0) }.count
        guard matched > 0 else { return nil }
        return Double(matched) / Double(terms.count)
    }
}

public struct AgentContext: Sendable, Equatable {
    public var query: String
    public var items: [AgentContextItem]

    public var renderedText: String {
        var lines: [String] = ["Query: \(query)"]
        for item in items {
            lines.append("Source: \(item.sourceID)")
            lines.append(item.content)
        }
        return lines.joined(separator: "\n")
    }
}

public struct AgentContextItem: Sendable, Equatable, Identifiable {
    public var id: String { sourceID }
    public var sourceID: String
    public var kind: GraphSearchResultKind
    public var content: String
    public var reason: String
}

public struct ContextAssembler: Sendable, Equatable {
    public var maxObserveLogEntries: Int
    public var maxItems: Int

    public init(maxObserveLogEntries: Int = 5, maxItems: Int = 20) {
        self.maxObserveLogEntries = maxObserveLogEntries
        self.maxItems = maxItems
    }

    public func assemble(query: String, results: [GraphSearchResult]) -> AgentContext {
        let nonObserve = results.filter { $0.kind != .observeLog }
        let observe = results.filter { $0.kind == .observeLog }
            .sorted { lhs, rhs in observeTimestamp(lhs) > observeTimestamp(rhs) }
            .prefix(maxObserveLogEntries)
        let selected = Array((nonObserve + observe).prefix(maxItems))
        return AgentContext(query: query, items: selected.map(contextItem))
    }

    private func contextItem(_ result: GraphSearchResult) -> AgentContextItem {
        switch result {
        case .node(let node, _, let reason):
            return AgentContextItem(sourceID: result.id, kind: .node, content: "Node[\(node.type.rawValue)] \(node.title): \(node.summary)", reason: reason)
        case .edge(let edge, _, let reason):
            return AgentContextItem(sourceID: result.id, kind: .edge, content: "Edge[\(edge.relation.rawValue)] \(edge.fact)", reason: reason)
        case .observeLog(let entry, _, let reason):
            return AgentContextItem(sourceID: result.id, kind: .observeLog, content: "Observe[\(entry.kind.rawValue)] \(entry.content)", reason: reason)
        }
    }

    private func observeTimestamp(_ result: GraphSearchResult) -> Date {
        if case .observeLog(let entry, _, _) = result { return entry.timestamp }
        return .distantPast
    }
}
