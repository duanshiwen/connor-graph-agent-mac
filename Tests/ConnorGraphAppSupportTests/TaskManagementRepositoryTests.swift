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

        #expect(tasks.contains { $0.id == "system.mail.check-every-10-minutes" })
        #expect(tasks.contains { $0.id == "system.calendar.check-every-10-minutes" })
        #expect(tasks.contains { $0.id == "system.rss.check-every-30-minutes" })
        #expect(FileManager.default.fileExists(atPath: repository.taskDefinitionsURL.path))
        #expect(repository.taskDefinitionsURL.path.contains("/tasks/task-definitions.json"))
    }

    @Test func repositoryBackfillsMissingSystemTasksWithoutReactivatingStoppedOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let defaults = ConnorTaskDefinition.systemDefaults(now: Date(timeIntervalSince1970: 0))
        var mail = try #require(defaults.first { $0.id == "system.mail.check-every-10-minutes" })
        mail.lifecycle.status = .stopped
        try repository.saveTask(mail)

        let tasks = try repository.loadOrCreateDefault(now: Date(timeIntervalSince1970: 10))
        let reloadedMail = try #require(tasks.first { $0.id == mail.id })

        #expect(tasks.contains { $0.id == "system.calendar.check-every-10-minutes" })
        #expect(tasks.contains { $0.id == "system.rss.check-every-30-minutes" })
        #expect(reloadedMail.lifecycle.status == .stopped)
        #expect(reloadedMail.target == ConnorTaskTarget.sourceRuntimeRefresh(sourceID: "mail"))
        #expect(FileManager.default.fileExists(atPath: repository.taskEventLogURL.path))
    }

    @Test func repositoryStopsRestoresAndProtectsSystemTasks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        _ = try repository.loadOrCreateDefault(now: Date(timeIntervalSince1970: 0))

        let stopped = try repository.stopTask(id: "system.mail.check-every-10-minutes", reason: "quiet hours")
        #expect(stopped.lifecycle.status == .stopped)

        let restored = try repository.restoreTask(id: "system.mail.check-every-10-minutes")
        #expect(restored.lifecycle.status == .active)

        #expect(throws: AppTaskManagementError.self) {
            try repository.deleteTask(id: "system.mail.check-every-10-minutes", reason: "remove")
        }
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
            taskID: "system.rss.check-every-30-minutes",
            status: .succeeded,
            startedAt: Date(timeIntervalSince1970: 20),
            finishedAt: Date(timeIntervalSince1970: 21),
            outputSummary: "external runtime completed",
            externalRunID: "rss-run-1"
        )

        try repository.appendRunRecord(record)
        let all = try repository.loadRunHistory(taskID: nil, limit: 10)
        let filtered = try repository.loadRunHistory(taskID: record.taskID, limit: 10)

        #expect(all == [record])
        #expect(filtered == [record])
        #expect(FileManager.default.fileExists(atPath: repository.taskRunHistoryURL.path))
    }
}
