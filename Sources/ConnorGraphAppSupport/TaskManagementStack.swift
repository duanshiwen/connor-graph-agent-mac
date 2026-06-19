import Foundation
import ConnorGraphCore

public struct TaskManagementStack: Sendable {
    public var repository: AppTaskManagementRepository
    public var sessionRepository: AppChatSessionRepository?
    public var sessionTaskAdapter: SessionBackgroundTaskManagementAdapter

    public init(
        repository: AppTaskManagementRepository,
        sessionRepository: AppChatSessionRepository? = nil,
        sessionTaskAdapter: SessionBackgroundTaskManagementAdapter = SessionBackgroundTaskManagementAdapter()
    ) {
        self.repository = repository
        self.sessionRepository = sessionRepository
        self.sessionTaskAdapter = sessionTaskAdapter
    }

    public func listTasks(includeDeleted: Bool = false) throws -> [ConnorTaskDefinition] {
        try repository.loadTasks(includeDeleted: includeDeleted)
    }

    public func task(id: String) throws -> ConnorTaskDefinition? {
        try repository.loadTask(id: id)
    }

    public func saveTask(_ task: ConnorTaskDefinition) throws {
        try repository.saveTask(task)
    }

    @discardableResult
    public func stopTask(id: String, reason: String? = nil) throws -> ConnorTaskDefinition {
        try repository.stopTask(id: id, reason: reason)
    }

    @discardableResult
    public func restoreTask(id: String) throws -> ConnorTaskDefinition {
        try repository.restoreTask(id: id)
    }

    @discardableResult
    public func deleteTask(id: String, reason: String? = nil) throws -> ConnorTaskDefinition {
        try repository.deleteTask(id: id, reason: reason)
    }

    public func recordRun(_ record: ConnorTaskRunRecord) throws {
        try repository.appendRunRecord(record)
        _ = try repository.updateLifecycleFromRunRecord(record)
    }

    public func runHistory(taskID: String? = nil, limit: Int = 50) throws -> [ConnorTaskRunRecord] {
        try repository.loadRunHistory(taskID: taskID, limit: limit)
    }

    public func listSessionTasks(sessionID: String, limit: Int? = nil) throws -> [ConnorTaskDefinition] {
        guard let sessionRepository else { return [] }
        return try sessionRepository
            .loadBackgroundTasks(sessionID: sessionID, limit: limit)
            .map(sessionTaskAdapter.taskDefinition(from:))
    }

    public func recoverableSessionTasks(sessionID: String) throws -> [ConnorTaskDefinition] {
        guard let sessionRepository else { return [] }
        let tasks = try sessionRepository.loadBackgroundTasks(sessionID: sessionID)
        return sessionTaskAdapter.recoverableTasks(from: tasks, sessionID: sessionID)
    }

    @discardableResult
    public func stopSessionTask(sessionID: String, taskID: String, reason: String? = nil) throws -> ConnorTaskDefinition {
        guard let sessionRepository else { throw AppTaskManagementError.taskNotFound(taskID) }
        let backgroundTaskID = sessionTaskAdapter.originalBackgroundTaskID(from: taskID, sessionID: sessionID) ?? taskID
        try sessionRepository.updateBackgroundTask(
            sessionID: sessionID,
            taskID: backgroundTaskID,
            status: .interrupted,
            detail: "Interrupted by Task Management Stack",
            errorMessage: reason
        )
        guard let task = try sessionRepository.loadBackgroundTasks(sessionID: sessionID).first(where: { $0.id == backgroundTaskID }) else {
            throw AppTaskManagementError.taskNotFound(taskID)
        }
        return sessionTaskAdapter.taskDefinition(from: task)
    }

    @discardableResult
    public func restoreSessionTask(sessionID: String, taskID: String) throws -> ConnorTaskDefinition {
        guard let sessionRepository else { throw AppTaskManagementError.taskNotFound(taskID) }
        let backgroundTaskID = sessionTaskAdapter.originalBackgroundTaskID(from: taskID, sessionID: sessionID) ?? taskID
        try sessionRepository.updateBackgroundTask(
            sessionID: sessionID,
            taskID: backgroundTaskID,
            status: .queued,
            detail: "Queued for runtime recovery",
            errorMessage: nil
        )
        guard let task = try sessionRepository.loadBackgroundTasks(sessionID: sessionID).first(where: { $0.id == backgroundTaskID }) else {
            throw AppTaskManagementError.taskNotFound(taskID)
        }
        return sessionTaskAdapter.taskDefinition(from: task)
    }
}
