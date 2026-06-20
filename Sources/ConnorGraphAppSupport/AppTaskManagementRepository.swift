import Foundation
import ConnorGraphCore

public enum AppTaskManagementError: Error, Equatable, CustomStringConvertible {
    case taskNotFound(String)
    case cannotDeleteProtectedSystemTask(String)
    case invalidTaskID(String)

    public var description: String {
        switch self {
        case .taskNotFound(let id): "taskNotFound: \(id)"
        case .cannotDeleteProtectedSystemTask(let id): "cannotDeleteProtectedSystemTask: \(id)"
        case .invalidTaskID(let id): "invalidTaskID: \(id)"
        }
    }
}

public struct AppTaskManagementRepository: Sendable {
    public var storagePaths: AppStoragePaths

    public init(storagePaths: AppStoragePaths) {
        self.storagePaths = storagePaths
    }

    public var taskDefinitionsURL: URL { storagePaths.tasksDirectory.appendingPathComponent("task-definitions.json") }
    public var taskRunHistoryURL: URL { storagePaths.tasksDirectory.appendingPathComponent("task-run-history.jsonl") }
    public var taskEventLogURL: URL { storagePaths.tasksDirectory.appendingPathComponent("task-event-log.jsonl") }
    public var taskDeletionLogURL: URL { storagePaths.tasksDirectory.appendingPathComponent("task-deletion-log.jsonl") }

    public func loadOrCreateDefault(now: Date = Date()) throws -> [ConnorTaskDefinition] {
        try storagePaths.ensureDirectoryHierarchy()
        if FileManager.default.fileExists(atPath: taskDefinitionsURL.path) {
            return try ensureSystemDefaultTasks(now: now)
        }
        let tasks = ConnorTaskDefinition.systemDefaults(now: now)
        try write(tasks: tasks)
        return tasks
    }

    public func ensureSystemDefaultTasks(now: Date = Date()) throws -> [ConnorTaskDefinition] {
        var tasks = try loadTasks(includeDeleted: true)
        let defaults = ConnorTaskDefinition.systemDefaults(now: now)
        var changed = false
        for defaultTask in defaults {
            if let index = tasks.firstIndex(where: { $0.id == defaultTask.id }) {
                var existing = tasks[index]
                let previousTarget = existing.target
                existing.origin = .system
                existing.trigger.kind = .scheduled
                existing.trigger.intervalSeconds = defaultTask.trigger.intervalSeconds
                existing.trigger.recurrence = .interval
                existing.target = defaultTask.target
                existing.metadata.isProtectedSystemTask = true
                existing.metadata.scope = .global
                existing.metadata.isRecoverable = false
                existing.metadata.recoveryPolicy = .none
                existing.updatedAt = previousTarget == existing.target ? existing.updatedAt : now
                if existing != tasks[index] {
                    tasks[index] = existing
                    changed = true
                }
            } else {
                tasks.append(defaultTask)
                changed = true
                try appendEventLine(["event": "task.system-default.backfilled", "taskID": defaultTask.id])
            }
        }
        if changed { try write(tasks: tasks) }
        return try loadTasks(includeDeleted: true)
    }

    public func loadTasks(includeDeleted: Bool = false) throws -> [ConnorTaskDefinition] {
        guard FileManager.default.fileExists(atPath: taskDefinitionsURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let tasks = try decoder.decode([ConnorTaskDefinition].self, from: try Data(contentsOf: taskDefinitionsURL))
        let filtered = includeDeleted ? tasks : tasks.filter { $0.lifecycle.status != .deleted }
        return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func loadTask(id: String) throws -> ConnorTaskDefinition? {
        try loadTasks(includeDeleted: true).first { $0.id == id }
    }

    public func saveTask(_ task: ConnorTaskDefinition) throws {
        try validateID(task.id)
        var tasks = try loadTasks(includeDeleted: true)
        var normalized = task
        normalized.updatedAt = Date()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = normalized
        } else {
            tasks.append(normalized)
        }
        try write(tasks: tasks)
    }

    public func purgeTaskDefinition(id: String, reason: String? = nil) throws {
        try validateID(id)
        var tasks = try loadTasks(includeDeleted: true)
        let originalCount = tasks.count
        tasks.removeAll { $0.id == id }
        guard tasks.count != originalCount else { return }
        try write(tasks: tasks)
        try appendEventLine(["event": "task.definition.purged", "taskID": id, "reason": reason ?? ""])
    }

    @discardableResult
    public func stopTask(id: String, reason: String? = nil) throws -> ConnorTaskDefinition {
        try mutateTask(id: id) { task in
            task.lifecycle.status = .stopped
            task.lifecycle.lastErrorMessage = reason
        }
    }

    @discardableResult
    public func restoreTask(id: String) throws -> ConnorTaskDefinition {
        try mutateTask(id: id) { task in
            task.lifecycle.status = .active
            task.lifecycle.lastErrorMessage = nil
        }
    }

    @discardableResult
    public func deleteTask(id: String, reason: String? = nil) throws -> ConnorTaskDefinition {
        guard var task = try loadTask(id: id) else { throw AppTaskManagementError.taskNotFound(id) }
        if task.origin == .system && task.metadata.isProtectedSystemTask {
            throw AppTaskManagementError.cannotDeleteProtectedSystemTask(id)
        }
        task.lifecycle.status = .deleted
        task.lifecycle.lastErrorMessage = reason
        task.updatedAt = Date()
        try saveTask(task)
        try appendEventLine(["event": "task.deleted", "taskID": id, "reason": reason ?? ""])
        return task
    }

    public func appendRunRecord(_ record: ConnorTaskRunRecord) throws {
        try FileManager.default.createDirectory(at: storagePaths.tasksDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var line = String(decoding: try encoder.encode(record), as: UTF8.self)
        line.append("\n")
        if FileManager.default.fileExists(atPath: taskRunHistoryURL.path) {
            let handle = try FileHandle(forWritingTo: taskRunHistoryURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try line.write(to: taskRunHistoryURL, atomically: true, encoding: .utf8)
        }
    }

    public func loadRunHistory(taskID: String? = nil, limit: Int = 50) throws -> [ConnorTaskRunRecord] {
        guard FileManager.default.fileExists(atPath: taskRunHistoryURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let text = try String(contentsOf: taskRunHistoryURL, encoding: .utf8)
        let records = text.split(separator: "\n").compactMap { line -> ConnorTaskRunRecord? in
            try? decoder.decode(ConnorTaskRunRecord.self, from: Data(line.utf8))
        }
        let filtered = taskID.map { id in records.filter { $0.taskID == id } } ?? records
        return Array(filtered.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
            return (lhs.finishedAt ?? .distantPast) > (rhs.finishedAt ?? .distantPast)
        }.prefix(limit))
    }

    @discardableResult
    public func updateLifecycleFromRunRecord(_ record: ConnorTaskRunRecord) throws -> ConnorTaskDefinition? {
        guard var task = try loadTask(id: record.taskID) else { return nil }
        switch record.status {
        case .queued:
            break
        case .running:
            task.lifecycle.status = .running
            task.lifecycle.lastRunAt = record.startedAt
        case .succeeded:
            task.lifecycle.status = .succeeded
            task.lifecycle.lastRunAt = record.startedAt
            task.lifecycle.lastFinishedAt = record.finishedAt
            task.lifecycle.lastErrorMessage = nil
        case .failed:
            task.lifecycle.status = .failed
            task.lifecycle.lastRunAt = record.startedAt
            task.lifecycle.lastFinishedAt = record.finishedAt
            task.lifecycle.failureCount += 1
            task.lifecycle.lastErrorMessage = record.errorMessage
        case .cancelled:
            task.lifecycle.status = .stopped
            task.lifecycle.lastRunAt = record.startedAt
            task.lifecycle.lastFinishedAt = record.finishedAt
            task.lifecycle.lastErrorMessage = record.errorMessage
        }
        try saveTask(task)
        return task
    }

    private func mutateTask(id: String, mutation: (inout ConnorTaskDefinition) -> Void) throws -> ConnorTaskDefinition {
        guard var task = try loadTask(id: id) else { throw AppTaskManagementError.taskNotFound(id) }
        mutation(&task)
        task.updatedAt = Date()
        try saveTask(task)
        try appendEventLine(["event": "task.lifecycle.changed", "taskID": id, "status": task.lifecycle.status.rawValue])
        return task
    }

    private func write(tasks: [ConnorTaskDefinition]) throws {
        try FileManager.default.createDirectory(at: storagePaths.tasksDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sorted = tasks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try encoder.encode(sorted).write(to: taskDefinitionsURL, options: .atomic)
    }

    private func appendEventLine(_ payload: [String: String]) throws {
        try FileManager.default.createDirectory(at: storagePaths.tasksDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var line = String(decoding: try encoder.encode(payload), as: UTF8.self)
        line.append("\n")
        if FileManager.default.fileExists(atPath: taskEventLogURL.path) {
            let handle = try FileHandle(forWritingTo: taskEventLogURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try line.write(to: taskEventLogURL, atomically: true, encoding: .utf8)
        }
    }

    private func validateID(_ id: String) throws {
        let pattern = #"^[a-z0-9][a-z0-9.-]{1,126}[a-z0-9]$"#
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            throw AppTaskManagementError.invalidTaskID(id)
        }
    }
}
