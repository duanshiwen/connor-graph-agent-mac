import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct CloudKnowledgeAnswerTool: AgentTool {
    public let name = "cloud_kb_answer"
    public let description = "Search current committed knowledge from explicitly subscribed cloud knowledge bases. Returns separate L2 recent state, L3 reusable knowledge, and L4 stable entity/relation partitions within a context budget. Subscription authorization is checked before retrieval and cached results are revoked immediately on unsubscribe."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "query": .string(description: "Question or knowledge query."),
        "knowledge_base_ids": .array(items: .string(description: "Subscribed knowledge base ID."), description: "One or more explicitly subscribed knowledge bases."),
        "context_budget": .integer(description: "Maximum returned context characters."),
        "limit": .integer(description: "Maximum result count.")
    ], required: ["query", "knowledge_base_ids", "context_budget", "limit"])
    private let client: CloudKnowledgeConsumptionClient
    public init(client: CloudKnowledgeConsumptionClient) { self.client = client }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let query = arguments.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { throw AgentToolError.invalidArguments("query is required") }
        let ids = arguments.array("knowledge_base_ids")?.compactMap(\.stringValue) ?? []; guard !ids.isEmpty else { throw AgentToolError.invalidArguments("knowledge_base_ids is required") }
        let response = try await client.answer(.init(query: query, knowledgeBaseIDs: ids, contextBudget: max(1_000, min(arguments.int("context_budget") ?? 8_000, 32_000)), limit: max(1, min(arguments.int("limit") ?? 20, 100))))
        let text = response.partitions.map { partition in
            let rows = partition.results.enumerated().map { index, hit in "\(index + 1). \(hit.title ?? hit.stableKey ?? hit.kind): \(hit.text)" }.joined(separator: "\n")
            return "## \(partition.layer.rawValue)\n\(rows.isEmpty ? "No results." : rows)"
        }.joined(separator: "\n\n")
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: text, contentJSON: String(data: try encoder.encode(response), encoding: .utf8), citations: response.partitions.flatMap(\.results).compactMap(\.revisionID))
    }
}

public extension AgentToolRegistry { mutating func registerCloudKnowledgeConsumptionTool(client: CloudKnowledgeConsumptionClient) { register(CloudKnowledgeAnswerTool(client: client)) } }
