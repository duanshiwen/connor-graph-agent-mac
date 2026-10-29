import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public extension AgentToolRegistry {
    mutating func registerSessionTools(repository: AppChatSessionRepository) {
        register(SessionListTool(repository: repository))
        register(SessionBatchDeleteTool(repository: repository))
    }
}

public struct SessionListTool: AgentTool {
    public let name = "session_list"
    public let description = "List Connor sessions with stable pagination. Copy sessions[].sessionID unchanged when deleting sessions. " + AgentToolBatchPagination.paginationContract(listToolName: "session_list")
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "page": .integer(description: "1-based page. Defaults to 1; use nextPage from the previous response."),
        "pageSize": .integer(description: "Items per page from 1 through 100. Defaults to 50 and must remain unchanged while following nextPage.")
    ], required: [])

    private let repository: AppChatSessionRepository

    public init(repository: AppChatSessionRepository) {
        self.repository = repository
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let page = arguments.int("page") ?? 1
        try AgentToolBatchPagination.validate(page: page)
        let pageSize = try AgentToolBatchPagination.validatedPageSize(arguments.int("pageSize") ?? arguments.int("page_size"))
        let sessions = try repository.loadSessionMetadata().sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
        let totalItems = sessions.count
        let totalPages = totalItems == 0 ? 0 : (totalItems + pageSize - 1) / pageSize
        guard page == 1 || page <= totalPages else {
            throw AgentToolError.invalidArguments("page \(page) exceeds totalPages \(totalPages)")
        }
        let start = min((page - 1) * pageSize, totalItems)
        let end = min(start + pageSize, totalItems)
        let items = sessions[start..<end].map { session in
            SessionListItem(
                sessionID: session.id,
                title: session.title,

                updatedAt: session.updatedAt
            )
        }
        let hasNextPage = end < totalItems
        let payload = SessionListPage(

            page: page,
            pageSize: pageSize,
            returnedItems: items.count,
            totalItems: totalItems,
            totalPages: totalPages,
            hasNextPage: hasNextPage,
            nextPage: hasNextPage ? page + 1 : nil,
            sessions: items
        )
        return try sessionJSONResult(
            payload,
            context: context,
            toolName: name,
            text: "Returned \(items.count) of \(totalItems) session(s) on page \(page).",
            modelContentUsesJSON: true
        )
    }
}

public struct SessionBatchDeleteTool: AgentTool {
    public let name = "session_batch_delete"
    public let description = "Delete one or more Connor sessions. Copy each sessionID exactly from session_list. The current session can never be deleted through this tool. Each item returns deleted, not_found, running_tasks, or failed so partial results are explicit; do not claim the whole batch succeeded unless every item reports deleted. Deletion is destructive and gated by user approval — only call this tool after the user explicitly asks to delete sessions, and report failures/conflicts instead of retrying blindly. " + AgentToolBatchPagination.batchContract(toolName: "session_batch_delete")
    public let permission: AgentPermissionCapability = .deleteSession
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "sessionIDs": .array(
            items: .string(description: "Exact sessionID returned by session_list; copy the field without renaming it."),
            description: "One or more sessions to delete (at most 50 per call; delete in batches of 50 and continue until all selected sessions are handled). Duplicate session IDs are processed once."
        ),
        "reason": .string(description: "Optional human-readable reason for the deletion.")
    ], required: ["sessionIDs"])

    public static let defaultMaxSessionIDsPerCall = AgentToolBatchPagination.defaultBatchSize

    private let repository: AppChatSessionRepository
    private let maxSessionIDsPerCall: Int

    public init(
        repository: AppChatSessionRepository,
        maxSessionIDsPerCall: Int = Self.defaultMaxSessionIDsPerCall
    ) {
        self.repository = repository
        self.maxSessionIDsPerCall = max(1, maxSessionIDsPerCall)
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let rawValues = arguments.array("sessionIDs") ?? arguments.array("session_ids") ?? []
        guard !rawValues.isEmpty else {
            throw AgentToolError.invalidArguments("sessionIDs must not be empty")
        }
        guard rawValues.count <= maxSessionIDsPerCall else {
            throw AgentToolError.invalidArguments("sessionIDs accepts at most \(maxSessionIDsPerCall) items per call; delete in batches of at most \(maxSessionIDsPerCall) and continue until all selected sessions are handled.")
        }
        var seen = Set<String>()
        var requestedIDs = Set<String>()
        var results: [SessionBatchDeleteItemResult] = []
        for value in rawValues {
            guard let sessionID = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionID.isEmpty else {
                results.append(SessionBatchDeleteItemResult(sessionID: "", outcome: "failed", message: "sessionID is required"))
                continue
            }
            requestedIDs.insert(sessionID)
            guard seen.insert(sessionID).inserted else { continue }
            if sessionID == context.sessionID {
                results.append(SessionBatchDeleteItemResult(
                    sessionID: sessionID,
                    outcome: "failed",
                    message: "当前会话不能通过工具删除，请使用会话列表界面操作。"
                ))
                continue
            }
            do {
                try repository.deleteSession(sessionID: sessionID)
                results.append(SessionBatchDeleteItemResult(sessionID: sessionID, outcome: "deleted", message: nil))
            } catch AppChatSessionRepositoryError.sessionNotFound {
                results.append(SessionBatchDeleteItemResult(sessionID: sessionID, outcome: "not_found", message: "Session not found."))
            } catch AppChatSessionRepositoryError.sessionHasRunningBackgroundTasks {
                results.append(SessionBatchDeleteItemResult(sessionID: sessionID, outcome: "running_tasks", message: "Session has running background tasks; cancel or wait before deleting."))
            } catch {
                results.append(SessionBatchDeleteItemResult(sessionID: sessionID, outcome: "failed", message: String(describing: error)))
            }
        }
        let payload = SessionBatchDeleteResponse(
            requestedItems: requestedIDs.count,
            deletedItems: results.filter { $0.outcome == "deleted" }.count,
            failedItems: results.filter { $0.outcome != "deleted" }.count,
            results: results
        )
        return try sessionJSONResult(
            payload,
            context: context,
            toolName: name,
            text: "Batch session deletion completed: \(payload.deletedItems) deleted, \(payload.failedItems) failed, not found, or blocked.",
            modelContentUsesJSON: true
        )
    }
}

private struct SessionListItem: Codable {
    var sessionID: String
    var title: String
    var updatedAt: Date
}

private struct SessionListPage: Codable {
    var page: Int
    var pageSize: Int
    var returnedItems: Int
    var totalItems: Int
    var totalPages: Int
    var hasNextPage: Bool
    var nextPage: Int?
    var sessions: [SessionListItem]
}

private struct SessionBatchDeleteItemResult: Codable {
    var sessionID: String
    var outcome: String
    var message: String?
}

private struct SessionBatchDeleteResponse: Codable {
    var requestedItems: Int
    var deletedItems: Int
    var failedItems: Int
    var results: [SessionBatchDeleteItemResult]
}

private func sessionJSONResult<T: Encodable>(
    _ payload: T,
    context: AgentToolExecutionContext,
    toolName: String,
    text: String,
    modelContentUsesJSON: Bool = false
) throws -> AgentToolResult {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let json = String(decoding: try encoder.encode(payload), as: UTF8.self)
    return AgentToolResult(
        toolCallID: context.toolCallID,
        toolName: toolName,
        contentText: modelContentUsesJSON ? json : text,
        contentJSON: json
    )
}
