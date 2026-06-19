import Foundation
import ConnorGraphCore

public struct TaskSchedulerRunOutcome: Sendable, Equatable {
    public var taskID: String
    public var runID: String
    public var succeeded: Bool
    public var summary: String
    public var errorMessage: String?

    public init(taskID: String, runID: String, succeeded: Bool, summary: String, errorMessage: String? = nil) {
        self.taskID = taskID
        self.runID = runID
        self.succeeded = succeeded
        self.summary = summary
        self.errorMessage = errorMessage
    }
}

public struct TaskSchedulerRunnerService: Sendable {
    public var repository: AppTaskManagementRepository
    public var scheduler: TaskSchedulerService
    public var runner: TaskTargetRunner

    public init(repository: AppTaskManagementRepository, scheduler: TaskSchedulerService = TaskSchedulerService(), runner: TaskTargetRunner) {
        self.repository = repository
        self.scheduler = scheduler
        self.runner = runner
    }

    public func runDueTasks(now: Date = Date()) async throws -> [TaskSchedulerRunOutcome] {
        let tasks = try repository.loadOrCreateDefault(now: now)
        let due = scheduler.dueTasks(tasks, now: now)
        var outcomes: [TaskSchedulerRunOutcome] = []
        for task in due {
            let runID = "task-run-\(UUID().uuidString)"
            let startedAt = now
            let started = scheduler.markRunStarted(task: task, now: startedAt)
            try repository.saveTask(started)
            try repository.appendRunRecord(ConnorTaskRunRecord(id: "\(runID)-running", taskID: task.id, status: .running, startedAt: startedAt, outputSummary: "Task started", externalRunID: runID))
            do {
                let result = try await runner.run(task: task, runID: runID)
                let finishedAt = now
                let succeeded = scheduler.markRunSucceeded(task: task, startedAt: startedAt, finishedAt: finishedAt)
                try repository.saveTask(succeeded)
                try repository.appendRunRecord(ConnorTaskRunRecord(id: "\(runID)-succeeded", taskID: task.id, status: .succeeded, startedAt: startedAt, finishedAt: finishedAt, outputSummary: result.summary, externalRunID: runID))
                outcomes.append(TaskSchedulerRunOutcome(taskID: task.id, runID: runID, succeeded: true, summary: result.summary))
            } catch {
                let finishedAt = now
                let message = String(describing: error)
                let failed = scheduler.markRunFailed(task: task, startedAt: startedAt, finishedAt: finishedAt, errorMessage: message)
                try repository.saveTask(failed)
                try repository.appendRunRecord(ConnorTaskRunRecord(id: "\(runID)-failed", taskID: task.id, status: .failed, startedAt: startedAt, finishedAt: finishedAt, outputSummary: "Task failed", errorMessage: message, externalRunID: runID))
                outcomes.append(TaskSchedulerRunOutcome(taskID: task.id, runID: runID, succeeded: false, summary: "Task failed", errorMessage: message))
            }
        }
        return outcomes
    }
}
