import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Management Stack Tests")
struct TaskManagementStackTests {
    @Test func stackRejectsProtectedSystemStopAndUpdatesUserLifecycleWithoutRunningTargetImplementation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let stack = TaskManagementStack(repository: repository)
        let calendar = makeProtectedCalendarRefreshTask(accountID: "calendar-account-a")
        try repository.saveTask(calendar)

        #expect(throws: AppTaskManagementError.self) {
            try stack.stopTask(id: calendar.id, reason: "network constrained")
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

        let stopped = try stack.stopTask(id: aiTask.id, reason: "network constrained")
        let restored = try stack.restoreTask(id: aiTask.id)

        #expect(stopped.lifecycle.status == .stopped)
        #expect(restored.lifecycle.status == .active)
        #expect(restored.target.targetKind == "external.runtime")
    }

    @Test func stackRejectsProtectedSystemTaskDeletionButDeletesAITask() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let stack = TaskManagementStack(repository: repository)
        let calendar = makeProtectedCalendarRefreshTask(accountID: "calendar-account-a")
        try repository.saveTask(calendar)

        #expect(throws: AppTaskManagementError.self) {
            try stack.deleteTask(id: calendar.id, reason: "remove")
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
        let calendar = makeProtectedCalendarRefreshTask(accountID: "calendar-account-a")
        try repository.saveTask(calendar)

        let running = ConnorTaskRunRecord(id: "run-running", taskID: calendar.id, status: .running, startedAt: Date(timeIntervalSince1970: 1), outputSummary: "started")
        let succeeded = ConnorTaskRunRecord(id: "run-success", taskID: calendar.id, status: .succeeded, startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2), outputSummary: "done")

        try stack.recordRun(running)
        try stack.recordRun(succeeded)
        let history = try stack.runHistory(taskID: calendar.id, limit: 10)
        let task = try repository.loadTask(id: calendar.id)

        #expect(history.map(\.id) == ["run-success", "run-running"])
        #expect(task?.lifecycle.status == .succeeded)
        #expect(task?.lifecycle.lastFinishedAt == Date(timeIntervalSince1970: 2))
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
