import Foundation
import ConnorGraphCore
import ConnorGraphStore

public struct SessionBackgroundTaskManagementAdapter: Sendable {
    public init() {}

    public func taskDefinition(from task: PersistedSessionBackgroundTask) -> ConnorTaskDefinition {
        ConnorTaskDefinition(
            id: taskManagementID(for: task),
            name: task.title,
            origin: .ai,
            trigger: ConnorTaskTrigger(
                kind: .eventTriggered,
                eventName: "session.background-task.created",
                eventFilter: ["sessionID": task.sessionID]
            ),
            target: ConnorTaskTarget(
                targetKind: "session.background-runtime",
                targetID: task.sessionID,
                operationName: task.kind,
                parameters: [
                    "backgroundTaskID": task.id,
                    "payloadJSON": task.payloadJSON
                ]
            ),
            lifecycle: lifecycle(from: task),
            metadata: metadata(from: task),
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
    }

    public func runRecord(from task: PersistedSessionBackgroundTask) -> ConnorTaskRunRecord {
        ConnorTaskRunRecord(
            id: "session-background-\(task.id)-\(Int(task.updatedAt.timeIntervalSince1970))",
            taskID: taskManagementID(for: task),
            status: runStatus(from: task.status),
            startedAt: task.createdAt,
            finishedAt: finishedAt(from: task),
            outputSummary: task.detail,
            errorMessage: task.errorMessage,
            externalRunID: task.id
        )
    }

    public func recoverableTasks(from tasks: [PersistedSessionBackgroundTask], sessionID: String) -> [ConnorTaskDefinition] {
        tasks
            .filter { $0.sessionID == sessionID }
            .filter { isRecoverable(status: $0.status) }
            .sorted { lhs, rhs in
                let lhsPriority = recoveryPriority(for: lhs.status)
                let rhsPriority = recoveryPriority(for: rhs.status)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.createdAt < rhs.createdAt
            }
            .map(taskDefinition(from:))
    }

    public func taskManagementID(for task: PersistedSessionBackgroundTask) -> String {
        "session.\(task.sessionID).background.\(task.id)"
    }

    public func originalBackgroundTaskID(from taskManagementID: String, sessionID: String) -> String? {
        let prefix = "session.\(sessionID).background."
        guard taskManagementID.hasPrefix(prefix) else { return nil }
        return String(taskManagementID.dropFirst(prefix.count))
    }

    private func lifecycle(from task: PersistedSessionBackgroundTask) -> ConnorTaskLifecycle {
        ConnorTaskLifecycle(
            status: lifecycleStatus(from: task.status),
            lastRunAt: task.status == .running ? task.createdAt : nil,
            lastFinishedAt: finishedAt(from: task),
            failureCount: task.status == .failed ? 1 : 0,
            lastErrorMessage: task.errorMessage
        )
    }

    private func metadata(from task: PersistedSessionBackgroundTask) -> ConnorTaskMetadata {
        ConnorTaskMetadata(
            createdBySessionID: task.sessionID,
            rationale: "Session-owned background task managed through Task Management Stack.",
            tags: ["session", "background", task.kind],
            scope: .session,
            ownerSessionID: task.sessionID,
            isRecoverable: isRecoverable(status: task.status),
            recoveryPolicy: recoveryPolicy(from: task.status),
            isProtectedSystemTask: false
        )
    }

    private func lifecycleStatus(from status: PersistedSessionBackgroundTaskStatus) -> ConnorTaskLifecycleStatus {
        switch status {
        case .queued: .active
        case .running: .running
        case .succeeded: .succeeded
        case .failed: .failed
        case .interrupted: .stopped
        }
    }

    private func runStatus(from status: PersistedSessionBackgroundTaskStatus) -> ConnorTaskRunStatus {
        switch status {
        case .queued: .queued
        case .running: .running
        case .succeeded: .succeeded
        case .failed: .failed
        case .interrupted: .cancelled
        }
    }

    private func recoveryPolicy(from status: PersistedSessionBackgroundTaskStatus) -> ConnorTaskRecoveryPolicy {
        switch status {
        case .queued, .running: .restoreIfQueuedOrRunning
        case .interrupted: .restoreIfInterrupted
        case .succeeded, .failed: .none
        }
    }

    private func isRecoverable(status: PersistedSessionBackgroundTaskStatus) -> Bool {
        switch status {
        case .queued, .running, .interrupted: true
        case .succeeded, .failed: false
        }
    }

    private func recoveryPriority(for status: PersistedSessionBackgroundTaskStatus) -> Int {
        switch status {
        case .queued: 0
        case .running: 1
        case .interrupted: 2
        case .succeeded, .failed: 3
        }
    }

    private func finishedAt(from task: PersistedSessionBackgroundTask) -> Date? {
        switch task.status {
        case .succeeded, .failed, .interrupted: task.updatedAt
        case .queued, .running: nil
        }
    }
}
