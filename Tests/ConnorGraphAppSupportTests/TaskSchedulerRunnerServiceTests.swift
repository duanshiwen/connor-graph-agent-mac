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
        for var defaultTask in ConnorTaskDefinition.systemDefaults(now: Date(timeIntervalSince1970: 0)) {
            defaultTask.lifecycle.lastFinishedAt = Date(timeIntervalSince1970: 0)
            if defaultTask.id != "system.rss.check-every-30-minutes" {
                defaultTask.lifecycle.status = .stopped
            }
            try repository.saveTask(defaultTask)
        }
        let task = try #require(try repository.loadTask(id: "system.rss.check-every-30-minutes"))
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
        let tasks = ConnorTaskDefinition.systemDefaults(now: Date(timeIntervalSince1970: 0)).map { task in
            var copy = task
            copy.lifecycle.lastFinishedAt = Date(timeIntervalSince1970: 0)
            return copy
        }
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
        let rss = try #require(try repository.loadTask(id: "system.rss.check-every-30-minutes"))

        #expect(outcomes.count == 3)
        #expect(outcomes.filter(\.succeeded).count == 2)
        #expect(failedMail.lifecycle.status == .failed)
        #expect(rss.lifecycle.status == .active)
    }
}

private actor RefreshCallCounter {
    var count = 0
    func refresh(_ runID: String?) async throws -> String {
        count += 1
        return "rss refreshed"
    }
}
