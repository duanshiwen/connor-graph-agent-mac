import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct SessionGetStatusTool: AgentTool {
    public let name = "session_get_status"
    public let description = "Read the governance status for the current Connor session or a specific session."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "sessionID": .string(description: "Optional exact sessionID returned by session_list_by_status. Omit to read the current session status.")
    ], required: [])

    private let repository: AppChatSessionRepository

    public init(repository: AppChatSessionRepository) {
        self.repository = repository
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let sessionID = (arguments.string("sessionID") ?? arguments.string("session_id"))?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? context.sessionID
        guard let session = try repository.loadSession(id: sessionID) else {
            throw AgentToolError.invalidArguments("Session not found: \(sessionID)")
        }
        return try SessionStatusToolPayload.result(
            session: session,
            previousStatus: nil,
            context: context,
            toolName: name,
            text: "Session \(session.id) status is \(session.governance.status.rawValue) (\(session.governance.status.displayName))."
        )
    }
}

public struct SessionSetStatusTool: AgentTool {
    public let name = "session_set_status"
    public let description = "Set the governance status for the current Connor session or a specific session. Call `session_list_statuses` first to get the available status IDs."
    public let permission: AgentPermissionCapability = .mutateSessionStatus
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "sessionID": .string(description: "Optional exact sessionID returned by session_list_by_status. Omit to update the current session."),
        "status": .string(description: "Required exact status returned by session_list_statuses; copy the field without renaming it."),
        "reason": .string(description: "Optional human-readable reason for the status change.")
    ], required: ["status"])

    private let repository: AppChatSessionRepository
    private let governanceConfig: AppSessionGovernanceConfig

    public init(repository: AppChatSessionRepository, governanceConfig: AppSessionGovernanceConfig = .default) {
        self.repository = repository
        self.governanceConfig = governanceConfig
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let sessionID = (arguments.string("sessionID") ?? arguments.string("session_id"))?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? context.sessionID
        guard let statusRaw = arguments.string("status")?.trimmingCharacters(in: .whitespacesAndNewlines), !statusRaw.isEmpty else {
            throw AgentToolError.invalidArguments("status is required")
        }
        let availableIDs = governanceConfig.statuses.map(\.id)
        guard availableIDs.contains(statusRaw) else {
            throw AgentToolError.invalidArguments("Unsupported status '\(statusRaw)'. Available status IDs: \(availableIDs.joined(separator: ", ")). Call session_list_statuses to get the current list.")
        }
        let matched = governanceConfig.statuses.first { $0.id == statusRaw }
        let displayName = matched?.name ?? statusRaw
        let previousStatus = try repository.loadSession(id: sessionID)?.governance.status
        let updated = try repository.setStatus(sessionID: sessionID, statusRaw: statusRaw)
        if let reason = arguments.string("reason")?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            try repository.appendJournalEvent(
                runID: context.runID,
                sessionID: sessionID,
                kind: .sessionStatusChanged,
                action: "session_status_change_reason",
                message: reason,
                metadata: ["status": statusRaw]
            )
        }
        return try SessionStatusToolPayload.result(
            sessionID: updated.id,
            title: updated.title,
            statusID: statusRaw,
            statusDisplayName: displayName,
            previousStatus: previousStatus?.rawValue,
            availableStatuses: governanceConfig.statuses.map { SessionStatusToolPayload.StatusDefinition(id: $0.id, displayName: $0.name) },
            context: context,
            toolName: name
        )
    }
}

public extension AgentToolRegistry {
    mutating func registerSessionStatusTools(repository: AppChatSessionRepository, governanceConfig: AppSessionGovernanceConfig = .default) {
        register(SessionGetStatusTool(repository: repository))
        register(SessionSetStatusTool(repository: repository, governanceConfig: governanceConfig))
        register(SessionListByStatusTool(repository: repository, governanceConfig: governanceConfig))
        register(SessionBatchSetStatusTool(repository: repository, governanceConfig: governanceConfig))
        register(SessionBatchDeleteTool(repository: repository))
        register(SessionListStatusesTool(governanceConfig: governanceConfig))
    }
}

public struct SessionListByStatusTool: AgentTool {
    public let name = "session_list_by_status"
    public let description = "List Connor sessions, optionally filtered by governance status, with stable pagination. The response contains a sessions array; every item has an operation-ready sessionID that can be copied directly into session_set_status, session_batch_set_status updates[].sessionID, or session_batch_delete sessionIDs. " + AgentToolBatchPagination.paginationContract(listToolName: "session_list_by_status")
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "status": .string(description: "Optional exact status returned by session_list_statuses; copy the field without renaming it. Omit to list all sessions."),
        "page": .integer(description: "1-based page. Defaults to 1; use nextPage from the previous response."),
        "pageSize": .integer(description: "Items per page from 1 through 100. Defaults to 50 and must remain unchanged while following nextPage.")
    ], required: [])

    private let repository: AppChatSessionRepository
    private let governanceConfig: AppSessionGovernanceConfig

    public init(repository: AppChatSessionRepository, governanceConfig: AppSessionGovernanceConfig = .default) {
        self.repository = repository
        self.governanceConfig = governanceConfig
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let status = arguments.string("status")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let status { try validateStatus(status, governanceConfig: governanceConfig) }
        let page = arguments.int("page") ?? 1
        try AgentToolBatchPagination.validate(page: page)
        let pageSize = try AgentToolBatchPagination.validatedPageSize(arguments.int("pageSize") ?? arguments.int("page_size"))
        let sessions = try repository.loadSessionMetadata().filter { session in
            status == nil || session.governance.status.rawValue == status
        }.sorted {
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
            SessionStatusListItem(
                sessionID: session.id,
                title: session.title,
                status: session.governance.status.rawValue,
                statusDisplayName: displayName(for: session.governance.status.rawValue, governanceConfig: governanceConfig),
                updatedAt: session.updatedAt
            )
        }
        let hasNextPage = end < totalItems
        let payload = SessionStatusListPage(
            statusFilter: status,
            page: page,
            pageSize: pageSize,
            returnedItems: items.count,
            totalItems: totalItems,
            totalPages: totalPages,
            hasNextPage: hasNextPage,
            nextPage: hasNextPage ? page + 1 : nil,
            sessions: items
        )
        return try sessionStatusJSONResult(
            payload,
            context: context,
            toolName: name,
            text: "Returned \(items.count) of \(totalItems) session(s) on page \(page).",
            modelContentUsesJSON: true
        )
    }
}

public struct SessionBatchSetStatusTool: AgentTool {
    public let name = "session_batch_set_status"
    public let description = "Set multiple Connor sessions to one status. Copy each sessionID directly from session_list_by_status. Each item returns updated, unchanged, not_found, conflict, or failed so partial success is explicit. Repeating the same request is idempotent: sessions already at the target status return unchanged. Optional expectedUpdatedAt enables caller-visible optimistic concurrency; updates are compare-and-set even when it is omitted. " + AgentToolBatchPagination.batchContract(toolName: "session_batch_set_status")
    public let permission: AgentPermissionCapability = .mutateSessionStatus
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "updates": .array(items: .closedObject(properties: [
            "sessionID": .string(description: "Exact sessionID returned by session_list_by_status; copy the field without renaming it."),
            "expectedUpdatedAt": .string(description: "Optional ISO-8601 updatedAt value returned by session_list_by_status.")
        ], required: ["sessionID"]), description: "One or more session updates. Duplicate session IDs are processed once."),
        "status": .string(description: "Exact status returned by session_list_statuses; copy the field without renaming it."),
        "reason": .string(description: "Optional reason recorded for successfully updated sessions.")
    ], required: ["updates", "status"])

    private let repository: AppChatSessionRepository
    private let governanceConfig: AppSessionGovernanceConfig
    private let maxItemsPerCall: Int

    public init(
        repository: AppChatSessionRepository,
        governanceConfig: AppSessionGovernanceConfig = .default,
        maxItemsPerCall: Int = AgentToolBatchPagination.defaultBatchSize
    ) {
        self.repository = repository
        self.governanceConfig = governanceConfig
        self.maxItemsPerCall = max(1, maxItemsPerCall)
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let status = arguments.string("status")?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty else {
            throw AgentToolError.invalidArguments("status is required")
        }
        try validateStatus(status, governanceConfig: governanceConfig)
        guard let values = arguments.array("updates"), !values.isEmpty else {
            throw AgentToolError.invalidArguments("updates must not be empty")
        }
        guard values.count <= maxItemsPerCall else {
            throw AgentToolError.invalidArguments("updates accepts at most \(maxItemsPerCall) items per call; split into batches of at most \(maxItemsPerCall) and continue until every item is handled.")
        }
        var seen = Set<String>()
        var results: [SessionBatchStatusItemResult] = []
        let formatter = ISO8601DateFormatter()
        for value in values {
            guard let object = value.objectValue,
                  let sessionID = (object["sessionID"] ?? object["session_id"])?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sessionID.isEmpty else {
                results.append(.init(sessionID: "", outcome: "failed", status: nil, updatedAt: nil, message: "sessionID is required"))
                continue
            }
            guard seen.insert(sessionID).inserted else { continue }
            let expectedRaw = (object["expectedUpdatedAt"] ?? object["expected_updated_at"])?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedUpdatedAt: Date?
            if let expectedRaw, !expectedRaw.isEmpty {
                guard let parsed = formatter.date(from: expectedRaw) else {
                    results.append(.init(sessionID: sessionID, outcome: "failed", status: nil, updatedAt: nil, message: "expectedUpdatedAt must be ISO-8601"))
                    continue
                }
                expectedUpdatedAt = parsed
            } else {
                expectedUpdatedAt = nil
            }
            do {
                let outcome = try repository.setStatusOptimistically(
                    sessionID: sessionID,
                    statusRaw: status,
                    expectedUpdatedAt: expectedUpdatedAt
                )
                switch outcome {
                case .updated(let session, let persistenceWarning):
                    var warnings = [persistenceWarning].compactMap { $0 }
                    if let reason = arguments.string("reason")?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                        do {
                            try repository.appendJournalEvent(runID: context.runID, sessionID: sessionID, kind: .sessionStatusChanged, action: "session_status_change_reason", message: reason, metadata: ["status": status])
                        } catch {
                            warnings.append("Status was updated, but the reason journal failed: \(error)")
                        }
                    }
                    results.append(.init(sessionID: sessionID, outcome: "updated", status: status, updatedAt: session.updatedAt, message: warnings.isEmpty ? nil : warnings.joined(separator: " ")))
                case .unchanged(let session):
                    results.append(.init(sessionID: sessionID, outcome: "unchanged", status: status, updatedAt: session.updatedAt, message: "Session already has the target status."))
                case .conflict(let session):
                    results.append(.init(sessionID: sessionID, outcome: "conflict", status: session.governance.status.rawValue, updatedAt: session.updatedAt, message: "Session changed concurrently; reload before retrying."))
                }
            } catch AppChatSessionRepositoryError.sessionNotFound {
                results.append(.init(sessionID: sessionID, outcome: "not_found", status: nil, updatedAt: nil, message: "Session not found."))
            } catch {
                results.append(.init(sessionID: sessionID, outcome: "failed", status: nil, updatedAt: nil, message: String(describing: error)))
            }
        }
        let payload = SessionBatchStatusResponse(
            requestedItems: Set<String>(values.compactMap { value in
                guard let object = value.objectValue else { return nil }
                return (object["sessionID"] ?? object["session_id"])?.stringValue
            }).count,
            updatedItems: results.filter { $0.outcome == "updated" }.count,
            unchangedItems: results.filter { $0.outcome == "unchanged" }.count,
            failedItems: results.filter { !["updated", "unchanged"].contains($0.outcome) }.count,
            results: results
        )
        return try sessionStatusJSONResult(
            payload,
            context: context,
            toolName: name,
            text: "Batch status update completed: \(payload.updatedItems) updated, \(payload.unchangedItems) unchanged, \(payload.failedItems) failed or conflicted.",
            modelContentUsesJSON: true
        )
    }
}

public struct SessionListStatusesTool: AgentTool {
    public let name = "session_list_statuses"
    public let description = "List all user-defined session statuses available for this Connor installation. Returns status id and display name."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [:], required: [])

    private let governanceConfig: AppSessionGovernanceConfig

    public init(governanceConfig: AppSessionGovernanceConfig) {
        self.governanceConfig = governanceConfig
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let statuses = governanceConfig.statuses.map { status -> [String: String] in
            ["id": status.id, "status": status.id, "name": status.name]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(statuses), as: UTF8.self)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: json,
            contentJSON: json
        )
    }
}

public struct SessionBatchDeleteTool: AgentTool {
    public let name = "session_batch_delete"
    public let description = "Delete one or more Connor sessions. Copy each sessionID exactly from session_list_by_status. The current session can never be deleted through this tool. Each item returns deleted, not_found, running_tasks, or failed so partial results are explicit; do not claim the whole batch succeeded unless every item reports deleted. Deletion is destructive and gated by user approval — only call this tool after the user explicitly asks to delete sessions, and report failures/conflicts instead of retrying blindly. " + AgentToolBatchPagination.batchContract(toolName: "session_batch_delete")
    public let permission: AgentPermissionCapability = .deleteSession
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "sessionIDs": .array(
            items: .string(description: "Exact sessionID returned by session_list_by_status; copy the field without renaming it."),
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
        return try sessionStatusJSONResult(
            payload,
            context: context,
            toolName: name,
            text: "Batch session deletion completed: \(payload.deletedItems) deleted, \(payload.failedItems) failed, not found, or blocked.",
            modelContentUsesJSON: true
        )
    }
}

private struct SessionStatusToolPayload: Codable {
    var sessionID: String
    var title: String
    var status: String
    var statusDisplayName: String
    var previousStatus: String?
    var availableStatuses: [StatusDefinition]

    struct StatusDefinition: Codable {
        var id: String
        var displayName: String
    }

    static func result(
        session: AgentSession,
        previousStatus: AgentSessionStatus?,
        context: AgentToolExecutionContext,
        toolName: String,
        text: String
    ) throws -> AgentToolResult {
        let payload = SessionStatusToolPayload(
            sessionID: session.id,
            title: session.title,
            status: session.governance.status.rawValue,
            statusDisplayName: session.governance.status.displayName,
            previousStatus: previousStatus?.rawValue,
            availableStatuses: AgentSessionStatus.allCases.map { StatusDefinition(id: $0.rawValue, displayName: $0.displayName) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(payload), as: UTF8.self)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: toolName, contentText: text, contentJSON: json)
    }

    static func result(
        sessionID: String,
        title: String,
        statusID: String,
        statusDisplayName: String,
        previousStatus: String?,
        availableStatuses: [StatusDefinition],
        context: AgentToolExecutionContext,
        toolName: String
    ) throws -> AgentToolResult {
        let payload = SessionStatusToolPayload(
            sessionID: sessionID,
            title: title,
            status: statusID,
            statusDisplayName: statusDisplayName,
            previousStatus: previousStatus,
            availableStatuses: availableStatuses
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(payload), as: UTF8.self)
        let text = "Updated session \(sessionID) status to \(statusID) (\(statusDisplayName))."
        return AgentToolResult(toolCallID: context.toolCallID, toolName: toolName, contentText: text, contentJSON: json)
    }
}

private struct SessionStatusListItem: Codable {
    var sessionID: String
    var title: String
    var status: String
    var statusDisplayName: String
    var updatedAt: Date
}

private struct SessionStatusListPage: Codable {
    var statusFilter: String?
    var page: Int
    var pageSize: Int
    var returnedItems: Int
    var totalItems: Int
    var totalPages: Int
    var hasNextPage: Bool
    var nextPage: Int?
    var sessions: [SessionStatusListItem]
}

private struct SessionBatchStatusItemResult: Codable {
    var sessionID: String
    var outcome: String
    var status: String?
    var updatedAt: Date?
    var message: String?
}

private struct SessionBatchStatusResponse: Codable {
    var requestedItems: Int
    var updatedItems: Int
    var unchangedItems: Int
    var failedItems: Int
    var results: [SessionBatchStatusItemResult]
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

private func sessionStatusJSONResult<T: Encodable>(
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

private func validateStatus(_ status: String, governanceConfig: AppSessionGovernanceConfig) throws {
    let availableIDs = governanceConfig.statuses.map(\.id)
    guard availableIDs.contains(status) else {
        throw AgentToolError.invalidArguments("Unsupported status '\(status)'. Available status IDs: \(availableIDs.joined(separator: ", ")). Call session_list_statuses to get the current list.")
    }
}

private func displayName(for status: String, governanceConfig: AppSessionGovernanceConfig) -> String {
    governanceConfig.statuses.first { $0.id == status }?.name ?? status
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
