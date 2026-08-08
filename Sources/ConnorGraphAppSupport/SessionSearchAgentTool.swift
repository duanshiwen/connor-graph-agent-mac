import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct SessionSearchToolRecord: Codable, Sendable, Equatable {
    public var sessionID: String
    public var title: String
    public var snippet: String
    public var messageCount: Int
    public var updatedAt: Date

    public init(sessionID: String, title: String, snippet: String, messageCount: Int, updatedAt: Date) {
        self.sessionID = sessionID
        self.title = title
        self.snippet = snippet
        self.messageCount = messageCount
        self.updatedAt = updatedAt
    }
}

public struct SessionSearchToolResponse: Codable, Sendable, Equatable {
    public var success: Bool
    public var reason: String
    public var query: String
    public var returnedItems: Int
    public var totalItems: Int
    public var records: [SessionSearchToolRecord]

    public init(success: Bool, reason: String, query: String, returnedItems: Int, totalItems: Int, records: [SessionSearchToolRecord]) {
        self.success = success
        self.reason = reason
        self.query = query
        self.returnedItems = returnedItems
        self.totalItems = totalItems
        self.records = records
    }
}

public struct SessionSearchTool: AgentTool {
    public let name = "session_search"
    public let description = "Search Connor's local session full-text transcript index using compact topic terms, entity names, or a subject phrase. Use this when Memory OS context searches returned no matching records, or to verify whether a topic was ever discussed in past chats. Returns summary candidates with session title, snippet, message count, and updated time. A successful empty result means the transcript index has no matching chat; never claim memory or transcripts were searched unless this tool or memory_os_* tools were actually called."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "query": .string(description: "Compact lexical topic/entity terms, e.g. '择偶' or '伴侣选择'. Required."),
        "limit": .integer(description: "Optional maximum number of hits. Defaults to 10 and must be between 1 and 50.")
    ], required: ["query"])

    private let sessionSearch: any SessionSearchProviding

    public init(sessionSearch: any SessionSearchProviding) {
        self.sessionSearch = sessionSearch
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let query = arguments.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            throw AgentToolError.invalidArguments("query is required and must be non-empty")
        }
        let limit = max(1, min(arguments.int("limit") ?? 10, 50))
        let results = try await sessionSearch.search(query: query, limit: limit)
        let records = results.map { result in
            SessionSearchToolRecord(
                sessionID: result.id,
                title: result.title,
                snippet: result.snippet,
                messageCount: result.messageCount,
                updatedAt: result.updatedAt
            )
        }
        let response = SessionSearchToolResponse(
            success: true,
            reason: "Returned \(records.count) session candidate(s) matching the transcript index.",
            query: query,
            returnedItems: records.count,
            totalItems: records.count,
            records: records
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(response)
        let payload = String(data: json, encoding: .utf8) ?? "{}"
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: payload,
            contentJSON: payload,
            citations: results.map { "session:\($0.id)" }
        )
    }
}
