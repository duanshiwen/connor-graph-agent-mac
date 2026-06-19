import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct TaskListTool: AgentTool {
    public let name = "tasks_list"
    public let description = "List Connor task definitions, including system, user, and AI tasks."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.object(properties: [:], required: [])
    private let repository: AppTaskManagementRepository

    public init(repository: AppTaskManagementRepository) {
        self.repository = repository
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let tasks = try repository.loadOrCreateDefault()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(tasks), as: UTF8.self)
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: "Listed \(tasks.count) tasks", contentJSON: json)
    }
}

public struct TaskCreateScheduledSessionMessageTool: AgentTool {
    public let name = "tasks_create_scheduled_session_message"
    public let description = "Create an AI task that creates a new session at a specific time or on a daily/weekly/monthly schedule, then sends a message to AI. This does not allow arbitrary scripts or external actions."
    public let permission: AgentPermissionCapability = .commitGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "name": .string(description: "Task name"),
        "runAt": .string(description: "First run time as ISO-8601 timestamp"),
        "recurrence": .string(description: "once, daily, weekly, or monthly"),
        "timezone": .string(description: "Optional IANA timezone, e.g. Asia/Shanghai"),
        "message": .string(description: "Message to send to AI in the new session"),
        "title": .string(description: "Optional title for the new session"),
        "rationale": .string(description: "Why this task should exist")
    ], required: ["name", "runAt", "recurrence", "message"])
    private let service: TaskCreationService

    public init(service: TaskCreationService) {
        self.service = service
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let name = arguments.string("name") else { throw AgentToolError.invalidArguments("name is required") }
        guard let runAtRaw = arguments.string("runAt"), let runAt = ISO8601DateFormatter().date(from: runAtRaw) else { throw AgentToolError.invalidArguments("runAt must be ISO-8601") }
        guard let recurrenceRaw = arguments.string("recurrence"), let recurrence = ConnorTaskRecurrence(rawValue: recurrenceRaw) else { throw AgentToolError.invalidArguments("recurrence must be once, daily, weekly, or monthly") }
        let task = try service.createScheduledSessionMessageTask(
            origin: .ai,
            name: name,
            runAt: runAt,
            recurrence: recurrence,
            timezoneIdentifier: arguments.string("timezone"),
            message: arguments.string("message") ?? "",
            title: arguments.string("title") ?? "",
            createdBySessionID: context.sessionID,
            rationale: arguments.string("rationale")
        )
        return try result(task: task, context: context, toolName: self.name, text: "Created scheduled AI task \(task.id)")
    }
}

public struct TaskCreateSessionStatusMessageTool: AgentTool {
    public let name = "tasks_create_session_status_message"
    public let description = "Create an AI task that runs when a session changes to a specific status, then sends a message to AI in that session. This is the only event-triggered task template available."
    public let permission: AgentPermissionCapability = .commitGraphWrite
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "name": .string(description: "Task name"),
        "toStatus": .string(description: "Target session status ID, e.g. done"),
        "message": .string(description: "Message to send to AI when the status is reached"),
        "sessionID": .string(description: "Optional fixed session ID; omit to use the event session"),
        "rationale": .string(description: "Why this task should exist")
    ], required: ["name", "toStatus", "message"])
    private let service: TaskCreationService

    public init(service: TaskCreationService) {
        self.service = service
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let name = arguments.string("name") else { throw AgentToolError.invalidArguments("name is required") }
        guard let toStatus = arguments.string("toStatus") else { throw AgentToolError.invalidArguments("toStatus is required") }
        let task = try service.createSessionStatusMessageTask(
            origin: .ai,
            name: name,
            toStatus: toStatus,
            message: arguments.string("message") ?? "",
            sessionID: arguments.string("sessionID"),
            createdBySessionID: context.sessionID,
            rationale: arguments.string("rationale")
        )
        return try result(task: task, context: context, toolName: self.name, text: "Created session-status AI task \(task.id)")
    }
}

public extension AgentToolRegistry {
    mutating func registerTaskManagementTools(repository: AppTaskManagementRepository) {
        let service = TaskCreationService(repository: repository)
        register(TaskListTool(repository: repository))
        register(TaskCreateScheduledSessionMessageTool(service: service))
        register(TaskCreateSessionStatusMessageTool(service: service))
    }
}

private func result(task: ConnorTaskDefinition, context: AgentToolExecutionContext, toolName: String, text: String) throws -> AgentToolResult {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = String(decoding: try encoder.encode(task), as: UTF8.self)
    return AgentToolResult(toolCallID: context.toolCallID, toolName: toolName, contentText: text, contentJSON: json)
}
