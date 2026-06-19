import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Event Dispatcher Tests")
struct TaskEventDispatcherTests {
    @Test func dispatcherMatchesSessionStatusChangedTasks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let task = ConnorTaskDefinition(
            id: "ai.done-followup",
            name: "Done followup",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .eventTriggered, eventName: ConnorTaskEventName.sessionStatusChanged, eventFilter: ["toStatus": "done"]),
            target: .sendMessageToSession(message: "Summarize this session"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(createdBySessionID: "session-creator")
        )
        try repository.saveTask(task)
        let session = SessionMessageRecorder()
        let runner = TaskTargetRunner(mailRefresher: { _ in "mail" }, calendarRefresher: { _ in "calendar" }, rssRefresher: { _ in "rss" }, sessionMessenger: session.perform)
        let dispatcher = TaskEventDispatcher(repository: repository, runner: runner)

        let outcomes = try await dispatcher.dispatchSessionStatusChanged(sessionID: "session-1", fromStatus: "todo", toStatus: "done")
        let history = try repository.loadRunHistory(taskID: task.id, limit: 10)

        #expect(outcomes.map(\.taskID) == [task.id])
        #expect(await session.messages == ["session-1:Summarize this session"])
        #expect(history.map(\.status) == [.succeeded, .running])
    }

    @Test func dispatcherIgnoresStoppedOrNonMatchingTasks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        var task = ConnorTaskDefinition(
            id: "ai.done-followup",
            name: "Done followup",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .eventTriggered, eventName: ConnorTaskEventName.sessionStatusChanged, eventFilter: ["toStatus": "done"]),
            target: .sendMessageToSession(message: "Summarize this session"),
            lifecycle: ConnorTaskLifecycle(status: .stopped),
            metadata: ConnorTaskMetadata(createdBySessionID: "session-creator")
        )
        try repository.saveTask(task)
        task.id = "ai.review-followup"
        task.lifecycle.status = .active
        task.trigger.eventFilter = ["toStatus": "review"]
        try repository.saveTask(task)
        let session = SessionMessageRecorder()
        let runner = TaskTargetRunner(mailRefresher: { _ in "mail" }, calendarRefresher: { _ in "calendar" }, rssRefresher: { _ in "rss" }, sessionMessenger: session.perform)
        let dispatcher = TaskEventDispatcher(repository: repository, runner: runner)

        let outcomes = try await dispatcher.dispatchSessionStatusChanged(sessionID: "session-1", fromStatus: "todo", toStatus: "done")

        #expect(outcomes.isEmpty)
        #expect(await session.messages.isEmpty)
    }
}

private actor SessionMessageRecorder {
    var messages: [String] = []
    func perform(_ request: TaskSessionMessageRequest) async throws -> String {
        messages.append("\(request.sessionID ?? "new"):\(request.message)")
        return "sent"
    }
}
