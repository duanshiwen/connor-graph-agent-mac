import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Management Stack Tests")
struct TaskManagementStackTests {
    @Test func stackUpdatesLifecycleWithoutRunningTargetImplementation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let stack = TaskManagementStack(repository: repository)
        _ = try repository.loadOrCreateDefault(now: Date(timeIntervalSince1970: 0))

        let stopped = try stack.stopTask(id: "system.mail.check-every-10-minutes", reason: "network constrained")
        let restored = try stack.restoreTask(id: "system.mail.check-every-10-minutes")

        #expect(stopped.lifecycle.status == .stopped)
        #expect(restored.lifecycle.status == .active)
        #expect(restored.target.targetKind == "source.runtime")
    }

    @Test func stackRejectsProtectedSystemTaskDeletionButDeletesAITask() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let stack = TaskManagementStack(repository: repository)
        _ = try repository.loadOrCreateDefault(now: Date(timeIntervalSince1970: 0))

        #expect(throws: AppTaskManagementError.self) {
            try stack.deleteTask(id: "system.calendar.check-every-10-minutes", reason: "remove")
        }

        let aiTask = ConnorTaskDefinition(
            id: "ai.watch-keyword",
            name: "Watch keyword",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .eventTriggered, eventName: "rss.item.arrived", eventFilter: ["keyword": "Connor"]),
            target: ConnorTaskTarget(targetKind: "external.runtime", targetID: "rss", operationName: "watch"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(createdBySessionID: "session-1", rationale: "Track Connor news")
        )
        try stack.saveTask(aiTask)
        let deleted = try stack.deleteTask(id: aiTask.id, reason: "done")

        #expect(deleted.lifecycle.status == .deleted)
    }

    @Test func stackRecordsExternalRuntimeRunUpdates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let stack = TaskManagementStack(repository: repository)
        _ = try repository.loadOrCreateDefault(now: Date(timeIntervalSince1970: 0))

        let running = ConnorTaskRunRecord(id: "run-running", taskID: "system.mail.check-every-10-minutes", status: .running, startedAt: Date(timeIntervalSince1970: 1), outputSummary: "started")
        let succeeded = ConnorTaskRunRecord(id: "run-success", taskID: "system.mail.check-every-10-minutes", status: .succeeded, startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2), outputSummary: "done")

        try stack.recordRun(running)
        try stack.recordRun(succeeded)
        let history = try stack.runHistory(taskID: "system.mail.check-every-10-minutes", limit: 10)
        let task = try repository.loadTask(id: "system.mail.check-every-10-minutes")

        #expect(history.map(\.id) == ["run-success", "run-running"])
        #expect(task?.lifecycle.status == .succeeded)
        #expect(task?.lifecycle.lastFinishedAt == Date(timeIntervalSince1970: 2))
    }
}
