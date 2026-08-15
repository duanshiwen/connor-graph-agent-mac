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
    /// 源刷新类任务（RSS/日历）的单次执行超时；超时按失败处理并继续后续任务，
    /// 避免一个卡死的刷新阻塞整轮定时调度（简报等会话任务因此永远排不上）。
    /// 5 秒足够：RSS/日历正常刷新很快，长时间无响应基本就是网络卡死或源不可达。
    public var refreshTaskTimeoutSeconds: TimeInterval
    /// 邮件刷新任务的单次执行超时。IMAP 增量同步（尤其 iCloud 等多文件夹账户）经常超过
    /// 通用源刷新窗口，手动刷新可正常完成但定时任务会被 5 秒超时误判失败；这里给邮件
    /// 单独开更大的时间窗口，超时后同样按失败处理并继续后续任务。
    public var mailRefreshTaskTimeoutSeconds: TimeInterval
    /// 其余任务（新建会话/记忆管道等）的超时；新建会话类任务创建后即返回，通常用不到。
    public var generationTaskTimeoutSeconds: TimeInterval

    public init(
        repository: AppTaskManagementRepository,
        scheduler: TaskSchedulerService = TaskSchedulerService(),
        runner: TaskTargetRunner,
        refreshTaskTimeoutSeconds: TimeInterval = 5,
        mailRefreshTaskTimeoutSeconds: TimeInterval = 120,
        generationTaskTimeoutSeconds: TimeInterval = 600
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.runner = runner
        self.refreshTaskTimeoutSeconds = refreshTaskTimeoutSeconds
        self.mailRefreshTaskTimeoutSeconds = mailRefreshTaskTimeoutSeconds
        self.generationTaskTimeoutSeconds = generationTaskTimeoutSeconds
    }

    private func timeoutSeconds(for task: ConnorTaskDefinition) -> TimeInterval {
        guard task.target.targetKind == "source.runtime" else { return generationTaskTimeoutSeconds }
        if task.target.targetID == "mail" { return mailRefreshTaskTimeoutSeconds }
        return refreshTaskTimeoutSeconds
    }

    /// 带超时执行单个任务。worker 用非结构化 Task 运行，超时后调度器立即返回并继续下一项，
    /// 后台任务即使不响应取消也不会拖住调度轮次。
    private func runTaskWithTimeout(task: ConnorTaskDefinition, runID: String) async throws -> TaskTargetRunResult {
        let worker = Task { try await runner.run(task: task, runID: runID) }
        return try await withThrowingTaskGroup(of: TaskTargetRunResult.self) { group in
            group.addTask { try await worker.value }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds(for: task)))
                throw TaskTargetRunnerError.taskTimedOut
            }
            guard let first = try await group.next() else {
                throw TaskTargetRunnerError.taskTimedOut
            }
            group.cancelAll()
            return first
        }
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
                let result = try await runTaskWithTimeout(task: task, runID: runID)
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
                    message: "定时任务运行已取消。"
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
                message: "上次进程在定时任务完成前已结束。"
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
            outputSummary: "任务已取消",
            errorMessage: message,
            externalRunID: runID
        ))
        return TaskSchedulerRunOutcome(
            taskID: task.id,
            runID: runID,
            succeeded: false,
            summary: "任务已取消",
            errorMessage: message
        )
    }
}
