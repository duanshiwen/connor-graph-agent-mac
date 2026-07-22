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
        _ = try recoverInterruptedRuns(now: now)
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
            } catch TaskTargetRunnerError.runCancelled(let detail) {
                outcomes.append(try recordCancellation(
                    task: task,
                    runID: runID,
                    startedAt: startedAt,
                    finishedAt: now,
                    message: detail
                ))
            } catch is CancellationError {
                _ = try recordCancellation(
                    task: task,
                    runID: runID,
                    startedAt: startedAt,
                    finishedAt: now,
                    message: "Scheduled task runner was cancelled"
                )
                throw CancellationError()
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

    @discardableResult
    public func recoverInterruptedRuns(now: Date = Date()) throws -> [TaskSchedulerRunOutcome] {
        let tasks = try repository.loadOrCreateDefault(now: now)
        var outcomes: [TaskSchedulerRunOutcome] = []
        for task in tasks where task.trigger.kind == .scheduled && task.lifecycle.status == .running {
            let history = try repository.loadRunHistory(taskID: task.id, limit: 1_000)
            let terminalRunIDs = Set(history.compactMap { record in
                record.status == .running ? nil : record.externalRunID
            })
            let runningRecord = history.first { record in
                record.status == .running
                    && record.externalRunID.map { !terminalRunIDs.contains($0) } != false
            }
            let runID = runningRecord?.externalRunID ?? "task-run-recovered-\(UUID().uuidString)"
            let startedAt = runningRecord?.startedAt ?? task.lifecycle.lastRunAt ?? now
            outcomes.append(try recordCancellation(
                task: task,
                runID: runID,
                startedAt: startedAt,
                finishedAt: now,
                message: "Previous process ended before the scheduled run reached a terminal state"
            ))
        }
        return outcomes
    }

    private func recordCancellation(
        task: ConnorTaskDefinition,
        runID: String,
        startedAt: Date,
        finishedAt: Date,
        message: String
    ) throws -> TaskSchedulerRunOutcome {
        let cancelled = scheduler.markRunCancelled(
            task: task,
            startedAt: startedAt,
            finishedAt: finishedAt,
            errorMessage: message
        )
        try repository.saveTask(cancelled)
        try repository.appendRunRecord(ConnorTaskRunRecord(
            id: "\(runID)-cancelled",
            taskID: task.id,
            status: .cancelled,
            startedAt: startedAt,
            finishedAt: finishedAt,
            outputSummary: "Task cancelled",
            errorMessage: message,
            externalRunID: runID
        ))
        return TaskSchedulerRunOutcome(
            taskID: task.id,
            runID: runID,
            succeeded: false,
            summary: "Task cancelled",
            errorMessage: message
        )
    }
}
