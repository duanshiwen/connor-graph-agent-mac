import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

@Suite("Session Background Task Management Adapter Tests")
struct SessionBackgroundTaskManagementAdapterTests {
    @Test func adapterMapsPersistedBackgroundTaskToSessionScopedTaskDefinition() {
        let task = persistedTask(status: .running, payloadJSON: "{\"url\":\"https://example.com\"}")
        let definition = SessionBackgroundTaskManagementAdapter().taskDefinition(from: task)

        #expect(definition.id == "session.session-1.background.task-1")
        #expect(definition.name == "Fetch article")
        #expect(definition.origin == .ai)
        #expect(definition.trigger.kind == .eventTriggered)
        #expect(definition.trigger.eventName == "session.background-task.created")
        #expect(definition.trigger.eventFilter["sessionID"] == "session-1")
        #expect(definition.target.targetKind == "session.background-runtime")
        #expect(definition.target.targetID == "session-1")
        #expect(definition.target.operationName == "browser.web-fetch")
        #expect(definition.target.parameters["backgroundTaskID"] == "task-1")
        #expect(definition.target.parameters["payloadJSON"] == "{\"url\":\"https://example.com\"}")
        #expect(definition.metadata.scope == .session)
        #expect(definition.metadata.ownerSessionID == "session-1")
        #expect(definition.metadata.isRecoverable == true)
        #expect(definition.metadata.recoveryPolicy == .restoreIfQueuedOrRunning)
        #expect(definition.lifecycle.status == .running)
        #expect(definition.lifecycle.lastRunAt == task.createdAt)
    }

    @Test func adapterMapsStatusesToTaskLifecycleAndRunRecords() {
        let adapter = SessionBackgroundTaskManagementAdapter()
        let cases: [(PersistedSessionBackgroundTaskStatus, ConnorTaskLifecycleStatus, ConnorTaskRunStatus)] = [
            (.queued, .active, .queued),
            (.running, .running, .running),
            (.succeeded, .succeeded, .succeeded),
            (.failed, .failed, .failed),
            (.interrupted, .stopped, .cancelled)
        ]

        for (persistedStatus, lifecycleStatus, runStatus) in cases {
            let task = persistedTask(id: "task-\(persistedStatus.rawValue)", status: persistedStatus)
            let definition = adapter.taskDefinition(from: task)
            let record = adapter.runRecord(from: task)

            #expect(definition.lifecycle.status == lifecycleStatus)
            #expect(record.status == runStatus)
            #expect(record.taskID == definition.id)
            #expect(record.externalRunID == task.id)
        }
    }

    @Test func adapterExposesOpaqueRecoveryTargetWithoutRunningRuntime() {
        let definition = SessionBackgroundTaskManagementAdapter().taskDefinition(from: persistedTask(status: .interrupted))

        #expect(definition.target.targetKind == "session.background-runtime")
        #expect(definition.target.targetID == "session-1")
        #expect(definition.target.operationName == "browser.web-fetch")
        #expect(definition.target.parameters["backgroundTaskID"] == "task-1")
        #expect(definition.metadata.recoveryPolicy == .restoreIfInterrupted)
    }

    @Test func adapterFindsRecoverableQueuedRunningAndInterruptedTasks() {
        let adapter = SessionBackgroundTaskManagementAdapter()
        let tasks = [
            persistedTask(id: "queued", sessionID: "session-1", status: .queued),
            persistedTask(id: "running", sessionID: "session-1", status: .running),
            persistedTask(id: "interrupted", sessionID: "session-1", status: .interrupted),
            persistedTask(id: "succeeded", sessionID: "session-1", status: .succeeded),
            persistedTask(id: "failed", sessionID: "session-1", status: .failed),
            persistedTask(id: "other", sessionID: "session-2", status: .running)
        ]

        let recoverable = adapter.recoverableTasks(from: tasks, sessionID: "session-1")

        #expect(recoverable.map(\.id) == [
            "session.session-1.background.queued",
            "session.session-1.background.running",
            "session.session-1.background.interrupted"
        ])
    }

    private func persistedTask(
        id: String = "task-1",
        sessionID: String = "session-1",
        status: PersistedSessionBackgroundTaskStatus,
        payloadJSON: String = "{}"
    ) -> PersistedSessionBackgroundTask {
        PersistedSessionBackgroundTask(
            id: id,
            sessionID: sessionID,
            kind: "browser.web-fetch",
            title: "Fetch article",
            detail: "Fetching article in background",
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_100),
            errorMessage: status == .failed ? "Network unavailable" : nil,
            payloadJSON: payloadJSON
        )
    }
}
