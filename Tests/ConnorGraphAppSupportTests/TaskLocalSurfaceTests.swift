import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Task Local Surface Tests")
struct TaskLocalSurfaceTests {
    @Test func localTaskSurfaceExposesTaskRoutesWithoutReviewGate() {
        let presentation = ConnorLocalTaskSurfacePresentation.default

        #expect(presentation.endpoints.contains { $0.id == .tasks && $0.path == "/v1/tasks" })
        #expect(presentation.endpoints.contains { $0.id == .taskRuns && $0.path == "/v1/tasks/{id}/runs" })
        #expect(presentation.endpoints.contains { $0.id == .taskStop && $0.path == "/v1/tasks/{id}/stop" })
        #expect(presentation.endpoints.contains { $0.id == .taskRestore && $0.path == "/v1/tasks/{id}/restore" })
        #expect(presentation.endpoints.allSatisfy { $0.requiresReview == false })
        #expect(presentation.supportedTriggerKinds == [.scheduled, .eventTriggered])
        #expect(presentation.localOnly)
    }

    @Test func cliCatalogUsesTasksCommands() {
        let commands = ConnorLocalTaskSurfaceCatalog.defaultCommands

        #expect(commands.contains { $0.id == .taskList && $0.usage == "connor tasks list" })
        #expect(commands.contains { $0.id == .taskShow && $0.usage == "connor tasks show <task-id>" })
        #expect(commands.contains { $0.id == .taskStop && $0.usage == "connor tasks stop <task-id>" })
        #expect(commands.contains { $0.id == .taskDelete && $0.usage == "connor tasks delete <task-id>" })
        #expect(commands.allSatisfy { $0.requiresReview == false })
        #expect(commands.contains { $0.usage.contains("execute-reviewed") } == false)
    }

    @Test func localTaskSurfaceExposesSessionTaskRoutes() {
        let presentation = ConnorLocalTaskSurfacePresentation.default

        #expect(presentation.endpoints.contains { $0.id == .sessionTasks && $0.path == "/v1/sessions/{sessionID}/tasks" })
        #expect(presentation.endpoints.contains { $0.id == .sessionRecoverableTasks && $0.path == "/v1/sessions/{sessionID}/tasks/recoverable" })
        #expect(presentation.endpoints.contains { $0.id == .sessionTaskStop && $0.path == "/v1/sessions/{sessionID}/tasks/{taskID}/stop" })
        #expect(presentation.endpoints.contains { $0.id == .sessionTaskRestore && $0.path == "/v1/sessions/{sessionID}/tasks/{taskID}/restore" })
    }

    @Test func cliCatalogUsesSessionTaskCommands() {
        let commands = ConnorLocalTaskSurfaceCatalog.defaultCommands

        #expect(commands.contains { $0.id == .sessionTaskList && $0.usage == "connor tasks session list <session-id>" })
        #expect(commands.contains { $0.id == .sessionTaskRecoverable && $0.usage == "connor tasks session recoverable <session-id>" })
        #expect(commands.contains { $0.id == .sessionTaskStop && $0.usage == "connor tasks session stop <session-id> <task-id>" })
        #expect(commands.contains { $0.id == .sessionTaskRestore && $0.usage == "connor tasks session restore <session-id> <task-id>" })
        #expect(commands.allSatisfy { $0.requiresReview == false })
        #expect(commands.contains { $0.usage.contains("execute-reviewed") || $0.usage.contains("manual") } == false)
    }

    @Test func taskSurfaceReadinessPayloadDoesNotExposeApprovalFields() {
        let payload = ConnorLocalTaskSurfaceReadiness.default

        #expect(payload.surface == "local-api-cli-task")
        #expect(payload.status == "ready")
        #expect(payload.reviewGateReady == nil)
        #expect(payload.manualTaskSupported == false)
        #expect(payload.triggerKinds == ["scheduled", "eventTriggered"])
    }
}
