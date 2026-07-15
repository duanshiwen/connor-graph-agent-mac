import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

@MainActor
@Observable
final class TaskAutomationFeatureModel {
    enum Event {
        case operationSucceeded
        case operationFailed(String)
    }

    var presentation = TaskManagementUIPresentation(
        summary: TaskManagementUISummary(
            totalTaskCount: 0,
            scheduledTaskCount: 0,
            eventTriggeredTaskCount: 0,
            systemTaskCount: 0,
            userTaskCount: 0,
            aiTaskCount: 0,
            stoppedTaskCount: 0,
            failedTaskCount: 0
        ),
        cards: []
    )
    var selectedTaskID: String?
    private(set) var isRunningScheduledTasks = false

    @ObservationIgnored private let taskRepository: AppTaskManagementRepository?
    @ObservationIgnored var createdBySessionIDProvider: @MainActor () -> String = { "" }
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    init(repository: AppTaskManagementRepository?) {
        taskRepository = repository
    }

    var repository: AppTaskManagementRepository? {
        taskRepository
    }

    func applyStartupSnapshot(_ result: StartupDomainResult<TaskManagementUIPresentation>) {
        guard let presentation = result.value else {
            if let failureMessage = result.failureMessage { onEvent?(.operationFailed(failureMessage)) }
            return
        }
        self.presentation = presentation
        if let selectedTaskID,
           !presentation.cards.contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = nil
        }
    }

    func reload() {
        do {
            guard let taskRepository else { return }
            let tasks = try taskRepository.loadOrCreateDefault()
            let history = try taskRepository.loadRunHistory(taskID: nil, limit: 100)
            presentation = TaskManagementUIPresentation.build(tasks: tasks, runHistory: history)
            if let selectedTaskID,
               !presentation.cards.contains(where: { $0.id == selectedTaskID }) {
                self.selectedTaskID = nil
            }
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func selectTask(_ id: String) {
        selectedTaskID = id
    }

    @discardableResult
    func createScheduledSessionMessageTask(
        name: String,
        runAt: Date,
        recurrence: ConnorTaskRecurrence,
        message: String,
        title: String,
        rationale: String?
    ) throws -> String {
        guard let taskRepository else { throw TaskAutomationFeatureModelError.missingRepository }
        let task = try TaskCreationService(repository: taskRepository).createScheduledSessionMessageTask(
            origin: .user,
            name: name,
            runAt: runAt,
            recurrence: recurrence,
            timezoneIdentifier: TimeZone.current.identifier,
            message: message,
            title: title,
            createdBySessionID: createdBySessionIDProvider(),
            rationale: rationale
        )
        reload()
        selectedTaskID = task.id
        return task.id
    }

    @discardableResult
    func createSessionStatusMessageTask(
        name: String,
        toStatus: String,
        message: String,
        sessionID: String?,
        rationale: String?
    ) throws -> String {
        guard let taskRepository else { throw TaskAutomationFeatureModelError.missingRepository }
        let task = try TaskCreationService(repository: taskRepository).createSessionStatusMessageTask(
            origin: .user,
            name: name,
            toStatus: toStatus,
            message: message,
            sessionID: sessionID,
            createdBySessionID: createdBySessionIDProvider(),
            rationale: rationale
        )
        reload()
        selectedTaskID = task.id
        return task.id
    }

    func stopTask(_ id: String) {
        do {
            _ = try taskRepository?.stopTask(id: id, reason: "Stopped from Task Management UI")
            reload()
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func restoreTask(_ id: String) {
        do {
            _ = try taskRepository?.restoreTask(id: id)
            reload()
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func deleteTask(_ id: String) {
        do {
            _ = try taskRepository?.deleteTask(id: id, reason: "Deleted from Task Management UI")
            reload()
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func beginScheduledTaskRun() -> Bool {
        guard !isRunningScheduledTasks, taskRepository != nil else { return false }
        isRunningScheduledTasks = true
        return true
    }

    func endScheduledTaskRun() {
        isRunningScheduledTasks = false
    }
}

enum TaskAutomationFeatureModelError: LocalizedError {
    case missingRepository

    var errorDescription: String? {
        switch self {
        case .missingRepository:
            "任务管理存储尚未初始化，请稍后重试。"
        }
    }
}
