import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct TaskAutomationFeatureModelTests {
    @Test func reloadBuildsPresentationAndClearsMissingSelection() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = TaskAutomationFeatureModel(repository: fixture.repository)
        model.selectedTaskID = "missing-task"

        model.reload()

        #expect(model.presentation.summary.totalTaskCount == ConnorTaskDefinition.systemDefaults().count)
        #expect(model.presentation.summary.systemTaskCount == ConnorTaskDefinition.systemDefaults().count)
        #expect(model.selectedTaskID == nil)
    }

    @Test func createsScheduledAndEventTasksWithCurrentSessionOwnership() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = TaskAutomationFeatureModel(repository: fixture.repository)
        model.createdBySessionIDProvider = { "session-current" }

        let scheduledID = try model.createScheduledSessionMessageTask(
            name: "Daily review",
            runAt: Date(timeIntervalSince1970: 1_000),
            recurrence: .daily,
            message: "Review today",
            title: "Daily Review",
            rationale: "Keep context current"
        )
        let loadedScheduled = try fixture.repository.loadTask(id: scheduledID)
        let scheduled = try #require(loadedScheduled)
        #expect(scheduled.metadata.createdBySessionID == "session-current")
        #expect(scheduled.target == .createSessionAndSendMessage(message: "Review today", title: "Daily Review"))
        #expect(model.selectedTaskID == scheduledID)

        let eventID = try model.createSessionStatusMessageTask(
            name: "Done summary",
            toStatus: "done",
            message: "Summarize this session",
            sessionID: nil,
            rationale: nil
        )
        let loadedEvent = try fixture.repository.loadTask(id: eventID)
        let event = try #require(loadedEvent)
        #expect(event.metadata.createdBySessionID == "session-current")
        #expect(event.trigger.eventFilter == ["toStatus": "done"])
        #expect(model.selectedTaskID == eventID)
        #expect(model.presentation.cards.contains(where: { $0.id == scheduledID }))
        #expect(model.presentation.cards.contains(where: { $0.id == eventID }))
    }

    @Test func stopRestoreDeleteMutateRepositoryAndSelection() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = TaskAutomationFeatureModel(repository: fixture.repository)
        let taskID = try model.createSessionStatusMessageTask(
            name: "Lifecycle task",
            toStatus: "done",
            message: "Continue",
            sessionID: nil,
            rationale: nil
        )

        model.stopTask(taskID)
        #expect(try fixture.repository.loadTask(id: taskID)?.lifecycle.status == .stopped)
        #expect(model.presentation.cards.first(where: { $0.id == taskID })?.statusLabel == "已暂停")

        model.restoreTask(taskID)
        #expect(try fixture.repository.loadTask(id: taskID)?.lifecycle.status == .active)
        #expect(model.presentation.cards.first(where: { $0.id == taskID })?.statusLabel == "已启用")

        model.deleteTask(taskID)
        #expect(try fixture.repository.loadTask(id: taskID)?.lifecycle.status == .deleted)
        #expect(model.presentation.cards.contains(where: { $0.id == taskID }) == false)
        #expect(model.selectedTaskID == nil)
    }

    @Test func scheduledTaskRunGateIsExclusiveAndResettable() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = TaskAutomationFeatureModel(repository: fixture.repository)

        #expect(model.beginScheduledTaskRun())
        #expect(model.isRunningScheduledTasks)
        #expect(model.beginScheduledTaskRun() == false)

        model.endScheduledTaskRun()
        #expect(model.isRunningScheduledTasks == false)
        #expect(model.beginScheduledTaskRun())
    }

    @Test func missingRepositoryPreservesCreationErrorAndCannotBeginRun() {
        let model = TaskAutomationFeatureModel(repository: nil)

        #expect(throws: TaskAutomationFeatureModelError.self) {
            try model.createSessionStatusMessageTask(
                name: "Unavailable",
                toStatus: "done",
                message: "No repository",
                sessionID: nil,
                rationale: nil
            )
        }
        #expect(model.beginScheduledTaskRun() == false)
    }

    private func makeFixture() throws -> (root: URL, repository: AppTaskManagementRepository) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-task-automation-model-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        return (root, AppTaskManagementRepository(storagePaths: paths))
    }
}
