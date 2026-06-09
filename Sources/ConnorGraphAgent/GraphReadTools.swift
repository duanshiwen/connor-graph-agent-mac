import Foundation
import ConnorGraphCore
import ConnorGraphSearch

public struct GraphSearchTool: AgentTool {
    public let name = "graph_search"
    public let description = "Search the local temporal knowledge graph across nodes, facts, and episodes."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "query": .string(description: "Search query."),
        "limit": .integer(description: "Maximum number of hits to return."),
        "includeNodes": .boolean(description: "Whether to include graph nodes."),
        "includeFacts": .boolean(description: "Whether to include graph facts."),
        "includeEpisodes": .boolean(description: "Whether to include graph episodes.")
    ], required: ["query"])

    private let searchService: any GraphHybridSearchService

    public init(searchService: any GraphHybridSearchService) {
        self.searchService = searchService
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let query = arguments.string("query"), !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("graph_search requires non-empty query")
        }
        let limit = arguments.int("limit") ?? 10
        let response = try await searchService.search(query: GraphSearchQuery(
            text: query,
            groupID: context.groupID,
            includeNodes: arguments.bool("includeNodes") ?? true,
            includeFacts: arguments.bool("includeFacts") ?? true,
            includeEpisodes: arguments.bool("includeEpisodes") ?? true,
            limit: max(1, min(limit, 50))
        ))
        let json = try renderJSON(response.hits)
        let text = response.hits.enumerated().map { index, hit in
            "\(index + 1). [\(hit.id)] \(hit.title) — \(hit.text) (score: \(String(format: "%.4f", hit.score)), method: \(hit.retrievalMethod))"
        }.joined(separator: "\n")
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: text.isEmpty ? "No graph search hits." : text,
            contentJSON: json,
            citations: response.hits.map(\.id)
        )
    }

    private func renderJSON(_ hits: [GraphSearchHit]) throws -> String {
        let rows: [[String: Any]] = hits.map { hit in
            [
                "id": hit.id,
                "ownerType": hit.ownerType.rawValue,
                "ownerID": hit.ownerID,
                "title": hit.title,
                "text": hit.text,
                "score": hit.score,
                "retrievalMethod": hit.retrievalMethod,
                "sourceEpisodeIDs": hit.sourceEpisodeIDs,
                "metadata": hit.metadata
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["hits": rows], options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{\"hits\":[]}"
    }
}
