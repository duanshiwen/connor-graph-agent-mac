import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct ConversationHistoryMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String { messageID }
    public var messageID: String
    public var sessionID: String
    public var sessionTitle: String
    public var role: AgentRole
    public var content: String
    public var createdAt: Date
}

public struct ConversationHistorySearchResponse: Codable, Sendable, Equatable {
    public var query: String
    public var startDate: Date
    public var endDate: Date
    public var returnedCount: Int
    public var hasMore: Bool
    public var messages: [ConversationHistoryMessage]
}

public struct ConversationHistorySearchTool: AgentTool {
    public let name = "conversation_history_search"
    public let description = "Read user requests and Connor assistant replies across all conversations within an ISO-8601 time range. Use this before Memory OS when reviewing yesterday or another single recent day. Leave query empty to return all messages in the period; provide query to filter by topic. startDate is inclusive and endDate is exclusive."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "query": .string(description: "Optional topic filter. Leave empty to return all user and assistant messages in the time range."),
        "startDate": .string(description: "Inclusive ISO-8601 range start."),
        "endDate": .string(description: "Exclusive ISO-8601 range end."),
        "limit": .integer(description: "Maximum messages to return. Defaults to 200; increase when hasMore is true.")
    ], required: ["startDate", "endDate"])

    private let repository: AppChatSessionRepository

    public init(repository: AppChatSessionRepository) {
        self.repository = repository
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let startDate = try Self.dateArgument("startDate", arguments: arguments)
        let endDate = try Self.dateArgument("endDate", arguments: arguments)
        guard startDate < endDate else { throw AgentToolError.invalidArguments("startDate must be earlier than endDate") }
        let query = arguments.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let limit = max(1, arguments.int("limit") ?? 200)
        let normalizedQuery = query.lowercased()

        let candidates = try repository.loadRecentSessions(limit: Int.max).flatMap { session in
            session.messages.compactMap { message -> ConversationHistoryMessage? in
                guard message.role == .user || message.role == .assistant else { return nil }
                guard message.createdAt >= startDate && message.createdAt < endDate else { return nil }
                if !normalizedQuery.isEmpty && !message.content.lowercased().contains(normalizedQuery) { return nil }
                return ConversationHistoryMessage(
                    messageID: message.id,
                    sessionID: session.id,
                    sessionTitle: session.title,
                    role: message.role,
                    content: message.content,
                    createdAt: message.createdAt
                )
            }
        }.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.messageID < rhs.messageID
        }
        let messages = Array(candidates.prefix(limit))
        let response = ConversationHistorySearchResponse(
            query: query,
            startDate: startDate,
            endDate: endDate,
            returnedCount: messages.count,
            hasMore: candidates.count > messages.count,
            messages: messages
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(response), encoding: .utf8) ?? "{}"
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: json,
            contentJSON: json,
            citations: messages.map(\.messageID)
        )
    }

    private static func dateArgument(_ name: String, arguments: AgentToolArguments) throws -> Date {
        guard let raw = arguments.string(name)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw AgentToolError.invalidArguments("\(name) is required")
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
            throw AgentToolError.invalidArguments("\(name) must be an ISO-8601 timestamp")
        }
        return date
    }
}

public extension AgentToolRegistry {
    mutating func registerConversationHistoryTools(repository: AppChatSessionRepository) {
        register(ConversationHistorySearchTool(repository: repository))
    }
}
