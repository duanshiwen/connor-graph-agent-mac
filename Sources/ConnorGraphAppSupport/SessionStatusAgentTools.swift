import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct SessionGetStatusTool: AgentTool {
    public let name = "session_get_status"
    public let description = "Read the governance status for the current Connor session or a specific session."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "session_id": .string(description: "Optional session ID. Omit to read the current session status.")
    ], required: [])

    private let repository: AppChatSessionRepository

    public init(repository: AppChatSessionRepository) {
        self.repository = repository
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let sessionID = arguments.string("session_id")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? context.sessionID
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
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "session_id": .string(description: "Optional session ID. Omit to update the current session."),
        "status": .string(description: "Required status id. Must be one of the ids returned by session_list_statuses."),
        "reason": .string(description: "Optional human-readable reason for the status change.")
    ], required: ["status"])

    private let repository: AppChatSessionRepository
    private let governanceConfig: AppSessionGovernanceConfig

    public init(repository: AppChatSessionRepository, governanceConfig: AppSessionGovernanceConfig = .default) {
        self.repository = repository
        self.governanceConfig = governanceConfig
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let sessionID = arguments.string("session_id")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? context.sessionID
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
        register(SessionListStatusesTool(governanceConfig: governanceConfig))
    }
}

public struct SessionListStatusesTool: AgentTool {
    public let name = "session_list_statuses"
    public let description = "List all user-defined session statuses available for this Connor installation. Returns status id and display name."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])

    private let governanceConfig: AppSessionGovernanceConfig

    public init(governanceConfig: AppSessionGovernanceConfig) {
        self.governanceConfig = governanceConfig
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let statuses = governanceConfig.statuses.map { status -> [String: String] in
            ["id": status.id, "name": status.name]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(statuses), as: UTF8.self)
        let names = statuses.map { $0["name"] ?? $0["id"] ?? "" }.joined(separator: ", ")
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Found \(statuses.count) status definition(s): \(names).",
            contentJSON: json
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
