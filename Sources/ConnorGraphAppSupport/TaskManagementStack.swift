import Foundation
import ConnorGraphCore

public struct TaskManagementStack: Sendable {
    public var repository: AppTaskManagementRepository

    public init(repository: AppTaskManagementRepository) {
        self.repository = repository
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
}
