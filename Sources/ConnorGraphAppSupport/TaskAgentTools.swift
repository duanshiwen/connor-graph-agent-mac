import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct TaskListTool: AgentTool {
    public let name = "tasks_list"
    public let description = "List Connor task definitions with stable pagination. Start at page 1 and follow nextPage with the same page_size until hasNextPage is false for complete results."
    public let permission: AgentPermissionCapability = .readSession
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "page": .integer(description: "1-based page. Defaults to 1."),
        "page_size": .integer(description: "Items per page from 1 through 100. Defaults to 50.")
    ], required: [])
    private let repository: AppTaskManagementRepository

    public init(repository: AppTaskManagementRepository) {
        self.repository = repository
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let page = arguments.int("page") ?? 1
        let pageSize = arguments.int("page_size") ?? 50
        guard page >= 1 else { throw AgentToolError.invalidArguments("page must be at least 1") }
        guard (1...100).contains(pageSize) else { throw AgentToolError.invalidArguments("page_size must be between 1 and 100") }
        let tasks = try repository.loadOrCreateDefault().sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        let totalItems = tasks.count
        let totalPages = totalItems == 0 ? 0 : (totalItems + pageSize - 1) / pageSize
        guard page == 1 || page <= totalPages else { throw AgentToolError.invalidArguments("page \(page) exceeds totalPages \(totalPages)") }
        let start = min((page - 1) * pageSize, totalItems)
        let end = min(start + pageSize, totalItems)
        let items = Array(tasks[start..<end])
        let hasNextPage = end < totalItems
        let payload = TaskListPage(page: page, pageSize: pageSize, returnedItems: items.count, totalItems: totalItems, totalPages: totalPages, hasNextPage: hasNextPage, nextPage: hasNextPage ? page + 1 : nil, tasks: items)
        return try taskJSONResult(payload, context: context, toolName: name, text: "Returned \(items.count) of \(totalItems) task(s) on page \(page).")
    }
}

public struct TaskUpdateScheduledSessionMessageTool: AgentTool {
    public let name = "tasks_update_scheduled_session_message"
    public let description = "Update a user or AI scheduled task that creates a session and sends a message. Pass expected_updated_at from tasks_list to prevent overwriting concurrent changes."
    public let permission: AgentPermissionCapability = .commitGraphWrite
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "task_id": .string(description: "Task ID returned by tasks_list"),
        "expected_updated_at": .string(description: "Optional current updatedAt ISO-8601 value for optimistic concurrency"),
        "name": .string(description: "Optional replacement task name"),
        "runAt": .string(description: "Optional replacement first run time as ISO-8601"),
        "recurrence": .string(description: "Optional once, daily, weekly, or monthly"),
        "timezone": .string(description: "Optional replacement IANA timezone; empty removes it"),
        "message": .string(description: "Optional replacement message"),
        "title": .string(description: "Optional replacement session title; empty removes it")
    ], required: ["task_id"])
    private let repository: AppTaskManagementRepository

    public init(repository: AppTaskManagementRepository) { self.repository = repository }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let taskID = nonEmpty(arguments.string("task_id")) else { throw AgentToolError.invalidArguments("task_id is required") }
        let formatter = ISO8601DateFormatter()
        let expectedUpdatedAt: Date?
        if let raw = nonEmpty(arguments.string("expected_updated_at")) {
            guard let value = formatter.date(from: raw) else { throw AgentToolError.invalidArguments("expected_updated_at must be ISO-8601") }
            expectedUpdatedAt = value
        } else {
            expectedUpdatedAt = nil
        }
        let mutableKeys = ["name", "runAt", "recurrence", "timezone", "message", "title"]
        guard mutableKeys.contains(where: { arguments.values[$0] != nil }) else {
            throw AgentToolError.invalidArguments("at least one editable field is required")
        }
        let updated = try repository.updateScheduledSessionMessageTask(id: taskID, expectedUpdatedAt: expectedUpdatedAt) { task in
            if arguments.values["name"] != nil {
                guard let value = nonEmpty(arguments.string("name")) else { throw AgentToolError.invalidArguments("name must not be empty") }
                task.name = value
            }
            if arguments.values["runAt"] != nil {
                guard let raw = arguments.string("runAt"), let value = formatter.date(from: raw) else { throw AgentToolError.invalidArguments("runAt must be ISO-8601") }
                task.trigger.runAt = value
                task.lifecycle.nextRunAt = value
            }
            if arguments.values["recurrence"] != nil {
                guard let raw = arguments.string("recurrence"), let value = ConnorTaskRecurrence(rawValue: raw), [.once, .daily, .weekly, .monthly].contains(value) else {
                    throw AgentToolError.invalidArguments("recurrence must be once, daily, weekly, or monthly")
                }
                task.trigger.recurrence = value
            }
            if arguments.values["timezone"] != nil { task.trigger.timezoneIdentifier = nonEmpty(arguments.string("timezone")) }
            if arguments.values["message"] != nil {
                guard let value = nonEmpty(arguments.string("message")) else { throw AgentToolError.invalidArguments("message must not be empty") }
                task.target.parameters["message"] = value
            }
            if arguments.values["title"] != nil {
                if let value = nonEmpty(arguments.string("title")) { task.target.parameters["title"] = value }
                else { task.target.parameters.removeValue(forKey: "title") }
            }
        }
        return try result(task: updated, context: context, toolName: name, text: "Updated scheduled task \(taskID)")
    }
}

public struct TaskDeleteTool: AgentTool {
    public let name = "tasks_delete"
    public let description = "Soft-delete a user or AI task. Protected system tasks cannot be deleted."
    public let permission: AgentPermissionCapability = .commitGraphWrite
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "task_id": .string(description: "Task ID returned by tasks_list"),
        "reason": .string(description: "Optional deletion reason")
    ], required: ["task_id"])
    private let repository: AppTaskManagementRepository

    public init(repository: AppTaskManagementRepository) { self.repository = repository }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let taskID = nonEmpty(arguments.string("task_id")) else { throw AgentToolError.invalidArguments("task_id is required") }
        let task = try repository.deleteTask(id: taskID, reason: nonEmpty(arguments.string("reason")))
        return try result(task: task, context: context, toolName: name, text: "Deleted task \(taskID)")
    }
}

public struct TaskCreateScheduledSessionMessageTool: AgentTool {
    public let name = "tasks_create_scheduled_session_message"
    public let description = "Create an AI task that creates a new session at a specific time or on a daily/weekly/monthly schedule, then sends a message to AI. This does not allow arbitrary scripts or external actions."
    public let permission: AgentPermissionCapability = .commitGraphWrite
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
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
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
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
        register(TaskUpdateScheduledSessionMessageTool(repository: repository))
        register(TaskDeleteTool(repository: repository))
    }
}

private struct TaskListPage: Encodable {
    var page: Int
    var pageSize: Int
    var returnedItems: Int
    var totalItems: Int
    var totalPages: Int
    var hasNextPage: Bool
    var nextPage: Int?
    var tasks: [ConnorTaskDefinition]
}

private func taskJSONResult<T: Encodable>(_ payload: T, context: AgentToolExecutionContext, toolName: String, text: String) throws -> AgentToolResult {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = String(decoding: try encoder.encode(payload), as: UTF8.self)
    return AgentToolResult(toolCallID: context.toolCallID, toolName: toolName, contentText: text, contentJSON: json)
}

private func nonEmpty(_ raw: String?) -> String? {
    let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
}

private func result(task: ConnorTaskDefinition, context: AgentToolExecutionContext, toolName: String, text: String) throws -> AgentToolResult {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let json = String(decoding: try encoder.encode(task), as: UTF8.self)
    return AgentToolResult(toolCallID: context.toolCallID, toolName: toolName, contentText: text, contentJSON: json)
}
