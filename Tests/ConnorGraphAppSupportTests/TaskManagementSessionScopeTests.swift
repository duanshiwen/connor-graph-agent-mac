import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

@Suite("Task Management Session Scope Tests")
struct TaskManagementSessionScopeTests {
    @Test func stackListsSessionScopedTasksFromChatRepository() throws {
        let (stack, chatRepository) = try makeStack()
        try chatRepository.saveBackgroundTask(backgroundTask(id: "task-1", sessionID: "session-1", status: .running))
        try chatRepository.saveBackgroundTask(backgroundTask(id: "task-2", sessionID: "session-2", status: .queued))

        let tasks = try stack.listSessionTasks(sessionID: "session-1")

        #expect(tasks.map(\.id) == ["session.session-1.background.task-1"])
        #expect(tasks.first?.metadata.scope == .session)
        #expect(tasks.first?.metadata.ownerSessionID == "session-1")
    }

    @Test func stackFiltersRecoverableSessionTasksBySessionID() throws {
        let (stack, chatRepository) = try makeStack()
        try chatRepository.saveBackgroundTask(backgroundTask(id: "queued", sessionID: "session-1", status: .queued))
        try chatRepository.saveBackgroundTask(backgroundTask(id: "running", sessionID: "session-1", status: .running))
        try chatRepository.saveBackgroundTask(backgroundTask(id: "interrupted", sessionID: "session-1", status: .interrupted))
        try chatRepository.saveBackgroundTask(backgroundTask(id: "succeeded", sessionID: "session-1", status: .succeeded))
        try chatRepository.saveBackgroundTask(backgroundTask(id: "other", sessionID: "session-2", status: .running))

        let tasks = try stack.recoverableSessionTasks(sessionID: "session-1")

        #expect(tasks.map(\.id) == [
            "session.session-1.background.queued",
            "session.session-1.background.running",
            "session.session-1.background.interrupted"
        ])
    }

    @Test func stackStopsSessionBackgroundTaskWithoutDeletingSessionOwnership() throws {
        let (stack, chatRepository) = try makeStack()
        try chatRepository.saveBackgroundTask(backgroundTask(id: "task-1", sessionID: "session-1", status: .running))

        let stopped = try stack.stopSessionTask(sessionID: "session-1", taskID: "session.session-1.background.task-1", reason: "App shutting down")
        let persisted = try #require(try chatRepository.loadBackgroundTasks(sessionID: "session-1").first)

        #expect(stopped.lifecycle.status == .stopped)
        #expect(stopped.metadata.ownerSessionID == "session-1")
        #expect(persisted.status == .interrupted)
        #expect(persisted.errorMessage == "App shutting down")
    }

    @Test func stackRestoresSessionBackgroundTaskAsRecoverableIntentOnly() throws {
        let (stack, chatRepository) = try makeStack()
        try chatRepository.saveBackgroundTask(backgroundTask(id: "task-1", sessionID: "session-1", status: .interrupted, errorMessage: "Lost continuation"))

        let restored = try stack.restoreSessionTask(sessionID: "session-1", taskID: "session.session-1.background.task-1")
        let persisted = try #require(try chatRepository.loadBackgroundTasks(sessionID: "session-1").first)

        #expect(restored.lifecycle.status == .active)
        #expect(restored.target.targetKind == "session.background-runtime")
        #expect(restored.target.parameters["backgroundTaskID"] == "task-1")
        #expect(persisted.status == .queued)
        #expect(persisted.errorMessage == nil)
    }

    private func makeStack() throws -> (TaskManagementStack, AppChatSessionRepository) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
        try store.migrate()
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
        let taskRepository = AppTaskManagementRepository(storagePaths: storagePaths)
        let chatRepository = AppChatSessionRepository(store: store, storagePaths: storagePaths)
        let stack = TaskManagementStack(repository: taskRepository, sessionRepository: chatRepository)
        return (stack, chatRepository)
    }

    private func backgroundTask(
        id: String,
        sessionID: String,
        status: PersistedSessionBackgroundTaskStatus,
        errorMessage: String? = nil
    ) -> PersistedSessionBackgroundTask {
        PersistedSessionBackgroundTask(
            id: id,
            sessionID: sessionID,
            kind: "browser.web-fetch",
            title: "Fetch article",
            detail: "Background browser fetch",
            status: status,
            createdAt: Date(timeIntervalSince1970: Double(id.unicodeScalars.first?.value ?? 1)),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            errorMessage: errorMessage,
            payloadJSON: "{\"url\":\"https://example.com\"}"
        )
    }
}
