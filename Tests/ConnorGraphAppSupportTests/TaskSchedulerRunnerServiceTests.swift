import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Scheduler Runner Service Tests")
struct TaskSchedulerRunnerServiceTests {
    @Test func serviceRunsDueTasksAndRecordsHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        try saveSystemDefaultsAsNotDue(repository: repository, now: Date(timeIntervalSince1970: 2_000))
        var task = makeRSSRefreshTask(sourceID: "feed-a", intervalSeconds: 1_800, now: Date(timeIntervalSince1970: 0))
        task.lifecycle.lastFinishedAt = Date(timeIntervalSince1970: 0)
        try repository.saveTask(task)
        let calls = RefreshCallCounter()
        let runner = TaskTargetRunner(mailRefresher: { _ in "mail" }, calendarRefresher: { _ in "calendar" }, rssRefresher: calls.refresh, sessionMessenger: { _ in "session" })
        let service = TaskSchedulerRunnerService(repository: repository, scheduler: TaskSchedulerService(), runner: runner)

        let outcomes = try await service.runDueTasks(now: Date(timeIntervalSince1970: 2_000))
        let reloaded = try #require(try repository.loadTask(id: task.id))
        let history = try repository.loadRunHistory(taskID: task.id, limit: 10)

        #expect(outcomes.map(\.taskID) == [task.id])
        #expect(await calls.count == 1)
        #expect(reloaded.lifecycle.status == .active)
        #expect(reloaded.lifecycle.nextRunAt == Date(timeIntervalSince1970: 3_800))
        #expect(history.map(\.status) == [.succeeded, .running])
    }

    @Test func serviceRecordsFailuresWithoutThrowingAwayOtherDueTasks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let now = Date(timeIntervalSince1970: 0)
        try saveSystemDefaultsAsNotDue(repository: repository, now: Date(timeIntervalSince1970: 2_000))
        var tasks: [ConnorTaskDefinition] = []
        var explicitMailTask = ConnorTaskDefinition(
            id: "system.mail.check-every-10-minutes",
            name: "检查邮件",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: .sourceRuntimeRefresh(sourceID: "mail"),
            lifecycle: ConnorTaskLifecycle(status: .active, lastFinishedAt: now),
            metadata: .protectedSystem,
            createdAt: now,
            updatedAt: now
        )
        explicitMailTask.lifecycle.lastFinishedAt = now
        tasks.append(explicitMailTask)
        var explicitCalendarTask = ConnorTaskDefinition(
            id: "system.calendar.account.calendar-account-a.refresh",
            name: "检查日历：Calendar A",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "calendar", operationName: "refresh", parameters: ["sourceInstanceID": "calendar-account-a"]),
            lifecycle: ConnorTaskLifecycle(status: .active, lastFinishedAt: now),
            metadata: .protectedSystem,
            createdAt: now,
            updatedAt: now
        )
        explicitCalendarTask.lifecycle.lastFinishedAt = now
        tasks.append(explicitCalendarTask)
        for task in tasks { try repository.saveTask(task) }
        let runner = TaskTargetRunner(
            mailRefresher: { _ in throw TaskTargetRunnerError.unsupportedTarget("mail") },
            calendarRefresher: { _ in "calendar" },
            rssRefresher: { _ in "rss" },
            sessionMessenger: { _ in "session" }
        )
        let service = TaskSchedulerRunnerService(repository: repository, scheduler: TaskSchedulerService(), runner: runner)

        let outcomes = try await service.runDueTasks(now: Date(timeIntervalSince1970: 2_000))
        let failedMail = try #require(try repository.loadTask(id: "system.mail.check-every-10-minutes"))
        let calendar = try #require(try repository.loadTask(id: "system.calendar.account.calendar-account-a.refresh"))

        #expect(outcomes.count == 2)
        #expect(outcomes.filter(\.succeeded).count == 1)
        #expect(failedMail.lifecycle.status == .failed)
        #expect(calendar.lifecycle.status == .active)
    }

    @Test func serviceRunsMissedDailyTaskOnNextSchedulerPassAndPreservesAnchor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(3 * 24 * 60 * 60 + 3_600)
        try saveSystemDefaultsAsNotDue(repository: repository, now: now)
        let expectedNextRun = start.addingTimeInterval(4 * 24 * 60 * 60)
        let task = ConnorTaskDefinition(
            id: "user.daily.catch-up",
            name: "Daily catch-up",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: start, recurrence: .daily),
            target: .createSessionAndSendMessage(message: "Daily check-in", title: "Daily"),
            lifecycle: ConnorTaskLifecycle(
                status: .active,
                nextRunAt: start.addingTimeInterval(10 * 24 * 60 * 60),
                lastFinishedAt: start
            ),
            metadata: ConnorTaskMetadata(tags: ["user", "scheduled-session-message"]),
            createdAt: start,
            updatedAt: start
        )
        try repository.saveTask(task)
        let calls = SessionMessageCallCounter()
        let runner = TaskTargetRunner(
            mailRefresher: { _ in "mail" },
            calendarRefresher: { _ in "calendar" },
            rssRefresher: { _ in "rss" },
            sessionMessenger: calls.send
        )
        let service = TaskSchedulerRunnerService(
            repository: repository,
            scheduler: TaskSchedulerService(calendar: Calendar(identifier: .gregorian)),
            runner: runner
        )

        let outcomes = try await service.runDueTasks(now: now)
        let reloaded = try #require(try repository.loadTask(id: task.id))

        #expect(outcomes.map(\.taskID) == [task.id])
        #expect(await calls.count == 1)
        #expect(await calls.messages == ["Daily check-in"])
        #expect(reloaded.lifecycle.status == .active)
        #expect(reloaded.lifecycle.nextRunAt == expectedNextRun)
    }

    private func saveSystemDefaultsAsNotDue(repository: AppTaskManagementRepository, now: Date) throws {
        for var defaultTask in ConnorTaskDefinition.systemDefaults(now: Date(timeIntervalSince1970: 0)) {
            let interval = defaultTask.trigger.intervalSeconds ?? 600
            defaultTask.lifecycle.status = .active
            defaultTask.lifecycle.lastFinishedAt = now
            defaultTask.lifecycle.nextRunAt = now.addingTimeInterval(interval)
            try repository.saveTask(defaultTask)
        }
    }

    private func makeRSSRefreshTask(sourceID: String, intervalSeconds: TimeInterval, now: Date) -> ConnorTaskDefinition {
        ConnorTaskDefinition(
            id: "system.rss.source.\(sourceID).refresh",
            name: "检查 RSS：\(sourceID)",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: intervalSeconds, recurrence: .interval),
            target: ConnorTaskTarget(
                targetKind: "source.runtime",
                targetID: "rss",
                operationName: "refresh",
                parameters: ["sourceKind": "rss", "sourceInstanceID": sourceID]
            ),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem,
            createdAt: now,
            updatedAt: now
        )
    }
}

private actor RefreshCallCounter {
    var count = 0
    var requests: [SourceRefreshTaskRequest] = []
    func refresh(_ request: SourceRefreshTaskRequest) async throws -> String {
        count += 1
        requests.append(request)
        return "rss refreshed"
    }
}

private actor SessionMessageCallCounter {
    var count = 0
    var messages: [String] = []

    func send(_ request: TaskSessionMessageRequest) async throws -> String {
        count += 1
        messages.append(request.message)
        return "session message sent"
    }
}
