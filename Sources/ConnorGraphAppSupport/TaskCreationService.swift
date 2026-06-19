import Foundation
import ConnorGraphCore

public enum TaskCreationServiceError: Error, Sendable, Equatable, CustomStringConvertible {
    case originNotUserCreatable(ConnorTaskOrigin)
    case emptyName
    case emptyMessage
    case emptyStatus

    public var description: String {
        switch self {
        case .originNotUserCreatable(let origin): "originNotUserCreatable: \(origin.rawValue)"
        case .emptyName: "emptyName"
        case .emptyMessage: "emptyMessage"
        case .emptyStatus: "emptyStatus"
        }
    }
}

public struct TaskCreationService: Sendable {
    public var repository: AppTaskManagementRepository

    public init(repository: AppTaskManagementRepository) {
        self.repository = repository
    }

    @discardableResult
    public func createScheduledSessionMessageTask(
        origin: ConnorTaskOrigin,
        name rawName: String,
        runAt: Date,
        recurrence: ConnorTaskRecurrence,
        timezoneIdentifier: String?,
        message rawMessage: String,
        title rawTitle: String = "",
        createdBySessionID: String? = nil,
        rationale: String? = nil
    ) throws -> ConnorTaskDefinition {
        try validateOrigin(origin)
        let name = try nonEmpty(rawName, error: .emptyName)
        let message = try nonEmpty(rawMessage, error: .emptyMessage)
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let task = ConnorTaskDefinition(
            id: uniqueTaskID(prefix: origin.rawValue, name: name),
            name: name,
            origin: origin,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: runAt, recurrence: recurrence, timezoneIdentifier: timezoneIdentifier),
            target: .createSessionAndSendMessage(message: message, title: title),
            lifecycle: ConnorTaskLifecycle(status: .active, nextRunAt: runAt),
            metadata: ConnorTaskMetadata(createdBySessionID: createdBySessionID, createdByDisplayName: origin == .ai ? "AI" : "User", rationale: rationale, tags: [origin.rawValue, "scheduled-session-message"]),
            createdAt: now,
            updatedAt: now
        )
        try task.validateUserCreatableTemplate()
        try repository.saveTask(task)
        return task
    }

    @discardableResult
    public func createSessionStatusMessageTask(
        origin: ConnorTaskOrigin,
        name rawName: String,
        toStatus rawStatus: String,
        message rawMessage: String,
        sessionID: String? = nil,
        createdBySessionID: String? = nil,
        rationale: String? = nil
    ) throws -> ConnorTaskDefinition {
        try validateOrigin(origin)
        let name = try nonEmpty(rawName, error: .emptyName)
        let status = try nonEmpty(rawStatus, error: .emptyStatus)
        let message = try nonEmpty(rawMessage, error: .emptyMessage)
        let now = Date()
        let task = ConnorTaskDefinition(
            id: uniqueTaskID(prefix: origin.rawValue, name: name),
            name: name,
            origin: origin,
            trigger: ConnorTaskTrigger(kind: .eventTriggered, eventName: ConnorTaskEventName.sessionStatusChanged, eventFilter: ["toStatus": status]),
            target: .sendMessageToSession(sessionID: sessionID ?? "", message: message),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(createdBySessionID: createdBySessionID, createdByDisplayName: origin == .ai ? "AI" : "User", rationale: rationale, tags: [origin.rawValue, "session-status-message"]),
            createdAt: now,
            updatedAt: now
        )
        try task.validateUserCreatableTemplate()
        try repository.saveTask(task)
        return task
    }

    private func validateOrigin(_ origin: ConnorTaskOrigin) throws {
        guard origin == .user || origin == .ai else { throw TaskCreationServiceError.originNotUserCreatable(origin) }
    }

    private func nonEmpty(_ raw: String, error: TaskCreationServiceError) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw error }
        return value
    }

    private func uniqueTaskID(prefix: String, name: String) -> String {
        let slug = name.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let safeSlug = slug.isEmpty ? "task" : slug
        return "\(prefix).\(safeSlug).\(UUID().uuidString.lowercased().prefix(8))"
    }
}
