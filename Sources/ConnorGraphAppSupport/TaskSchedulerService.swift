import Foundation
import ConnorGraphCore

public struct TaskSchedulerService: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    public func dueTasks(_ tasks: [ConnorTaskDefinition], now: Date = Date()) -> [ConnorTaskDefinition] {
        tasks
            .filter { task in
                guard task.trigger.kind == .scheduled else { return false }
                guard task.lifecycle.status == .active || task.lifecycle.status == .failed || task.lifecycle.status == .succeeded else { return false }
                guard task.lifecycle.status != .running && task.lifecycle.status != .stopped && task.lifecycle.status != .deleted else { return false }
                guard let dueDate = effectiveDueDate(for: task, now: now) else { return false }
                return dueDate <= now
            }
            .sorted { lhs, rhs in
                let left = effectiveDueDate(for: lhs, now: now) ?? .distantFuture
                let right = effectiveDueDate(for: rhs, now: now) ?? .distantFuture
                if left != right { return left < right }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    public func computeNextRunAt(task: ConnorTaskDefinition, after date: Date) -> Date? {
        let recurrence = task.trigger.recurrence ?? (task.trigger.intervalSeconds == nil ? .once : .interval)
        switch recurrence {
        case .interval:
            guard let seconds = task.trigger.intervalSeconds else { return nil }
            return date.addingTimeInterval(seconds)
        case .once:
            if let runAt = task.trigger.runAt, runAt > date { return runAt }
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }

    public func markRunStarted(task: ConnorTaskDefinition, now: Date = Date()) -> ConnorTaskDefinition {
        var updated = task
        updated.lifecycle.status = .running
        updated.lifecycle.lastRunAt = now
        updated.lifecycle.lastErrorMessage = nil
        updated.updatedAt = now
        return updated
    }

    public func markRunSucceeded(task: ConnorTaskDefinition, startedAt: Date, finishedAt: Date = Date()) -> ConnorTaskDefinition {
        var updated = task
        let nextRun = computeNextRunAt(task: task, after: finishedAt)
        updated.lifecycle.status = nextRun == nil ? .succeeded : .active
        updated.lifecycle.lastRunAt = startedAt
        updated.lifecycle.lastFinishedAt = finishedAt
        updated.lifecycle.nextRunAt = nextRun
        updated.lifecycle.lastErrorMessage = nil
        updated.updatedAt = finishedAt
        return updated
    }

    public func markRunFailed(task: ConnorTaskDefinition, startedAt: Date, finishedAt: Date = Date(), errorMessage: String) -> ConnorTaskDefinition {
        var updated = task
        updated.lifecycle.status = .failed
        updated.lifecycle.lastRunAt = startedAt
        updated.lifecycle.lastFinishedAt = finishedAt
        updated.lifecycle.failureCount += 1
        updated.lifecycle.lastErrorMessage = errorMessage
        updated.lifecycle.nextRunAt = computeNextRunAt(task: task, after: finishedAt)
        updated.updatedAt = finishedAt
        return updated
    }

    private func effectiveDueDate(for task: ConnorTaskDefinition, now: Date) -> Date? {
        let scheduled = nextDueDate(for: task)
        guard let missedInterval = missedIntervalDueDate(for: task, now: now) else { return scheduled }
        guard let scheduled else { return missedInterval }
        return min(scheduled, missedInterval)
    }

    private func nextDueDate(for task: ConnorTaskDefinition) -> Date? {
        let recurrence = task.trigger.recurrence ?? (task.trigger.intervalSeconds == nil ? .once : .interval)
        if recurrence == .once {
            guard task.lifecycle.lastFinishedAt == nil else { return nil }
            guard task.lifecycle.lastRunAt == nil || task.lifecycle.status == .active else { return nil }
            return task.lifecycle.nextRunAt ?? task.trigger.runAt ?? task.createdAt
        }
        if let nextRunAt = task.lifecycle.nextRunAt { return nextRunAt }
        if let runAt = task.trigger.runAt, task.lifecycle.lastRunAt == nil { return runAt }
        if let lastFinishedAt = task.lifecycle.lastFinishedAt, let next = computeNextRunAt(task: task, after: lastFinishedAt) { return next }
        if let lastRunAt = task.lifecycle.lastRunAt, let next = computeNextRunAt(task: task, after: lastRunAt) { return next }
        return task.createdAt
    }

    private func missedIntervalDueDate(for task: ConnorTaskDefinition, now: Date) -> Date? {
        let recurrence = task.trigger.recurrence ?? (task.trigger.intervalSeconds == nil ? .once : .interval)
        guard recurrence == .interval, let seconds = task.trigger.intervalSeconds else { return nil }
        let anchor = task.lifecycle.lastFinishedAt ?? task.lifecycle.lastRunAt ?? task.trigger.runAt ?? task.createdAt
        let expected = anchor.addingTimeInterval(seconds)
        return expected <= now ? expected : nil
    }
}
