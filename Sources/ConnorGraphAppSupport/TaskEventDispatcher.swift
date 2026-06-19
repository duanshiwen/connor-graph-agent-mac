import Foundation
import ConnorGraphCore

public struct TaskEventDispatcher: Sendable {
    public var repository: AppTaskManagementRepository
    public var runner: TaskTargetRunner

    public init(repository: AppTaskManagementRepository, runner: TaskTargetRunner) {
        self.repository = repository
        self.runner = runner
    }

    public func dispatchSessionStatusChanged(sessionID: String, fromStatus: String?, toStatus: String, now: Date = Date()) async throws -> [TaskSchedulerRunOutcome] {
        let payload = [
            "sessionID": sessionID,
            "fromStatus": fromStatus ?? "",
            "toStatus": toStatus
        ]
        return try await dispatch(eventName: ConnorTaskEventName.sessionStatusChanged, payload: payload, now: now)
    }

    public func dispatch(eventName: String, payload: [String: String], now: Date = Date()) async throws -> [TaskSchedulerRunOutcome] {
        let tasks = try repository.loadOrCreateDefault(now: now)
        let matching = tasks.filter { task in
            guard task.trigger.kind == .eventTriggered else { return false }
            guard task.lifecycle.status == .active || task.lifecycle.status == .failed || task.lifecycle.status == .succeeded else { return false }
            guard task.trigger.eventName == eventName else { return false }
            return task.trigger.eventFilter.allSatisfy { key, value in
                payload[key] == value
            }
        }
        var outcomes: [TaskSchedulerRunOutcome] = []
        for task in matching {
            let runID = "task-event-run-\(UUID().uuidString)"
            try repository.saveTask(mark(task: task, status: .running, now: now, errorMessage: nil))
            try repository.appendRunRecord(ConnorTaskRunRecord(id: "\(runID)-running", taskID: task.id, status: .running, startedAt: now, outputSummary: "Event task started", externalRunID: runID))
            do {
                let result = try await runner.run(task: task, runID: runID, eventPayload: payload)
                var completed = task
                completed.lifecycle.status = .succeeded
                completed.lifecycle.lastRunAt = now
                completed.lifecycle.lastFinishedAt = now
                completed.lifecycle.lastErrorMessage = nil
                completed.updatedAt = now
                try repository.saveTask(completed)
                try repository.appendRunRecord(ConnorTaskRunRecord(id: "\(runID)-succeeded", taskID: task.id, status: .succeeded, startedAt: now, finishedAt: now, outputSummary: result.summary, externalRunID: runID))
                outcomes.append(TaskSchedulerRunOutcome(taskID: task.id, runID: runID, succeeded: true, summary: result.summary))
            } catch {
                let message = String(describing: error)
                var failed = task
                failed.lifecycle.status = .failed
                failed.lifecycle.lastRunAt = now
                failed.lifecycle.lastFinishedAt = now
                failed.lifecycle.failureCount += 1
                failed.lifecycle.lastErrorMessage = message
                failed.updatedAt = now
                try repository.saveTask(failed)
                try repository.appendRunRecord(ConnorTaskRunRecord(id: "\(runID)-failed", taskID: task.id, status: .failed, startedAt: now, finishedAt: now, outputSummary: "Event task failed", errorMessage: message, externalRunID: runID))
                outcomes.append(TaskSchedulerRunOutcome(taskID: task.id, runID: runID, succeeded: false, summary: "Event task failed", errorMessage: message))
            }
        }
        return outcomes
    }

    private func mark(task: ConnorTaskDefinition, status: ConnorTaskLifecycleStatus, now: Date, errorMessage: String?) -> ConnorTaskDefinition {
        var copy = task
        copy.lifecycle.status = status
        copy.lifecycle.lastRunAt = now
        copy.lifecycle.lastErrorMessage = errorMessage
        copy.updatedAt = now
        return copy
    }
}
