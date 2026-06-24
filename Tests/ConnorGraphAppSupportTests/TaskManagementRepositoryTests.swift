import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Management Repository Tests")
struct TaskManagementRepositoryTests {
    @Test func repositorySeedsDefaultTasksInTasksDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))

        let tasks = try repository.loadOrCreateDefault(now: Date(timeIntervalSince1970: 0))

        #expect(tasks.contains { $0.id == "system.mail.check-every-10-minutes" } == false)
        #expect(tasks.contains { $0.id == "system.calendar.check-every-10-minutes" } == false)
        #expect(tasks.contains { $0.target.targetID == "rss" } == false)
        #expect(FileManager.default.fileExists(atPath: repository.taskDefinitionsURL.path))
        #expect(repository.taskDefinitionsURL.path.contains("/tasks/task-definitions.json"))
    }

    @Test func systemDefaultsIncludeProtectedMemoryOSPipelineTasks() throws {
        let now = Date(timeIntervalSince1970: 100)

        let tasks = ConnorTaskDefinition.systemDefaults(now: now)
        let l1Task = try #require(tasks.first { $0.id == "system.memory-os.plan-l1-to-l2" })
        let l2Task = try #require(tasks.first { $0.id == "system.memory-os.plan-l2-to-knowledge" })

        #expect(l1Task.origin == .system)
        #expect(l1Task.trigger.kind == .scheduled)
        #expect(l1Task.trigger.intervalSeconds == 86_400)
        #expect(l1Task.trigger.recurrence == .interval)
        #expect(l1Task.target.targetKind == "memory_os.pipeline")
        #expect(l1Task.target.targetID == "default")
        #expect(l1Task.target.operationName == "plan_l1_to_l2_jobs")
        #expect(l1Task.lifecycle.status == .active)
        #expect(l1Task.metadata.isProtectedSystemTask)

        #expect(l2Task.origin == .system)
        #expect(l2Task.trigger.kind == .scheduled)
        #expect(l2Task.trigger.intervalSeconds == 86_400)
        #expect(l2Task.trigger.recurrence == .interval)
        #expect(l2Task.target.targetKind == "memory_os.pipeline")
        #expect(l2Task.target.targetID == "default")
        #expect(l2Task.target.operationName == "plan_l2_to_knowledge_jobs")
        #expect(l2Task.lifecycle.status == .active)
        #expect(l2Task.metadata.isProtectedSystemTask)
    }

    @Test func repositoryBackfillsMemoryOSPipelineDefaults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        try repository.saveTask(makeProtectedCalendarRefreshTask(accountID: "calendar-account-a"))

        let tasks = try repository.loadOrCreateDefault(now: Date(timeIntervalSince1970: 100))

        #expect(tasks.contains { $0.id == "system.memory-os.plan-l1-to-l2" })
        #expect(tasks.contains { $0.id == "system.memory-os.plan-l2-to-knowledge" })
        #expect(tasks.contains { $0.id == "system.calendar.account.calendar-account-a.refresh" })
    }

    @Test func repositoryReactivatesStoppedProtectedSystemTasksWhenDefaultsLoad() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        var defaultTask = try #require(ConnorTaskDefinition.systemDefaults(now: Date(timeIntervalSince1970: 0)).first)
        defaultTask.lifecycle.status = .stopped
        defaultTask.lifecycle.lastErrorMessage = "legacy pause"
        try repository.saveTask(defaultTask)

        let tasks = try repository.loadOrCreateDefault(now: Date(timeIntervalSince1970: 10))
        let reloadedTask = try #require(tasks.first { $0.id == defaultTask.id })

        #expect(reloadedTask.lifecycle.status == .active)
        #expect(reloadedTask.lifecycle.lastErrorMessage == nil)
        #expect(FileManager.default.fileExists(atPath: repository.taskDefinitionsURL.path))
    }

    @Test func repositoryRejectsStopRestoreAndDeleteForProtectedSystemTasks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let calendar = makeProtectedCalendarRefreshTask(accountID: "calendar-account-a")
        try repository.saveTask(calendar)

        #expect(throws: AppTaskManagementError.self) {
            try repository.stopTask(id: calendar.id, reason: "quiet hours")
        }

        #expect(throws: AppTaskManagementError.self) {
            try repository.restoreTask(id: calendar.id)
        }

        #expect(throws: AppTaskManagementError.self) {
            try repository.deleteTask(id: calendar.id, reason: "remove")
        }

        let reloaded = try #require(try repository.loadTask(id: calendar.id))
        #expect(reloaded.lifecycle.status == .active)
    }

    @Test func repositoryAllowsUserAndAITaskDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let now = Date(timeIntervalSince1970: 10)
        var task = ConnorTaskDefinition(
            id: "ai.summary-task",
            name: "Summary task",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .eventTriggered, eventName: "session.done"),
            target: ConnorTaskTarget(targetKind: "external.runtime", targetID: "summary", operationName: "create"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(createdBySessionID: "session-1", rationale: "summarize", tags: ["ai"]),
            createdAt: now,
            updatedAt: now
        )

        try repository.saveTask(task)
        task.name = "Changed"
        try repository.saveTask(task)

        let stopped = try repository.stopTask(id: task.id, reason: "quiet hours")
        #expect(stopped.lifecycle.status == .stopped)

        let restored = try repository.restoreTask(id: task.id)
        #expect(restored.lifecycle.status == .active)

        let deleted = try repository.deleteTask(id: task.id, reason: "not needed")

        #expect(deleted.lifecycle.status == .deleted)
        #expect(try repository.loadTasks(includeDeleted: false).contains { $0.id == task.id } == false)
        #expect(try repository.loadTasks(includeDeleted: true).contains { $0.id == task.id } == true)
    }

    @Test func repositoryAppendsAndLoadsRunHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let record = ConnorTaskRunRecord(
            id: "run-1",
            taskID: "system.rss.source.feed-a.refresh",
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 20),
            finishedAt: Date(timeIntervalSince1970: 21),
            outputSummary: "external runtime completed",
            externalRunID: "rss-feed-a-run-1"
        )

        try repository.appendRunRecord(record)
        let all = try repository.loadRunHistory(taskID: nil, limit: 10)
        let filtered = try repository.loadRunHistory(taskID: record.taskID, limit: 10)

        #expect(all == [record])
        #expect(filtered == [record])
        #expect(FileManager.default.fileExists(atPath: repository.taskRunHistoryURL.path))
    }

    private func makeProtectedCalendarRefreshTask(accountID: String) -> ConnorTaskDefinition {
        ConnorTaskDefinition(
            id: "system.calendar.account.\(accountID).refresh",
            name: "检查日历：Calendar A",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "calendar", operationName: "refresh", parameters: ["sourceKind": "calendar", "sourceInstanceID": accountID]),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem
        )
    }
}
