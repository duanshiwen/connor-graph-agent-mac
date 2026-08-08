import Foundation
import ConnorGraphAgent
import ConnorGraphCore

/// IM 聊天记录检索源（对齐 Android imDao.searchConversations）：让 session_search 一并覆盖 IM 对话。
public protocol ImTranscriptSearchProviding: Sendable {
    func searchConversations(query: String, limit: Int) async throws -> [ImConversationSearchHit]
}

extension SQLiteImStore: ImTranscriptSearchProviding {}

public struct SessionSearchToolRecord: Codable, Sendable, Equatable {
    public var sessionID: String
    /// 来源类型：session（与 Connor 的会话）、im_peer（单聊）、im_group（群聊）。
    public var kind: String
    public var title: String
    public var snippet: String
    public var messageCount: Int
    public var updatedAt: Date

    public init(sessionID: String, kind: String = "session", title: String, snippet: String, messageCount: Int, updatedAt: Date) {
        self.sessionID = sessionID
        self.kind = kind
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
    public let description = "Search Connor's local chat history — both chat sessions (full-transcript index) and IM conversations — using compact topic terms, entity names, or a subject phrase. Use this when Memory OS context searches returned insufficient results, or to verify whether a topic was ever discussed in past chats. Returns summary candidates with source kind (session / im_peer / im_group), title, snippet, and updated time. A successful empty result means no local chat matches; never claim memory or transcripts were searched unless this tool or memory_os_* tools were actually called."
    public let permission: AgentPermissionCapability = .readGraph
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "query": .string(description: "Compact lexical topic/entity terms, e.g. '择偶' or '伴侣选择'. Required."),
        "limit": .integer(description: "Optional maximum number of hits. Defaults to 10 and must be between 1 and 50.")
    ], required: ["query"])

    private let sessionSearch: any SessionSearchProviding
    private let imTranscriptSearch: (any ImTranscriptSearchProviding)?

    public init(
        sessionSearch: any SessionSearchProviding,
        imTranscriptSearch: (any ImTranscriptSearchProviding)? = nil
    ) {
        self.sessionSearch = sessionSearch
        self.imTranscriptSearch = imTranscriptSearch
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let query = arguments.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            throw AgentToolError.invalidArguments("query is required and must be non-empty")
        }
        let limit = max(1, min(arguments.int("limit") ?? 10, 50))
        let sessionResults = try await sessionSearch.search(query: query, limit: limit)
        var records = sessionResults.map { result in
            SessionSearchToolRecord(
                sessionID: result.id,
                kind: "session",
                title: result.title,
                snippet: result.snippet,
                messageCount: result.messageCount,
                updatedAt: result.updatedAt
            )
        }
        if let imTranscriptSearch {
            let imHits = try await imTranscriptSearch.searchConversations(query: query, limit: limit)
            for hit in imHits {
                let conversation = hit.conversation
                let timestampMillis = max(conversation.lastMessageAt, conversation.updatedAt)
                records.append(SessionSearchToolRecord(
                    sessionID: conversation.id,
                    kind: conversation.kind == .group ? "im_group" : "im_peer",
                    title: conversation.title.isEmpty ? conversation.participantName : conversation.title,
                    snippet: hit.snippet.isEmpty ? conversation.lastMessagePreview : hit.snippet,
                    messageCount: 0,
                    updatedAt: Date(timeIntervalSince1970: Double(max(timestampMillis, 0)) / 1_000)
                ))
            }
        }
        records.sort { $0.updatedAt > $1.updatedAt }
        records = Array(records.prefix(limit))
        let response = SessionSearchToolResponse(
            success: true,
            reason: "Returned \(records.count) chat candidate(s) matching local sessions and IM conversations.",
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
            citations: records.map { "\($0.kind):\($0.sessionID)" }
        )
    }
}
