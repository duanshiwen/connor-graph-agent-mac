import Foundation
import ConnorGraphAgent
import ConnorGraphCore

private enum CloudKnowledgeContextToolSupport {
    static let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "query": .string(description: "Use 2-5 focused search terms separated by semicolons (; or ；). Include aliases and both Chinese and English terms when useful."),
        "context_budget": .integer(description: "Optional maximum returned context characters. Defaults to 8000."),
        "limit": .integer(description: "Optional maximum result count. Defaults to 20.")
    ], required: ["query"])

    static func execute(
        toolName: String,
        channel: CloudKnowledgeSearchChannel,
        allowedLayers: Set<CloudKnowledgeLayer>,
        client: CloudKnowledgeConsumptionClient,
        knowledgeBaseIDs: [String],
        arguments: AgentToolArguments,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolResult {
        guard !knowledgeBaseIDs.isEmpty else {
            return AgentToolResult(
                toolCallID: context.toolCallID,
                toolName: toolName,
                contentText: "No remote knowledge bases are selected for this session. Do not use remote knowledge context from earlier user runs.",
                contentJSON: "{\"channel\":\"\(channel.rawValue)\",\"knowledge_base_ids\":[],\"partitions\":[]}",
                citations: []
            )
        }
        guard let query = arguments.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            throw AgentToolError.invalidArguments("query is required")
        }
        let request = CloudKnowledgeAnswerRequest(
            query: query,
            knowledgeBaseIDs: knowledgeBaseIDs,
            contextBudget: max(1_000, min(arguments.int("context_budget") ?? 8_000, 32_000)),
            limit: max(1, min(arguments.int("limit") ?? 20, 100))
        )
        let response = try await client.context(request, channel: channel)
        let partitions = response.partitions
            .filter { allowedLayers.contains($0.layer) }
            .map { CloudKnowledgeAnswerPartition(layer: $0.layer, results: $0.results.filter { allowedLayers.contains($0.layer) }) }
        let filtered = CloudKnowledgeAnswerResponse(
            requestID: response.requestID,
            channel: channel,
            partitions: partitions,
            returnedBytes: response.returnedBytes,
            knowledgeSequence: response.knowledgeSequence
        )
        let text = partitions.map { partition in
            let rows = partition.results.enumerated().map { index, hit -> String in
                let timestamp = hit.updatedAt.map { " [updated_at: \(ISO8601DateFormatter().string(from: $0))]" } ?? ""
                return "\(index + 1). \(hit.title ?? hit.stableKey ?? hit.kind): \(hit.text)\(timestamp)"
            }.joined(separator: "\n")
            return "## \(partition.layer.rawValue)\n\(rows.isEmpty ? "No results." : rows)"
        }.joined(separator: "\n\n")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: toolName,
            contentText: text.isEmpty ? "No matching cloud knowledge context." : text,
            contentJSON: String(data: try encoder.encode(filtered), encoding: .utf8),
            citations: partitions.flatMap(\.results).compactMap(\.revisionID)
        )
    }
}

public struct CloudKnowledgeRecentContextTool: AgentTool {
    public let name = "cloud_kb_recent_context"
    public let description: String
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = CloudKnowledgeContextToolSupport.inputSchema
    private let client: CloudKnowledgeConsumptionClient
    private let knowledgeBaseIDs: [String]

    public init(client: CloudKnowledgeConsumptionClient, knowledgeBaseIDs: [String]) {
        let resolvedIDs = Array(Set(knowledgeBaseIDs)).sorted()
        self.client = client
        self.knowledgeBaseIDs = resolvedIDs
        self.description = resolvedIDs.isEmpty
            ? "No remote knowledge bases are selected for this session. Do not call this tool or reuse remote knowledge context from earlier user runs."
            : "Search only L2 mutable operational context from the remote knowledge bases selected for this session, including current project or task state, recent decisions, and other time-sensitive facts. Compare recorded_at when results conflict. This tool never returns L3/L4 durable knowledge."
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try await CloudKnowledgeContextToolSupport.execute(
            toolName: name,
            channel: .recentContext,
            allowedLayers: [.l2],
            client: client,
            knowledgeBaseIDs: knowledgeBaseIDs,
            arguments: arguments,
            context: context
        )
    }
}

public struct CloudKnowledgeKnowledgeContextTool: AgentTool {
    public let name = "cloud_kb_knowledge_context"
    public let description: String
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = CloudKnowledgeContextToolSupport.inputSchema
    private let client: CloudKnowledgeConsumptionClient
    private let knowledgeBaseIDs: [String]

    public init(client: CloudKnowledgeConsumptionClient, knowledgeBaseIDs: [String]) {
        let resolvedIDs = Array(Set(knowledgeBaseIDs)).sorted()
        self.client = client
        self.knowledgeBaseIDs = resolvedIDs
        self.description = resolvedIDs.isEmpty
            ? "No remote knowledge bases are selected for this session. Do not call this tool or reuse remote knowledge context from earlier user runs."
            : "Search only L3/L4 durable context from the remote knowledge bases selected for this session, including reusable knowledge, stable entities, concepts, and durable relationships. Do not use these results as proof of current operational state."
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try await CloudKnowledgeContextToolSupport.execute(
            toolName: name,
            channel: .knowledgeContext,
            allowedLayers: [.l3, .l4],
            client: client,
            knowledgeBaseIDs: knowledgeBaseIDs,
            arguments: arguments,
            context: context
        )
    }
}

public extension AgentToolRegistry {
    mutating func registerCloudKnowledgeConsumptionTools(client: CloudKnowledgeConsumptionClient, knowledgeBaseIDs: [String]) {
        register(CloudKnowledgeRecentContextTool(client: client, knowledgeBaseIDs: knowledgeBaseIDs))
        register(CloudKnowledgeKnowledgeContextTool(client: client, knowledgeBaseIDs: knowledgeBaseIDs))
    }
}
