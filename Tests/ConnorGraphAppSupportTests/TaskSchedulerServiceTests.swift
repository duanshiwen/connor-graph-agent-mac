import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Scheduler Service Tests")
struct TaskSchedulerServiceTests {
    @Test func intervalTaskBecomesDueAndSkipsRunningTasks() throws {
        let scheduler = TaskSchedulerService()
        let now = Date(timeIntervalSince1970: 1_000)
        var task = try #require(ConnorTaskDefinition.systemDefaults(now: Date(timeIntervalSince1970: 0)).first { $0.id == "system.mail.check-every-10-minutes" })
        task.lifecycle.status = .active
        task.lifecycle.lastFinishedAt = Date(timeIntervalSince1970: 300)

        #expect(scheduler.dueTasks([task], now: now).map(\.id) == [task.id])

        task.lifecycle.status = .running
        #expect(scheduler.dueTasks([task], now: now).isEmpty)
    }

    @Test func intervalTaskMissedRoundIsDueImmediatelyEvenWhenStoredNextRunIsStaleFuture() throws {
        let scheduler = TaskSchedulerService()
        let now = Date(timeIntervalSince1970: 1_000)
        let lastFinishedAt = Date(timeIntervalSince1970: 100)
        var interval = ConnorTaskDefinition(
            id: "system.rss.source.feed-a.refresh",
            name: "RSS：Feed A",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "rss", operationName: "refresh", parameters: ["sourceInstanceID": "feed-a"]),
            lifecycle: ConnorTaskLifecycle(
                status: .active,
                nextRunAt: Date(timeIntervalSince1970: 5_000),
                lastFinishedAt: lastFinishedAt
            ),
            metadata: .protectedSystem
        )

        #expect(scheduler.dueTasks([interval], now: now).map(\.id) == [interval.id])

        interval.trigger.recurrence = .daily
        #expect(scheduler.dueTasks([interval], now: now).isEmpty)
    }

    @Test func onceTasksDoNotBecomeDueAgainAfterSuccessOrFailure() throws {
        let scheduler = TaskSchedulerService()
        let startedAt = Date(timeIntervalSince1970: 100)
        let finishedAt = Date(timeIntervalSince1970: 120)
        let now = Date(timeIntervalSince1970: 1_000)
        let base = ConnorTaskDefinition(
            id: "media.transcription.media-job-example",
            name: "Media",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: startedAt, recurrence: .once),
            target: .mediaTranscriptionRun(jobID: "media-job-example", ownerSessionID: "session-1"),
            lifecycle: ConnorTaskLifecycle(status: .active, nextRunAt: startedAt),
            metadata: ConnorTaskMetadata(ownerSessionID: "session-1")
        )

        let active = scheduler.dueTasks([base], now: now)
        #expect(active.map(\.id) == [base.id])

        let running = scheduler.markRunStarted(task: base, now: startedAt)
        let succeeded = scheduler.markRunSucceeded(task: running, startedAt: startedAt, finishedAt: finishedAt)
        #expect(scheduler.dueTasks([succeeded], now: now).isEmpty)

        let failed = scheduler.markRunFailed(task: running, startedAt: startedAt, finishedAt: finishedAt, errorMessage: "boom")
        #expect(scheduler.dueTasks([failed], now: now).isEmpty)
    }

    @Test func dailyTaskMissedWhileAppWasClosedIsDueAndKeepsOriginalScheduleAfterRun() throws {
        let scheduler = TaskSchedulerService(calendar: Calendar(identifier: .gregorian))
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(3 * 24 * 60 * 60 + 3_600)
        let expectedNextRun = start.addingTimeInterval(4 * 24 * 60 * 60)
        let task = ConnorTaskDefinition(
            id: "user.daily",
            name: "Daily",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: start, recurrence: .daily),
            target: .createSessionAndSendMessage(message: "Daily"),
            lifecycle: ConnorTaskLifecycle(
                status: .active,
                nextRunAt: start.addingTimeInterval(10 * 24 * 60 * 60),
                lastFinishedAt: start
            ),
            metadata: ConnorTaskMetadata()
        )

        #expect(scheduler.dueTasks([task], now: now).map(\.id) == [task.id])

        let running = scheduler.markRunStarted(task: task, now: now)
        let succeeded = scheduler.markRunSucceeded(task: running, startedAt: now, finishedAt: now)
        #expect(succeeded.lifecycle.status == .active)
        #expect(succeeded.lifecycle.nextRunAt == expectedNextRun)
    }

    @Test func calendarRecurringTasksComputeNextRunFromOriginalAnchor() throws {
        let scheduler = TaskSchedulerService(calendar: Calendar(identifier: .gregorian))
        let start = Date(timeIntervalSince1970: 1_000)
        let afterMissedDailyRun = start.addingTimeInterval(2 * 24 * 60 * 60 + 60)
        let afterMissedWeeklyRun = start.addingTimeInterval(15 * 24 * 60 * 60)
        let afterMissedMonthlyRun = try #require(Calendar(identifier: .gregorian).date(byAdding: .day, value: 45, to: start))
        let daily = ConnorTaskDefinition(
            id: "user.daily",
            name: "Daily",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: start, recurrence: .daily),
            target: .createSessionAndSendMessage(message: "Daily"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata()
        )
        let weekly = ConnorTaskDefinition(
            id: "user.weekly",
            name: "Weekly",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: start, recurrence: .weekly),
            target: .createSessionAndSendMessage(message: "Weekly"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata()
        )
        let monthly = ConnorTaskDefinition(
            id: "user.monthly",
            name: "Monthly",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: start, recurrence: .monthly),
            target: .createSessionAndSendMessage(message: "Monthly"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata()
        )

        #expect(scheduler.computeNextRunAt(task: daily, after: afterMissedDailyRun) == start.addingTimeInterval(3 * 24 * 60 * 60))
        #expect(scheduler.computeNextRunAt(task: weekly, after: afterMissedWeeklyRun) == start.addingTimeInterval(21 * 24 * 60 * 60))
        #expect(scheduler.computeNextRunAt(task: monthly, after: afterMissedMonthlyRun) == Calendar(identifier: .gregorian).date(byAdding: .month, value: 2, to: start))
    }

    @Test func schedulerComputesNextRunForIntervalDailyWeeklyAndMonthly() throws {
        let scheduler = TaskSchedulerService(calendar: Calendar(identifier: .gregorian))
        let start = Date(timeIntervalSince1970: 1_000)
        let interval = ConnorTaskDefinition(
            id: "system.rss.source.feed-a.refresh",
            name: "RSS：Feed A",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 1_800, recurrence: .interval),
            target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "rss", operationName: "refresh", parameters: ["sourceInstanceID": "feed-a"]),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem
        )
        let daily = ConnorTaskDefinition(
            id: "user.daily",
            name: "Daily",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: start, recurrence: .daily),
            target: .createSessionAndSendMessage(message: "Daily"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata()
        )
        let weekly = ConnorTaskDefinition(
            id: "user.weekly",
            name: "Weekly",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: start, recurrence: .weekly),
            target: .createSessionAndSendMessage(message: "Weekly"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata()
        )
        let monthly = ConnorTaskDefinition(
            id: "user.monthly",
            name: "Monthly",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: start, recurrence: .monthly),
            target: .createSessionAndSendMessage(message: "Monthly"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata()
        )

        #expect(scheduler.computeNextRunAt(task: interval, after: start) == start.addingTimeInterval(1_800))
        #expect(scheduler.computeNextRunAt(task: daily, after: start) == Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: start))
        #expect(scheduler.computeNextRunAt(task: weekly, after: start) == Calendar(identifier: .gregorian).date(byAdding: .day, value: 7, to: start))
        #expect(scheduler.computeNextRunAt(task: monthly, after: start) == Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: start))
    }

    @Test func schedulerUpdatesRunLifecycleForSuccessAndFailure() throws {
        let scheduler = TaskSchedulerService()
        let startedAt = Date(timeIntervalSince1970: 100)
        let finishedAt = Date(timeIntervalSince1970: 110)
        var task = ConnorTaskDefinition(
            id: "user.once",
            name: "Once",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: startedAt, recurrence: .once),
            target: .createSessionAndSendMessage(message: "Once"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata()
        )

        task = scheduler.markRunStarted(task: task, now: startedAt)
        #expect(task.lifecycle.status == .running)
        #expect(task.lifecycle.lastRunAt == startedAt)

        let succeeded = scheduler.markRunSucceeded(task: task, startedAt: startedAt, finishedAt: finishedAt)
        #expect(succeeded.lifecycle.status == .succeeded)
        #expect(succeeded.lifecycle.lastFinishedAt == finishedAt)
        #expect(succeeded.lifecycle.nextRunAt == nil)

        let failed = scheduler.markRunFailed(task: task, startedAt: startedAt, finishedAt: finishedAt, errorMessage: "boom")
        #expect(failed.lifecycle.status == .failed)
        #expect(failed.lifecycle.failureCount == 1)
        #expect(failed.lifecycle.lastErrorMessage == "boom")
    }
}
