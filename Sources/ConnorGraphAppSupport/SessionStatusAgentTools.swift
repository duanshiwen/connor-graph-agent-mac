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
    public let description = "Set the governance status for the current Connor session or a specific session. Use only when the user asks to mark a session todo, in progress, waiting, needs review, done, blocked, cancelled, or archived."
    public let permission: AgentPermissionCapability = .mutateSessionStatus
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "session_id": .string(description: "Optional session ID. Omit to update the current session."),
        "status": .string(description: "Required status: todo, in_progress, waiting, needs_review, done, blocked, cancelled, or archived."),
        "reason": .string(description: "Optional human-readable reason for the status change.")
    ], required: ["status"])

    private let repository: AppChatSessionRepository

    public init(repository: AppChatSessionRepository) {
        self.repository = repository
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let sessionID = arguments.string("session_id")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? context.sessionID
        guard let statusRaw = arguments.string("status")?.trimmingCharacters(in: .whitespacesAndNewlines), !statusRaw.isEmpty else {
            throw AgentToolError.invalidArguments("status is required")
        }
        guard let status = AgentSessionStatus(rawValue: statusRaw) else {
            throw AgentToolError.invalidArguments("Unsupported status '\(statusRaw)'. Use one of: \(AgentSessionStatus.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let previousStatus = try repository.loadSession(id: sessionID)?.governance.status
        let updated = try repository.setStatus(sessionID: sessionID, status: status)
        if let reason = arguments.string("reason")?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            try repository.appendJournalEvent(
                runID: context.runID,
                sessionID: sessionID,
                kind: .sessionStatusChanged,
                action: "session_status_change_reason",
                message: reason,
                metadata: ["status": status.rawValue]
            )
        }
        return try SessionStatusToolPayload.result(
            session: updated,
            previousStatus: previousStatus,
            context: context,
            toolName: name,
            text: "Updated session \(updated.id) status to \(status.rawValue) (\(status.displayName))."
        )
    }
}

public extension AgentToolRegistry {
    mutating func registerSessionStatusTools(repository: AppChatSessionRepository) {
        register(SessionGetStatusTool(repository: repository))
        register(SessionSetStatusTool(repository: repository))
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
