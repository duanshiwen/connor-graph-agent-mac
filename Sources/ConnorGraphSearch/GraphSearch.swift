import Foundation

public enum GraphSearchResultKind: String, Codable, Sendable, Equatable {
    case node
    case edge
    case observeLog
}

public struct AgentContext: Sendable, Equatable {
    public var query: String
    public var items: [AgentContextItem]

    public init(query: String, items: [AgentContextItem]) {
        self.query = query
        self.items = items
    }

    public var renderedText: String {
        var lines: [String] = ["Query: \(query)"]
        for item in items {
            lines.append("Source: \(item.sourceID)")
            lines.append("Reason: \(item.reason)")
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

    public init(sourceID: String, kind: GraphSearchResultKind, content: String, reason: String) {
        self.sourceID = sourceID
        self.kind = kind
        self.content = content
        self.reason = reason
    }
}
