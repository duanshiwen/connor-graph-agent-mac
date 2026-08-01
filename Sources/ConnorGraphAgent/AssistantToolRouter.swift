import Foundation

public enum AssistantToolTier: String, Codable, Sendable, Equatable {
    case runtimeInternal
    case alwaysVisible
    case discoverable
}

public struct AssistantToolRoute: Sendable, Equatable {
    public var modelVisibleDefinitions: [AgentToolDefinition]
    public var discoverableDefinitions: [AgentToolDefinition]

    public init(modelVisibleDefinitions: [AgentToolDefinition], discoverableDefinitions: [AgentToolDefinition]) {
        self.modelVisibleDefinitions = modelVisibleDefinitions
        self.discoverableDefinitions = discoverableDefinitions
    }
}

public struct AssistantToolRouter: Sendable, Equatable {
    public static let directToolNames: Set<String> = ["Shell", "ApplyPatch"]

    public init() {}

    public func route(definitions: [AgentToolDefinition]) -> AssistantToolRoute {
        let publicDefinitions = definitions.filter {
            !AssistantBootstrapCoordinator.internalToolNames.contains($0.name)
        }
        let direct = publicDefinitions.filter { Self.directToolNames.contains($0.name) }
        let discoverable = publicDefinitions.filter { !Self.directToolNames.contains($0.name) }
        return AssistantToolRoute(
            modelVisibleDefinitions: (AssistantDecisionToolContract.definitions + direct).sorted { $0.name < $1.name },
            discoverableDefinitions: discoverable.sorted { $0.name < $1.name }
        )
    }

    public func discover(
        query: String,
        definitions: [AgentToolDefinition],
        maximumResults: Int = 8
    ) -> [AgentToolDefinition] {
        let candidates = route(definitions: definitions).discoverableDefinitions
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count >= 2 }
        let ranked = candidates.compactMap { definition -> (AgentToolDefinition, Int)? in
            let haystack = "\(definition.name) \(definition.description)".lowercased()
            var score = terms.reduce(0) { $0 + (haystack.contains($1) ? 2 : 0) }
            if haystack.contains(normalizedQuery), !normalizedQuery.isEmpty { score += 4 }
            if definition.name.lowercased().contains(normalizedQuery), !normalizedQuery.isEmpty { score += 8 }
            return score > 0 ? (definition, score) : nil
        }
        let sorted = ranked.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.name < $1.0.name
        }
        guard let topScore = sorted.first?.1 else { return [] }
        return sorted
        .filter { $0.1 >= max(1, topScore - 1) }
        .prefix(max(1, min(maximumResults, 16)))
        .map(\.0)
    }

    public func compactCatalogSummary(definitions: [AgentToolDefinition]) -> String {
        let discoverable = route(definitions: definitions).discoverableDefinitions
        let families = Dictionary(grouping: discoverable, by: familyName(for:))
        let lines = families.keys.sorted().map { family in
            "- \(family): \(families[family]?.count ?? 0) tools"
        }
        return ([
            "## Tool Discovery",
            "Only direct workspace tools and control tools have stable schemas in this request. For any other capability, call assistant_tool_search once with a compact capability query, then invoke returned exact names and schemas through parallel_tool_query or parallel_tool_execute.",
            "Available families:"
        ] + lines).joined(separator: "\n")
    }

    private func familyName(for definition: AgentToolDefinition) -> String {
        let name = definition.name.lowercased()
        if let separator = name.firstIndex(of: "_") { return String(name[..<separator]) }
        return name
    }
}

public enum AssistantDecisionToolContract {
    public static let searchName = "assistant_tool_search"

    public static let definitions: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: searchName,
            description: "Search the current session's approved Tool Registry, MCP, and knowledge capabilities. Returns a small set of exact tool names with complete input schemas. Use once per missing capability and do not repeat the same query.",
            inputSchema: .closedObject(properties: [
                "query": .string(description: "Compact capability or domain query."),
                "maxResults": .integer(description: "Optional result limit from 1 through 16; default 8.")
            ], required: ["query"])
        ),
        AgentPhaseToolContract.definitions.first { $0.name == AgentPhaseToolContract.externalSearchBatchName }!,
        AgentPhaseToolContract.definitions.first { $0.name == AgentPhaseToolContract.externalReadBatchName }!
    ].sorted { $0.name < $1.name }
}
