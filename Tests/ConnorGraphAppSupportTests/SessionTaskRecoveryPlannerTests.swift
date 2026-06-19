import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

@Suite("Session Task Recovery Planner Tests")
struct SessionTaskRecoveryPlannerTests {
    @Test func plannerReturnsOpaqueRecoveryTargetsForRecoverableSessionTasks() throws {
        let (planner, chatRepository) = try makePlanner()
        try chatRepository.saveBackgroundTask(backgroundTask(id: "queued", status: .queued))
        try chatRepository.saveBackgroundTask(backgroundTask(id: "interrupted", status: .interrupted))
        try chatRepository.saveBackgroundTask(backgroundTask(id: "succeeded", status: .succeeded))

        let targets = try planner.recoveryTargets(sessionID: "session-1")

        #expect(targets.map(\.targetKind) == ["session.background-runtime", "session.background-runtime"])
        #expect(targets.map(\.targetID) == ["session-1", "session-1"])
        #expect(targets.map { $0.parameters["backgroundTaskID"] } == ["queued", "interrupted"])
    }

    @Test func plannerDoesNotResumeRuntimeDirectly() throws {
        let (planner, chatRepository) = try makePlanner()
        try chatRepository.saveBackgroundTask(backgroundTask(id: "running", status: .running))

        _ = try planner.recoveryTargets(sessionID: "session-1")
        let persisted = try #require(try chatRepository.loadBackgroundTasks(sessionID: "session-1").first)

        #expect(persisted.status == .running)
        #expect(persisted.detail == "Background browser fetch")
    }

    @Test func plannerMarksUnrecoverableInterruptedTasksWithClearReason() throws {
        let (planner, chatRepository) = try makePlanner()
        try chatRepository.saveBackgroundTask(backgroundTask(
            id: "interrupted-unrecoverable",
            status: .interrupted,
            payloadJSON: "{\"recoverable\":false}"
        ))

        let targets = try planner.recoveryTargets(sessionID: "session-1")
        let persisted = try #require(try chatRepository.loadBackgroundTasks(sessionID: "session-1").first)

        #expect(targets.isEmpty)
        #expect(persisted.status == .interrupted)
        #expect(persisted.errorMessage == "Runtime continuation was lost; task requires retry from the session UI.")
    }

    private func makePlanner() throws -> (SessionTaskRecoveryPlanner, AppChatSessionRepository) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
        try store.migrate()
        let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
        let taskRepository = AppTaskManagementRepository(storagePaths: storagePaths)
        let chatRepository = AppChatSessionRepository(store: store, storagePaths: storagePaths)
        let stack = TaskManagementStack(repository: taskRepository, sessionRepository: chatRepository)
        let planner = SessionTaskRecoveryPlanner(stack: stack, sessionRepository: chatRepository)
        return (planner, chatRepository)
    }

    private func backgroundTask(
        id: String,
        status: PersistedSessionBackgroundTaskStatus,
        payloadJSON: String = "{\"recoverable\":true}"
    ) -> PersistedSessionBackgroundTask {
        PersistedSessionBackgroundTask(
            id: id,
            sessionID: "session-1",
            kind: "browser.web-fetch",
            title: "Fetch article",
            detail: "Background browser fetch",
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_100),
            payloadJSON: payloadJSON
        )
    }
}
