import Foundation
import ConnorGraphCore
import ConnorGraphStore

public struct SessionTaskRecoveryPlanner: Sendable {
    public var stack: TaskManagementStack
    public var sessionRepository: AppChatSessionRepository

    public init(stack: TaskManagementStack, sessionRepository: AppChatSessionRepository) {
        self.stack = stack
        self.sessionRepository = sessionRepository
    }

    public func recoveryTargets(sessionID: String) throws -> [ConnorTaskTarget] {
        let persistedTasks = try sessionRepository.loadBackgroundTasks(sessionID: sessionID)
        for task in persistedTasks where task.status == .interrupted && explicitlyUnrecoverable(task) {
            try sessionRepository.updateBackgroundTask(
                sessionID: sessionID,
                taskID: task.id,
                status: .interrupted,
                detail: task.detail,
                errorMessage: "Runtime continuation was lost; task requires retry from the session UI."
            )
        }
        let tasks = try stack.recoverableSessionTasks(sessionID: sessionID)
        return tasks
            .filter { task in
                guard task.lifecycle.status == .stopped,
                      let backgroundTaskID = task.target.parameters["backgroundTaskID"],
                      let persisted = persistedTasks.first(where: { $0.id == backgroundTaskID })
                else { return true }
                return !explicitlyUnrecoverable(persisted)
            }
            .map(\.target)
    }

    private func explicitlyUnrecoverable(_ task: PersistedSessionBackgroundTask) -> Bool {
        task.payloadJSON.contains("\"recoverable\":false") || task.payloadJSON.contains("\"recoverable\": false")
    }
}
