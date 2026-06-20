import Foundation
import ConnorGraphCore

public struct TaskManagementUISummary: Codable, Sendable, Equatable {
    public var totalTaskCount: Int
    public var scheduledTaskCount: Int
    public var eventTriggeredTaskCount: Int
    public var systemTaskCount: Int
    public var userTaskCount: Int
    public var aiTaskCount: Int
    public var stoppedTaskCount: Int
    public var failedTaskCount: Int
    public var manualTaskCount: Int
    public var reviewControlCount: Int

    public init(
        totalTaskCount: Int,
        scheduledTaskCount: Int,
        eventTriggeredTaskCount: Int,
        systemTaskCount: Int,
        userTaskCount: Int,
        aiTaskCount: Int,
        stoppedTaskCount: Int,
        failedTaskCount: Int,
        manualTaskCount: Int = 0,
        reviewControlCount: Int = 0
    ) {
        self.totalTaskCount = totalTaskCount
        self.scheduledTaskCount = scheduledTaskCount
        self.eventTriggeredTaskCount = eventTriggeredTaskCount
        self.systemTaskCount = systemTaskCount
        self.userTaskCount = userTaskCount
        self.aiTaskCount = aiTaskCount
        self.stoppedTaskCount = stoppedTaskCount
        self.failedTaskCount = failedTaskCount
        self.manualTaskCount = manualTaskCount
        self.reviewControlCount = reviewControlCount
    }
}

public struct TaskManagementUICard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var originBadge: String
    public var triggerLabel: String
    public var statusLabel: String
    public var targetLabel: String
    public var nextRunLabel: String
    public var lastRunLabel: String
    public var lastErrorLabel: String
    public var rationaleLabel: String
    public var canStop: Bool
    public var canRestore: Bool
    public var canDelete: Bool
    public var deleteDisabledReason: String?
    public var hasReviewControls: Bool
    public var hasManualTaskControls: Bool
    public var severity: AgentEventPresentationSeverity

    public init(
        id: String,
        title: String,
        originBadge: String,
        triggerLabel: String,
        statusLabel: String,
        targetLabel: String,
        nextRunLabel: String,
        lastRunLabel: String,
        lastErrorLabel: String,
        rationaleLabel: String,
        canStop: Bool,
        canRestore: Bool,
        canDelete: Bool,
        deleteDisabledReason: String?,
        hasReviewControls: Bool = false,
        hasManualTaskControls: Bool = false,
        severity: AgentEventPresentationSeverity
    ) {
        self.id = id
        self.title = title
        self.originBadge = originBadge
        self.triggerLabel = triggerLabel
        self.statusLabel = statusLabel
        self.targetLabel = targetLabel
        self.nextRunLabel = nextRunLabel
        self.lastRunLabel = lastRunLabel
        self.lastErrorLabel = lastErrorLabel
        self.rationaleLabel = rationaleLabel
        self.canStop = canStop
        self.canRestore = canRestore
        self.canDelete = canDelete
        self.deleteDisabledReason = deleteDisabledReason
        self.hasReviewControls = hasReviewControls
        self.hasManualTaskControls = hasManualTaskControls
        self.severity = severity
    }
}

public struct TaskManagementUIPresentation: Codable, Sendable, Equatable {
    public var summary: TaskManagementUISummary
    public var cards: [TaskManagementUICard]
    public var scheduledTasks: [TaskManagementUICard]
    public var eventTriggeredTasks: [TaskManagementUICard]

    public init(summary: TaskManagementUISummary, cards: [TaskManagementUICard]) {
        self.summary = summary
        self.cards = cards
        self.scheduledTasks = cards.filter { $0.triggerLabel == "定时" }
        self.eventTriggeredTasks = cards.filter { $0.triggerLabel == "事件触发" }
    }

    public static func build(tasks: [ConnorTaskDefinition], runHistory: [ConnorTaskRunRecord]) -> TaskManagementUIPresentation {
        let latestRunByTask = Dictionary(grouping: runHistory, by: \.taskID).compactMapValues { records in
            records.sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
                return (lhs.finishedAt ?? .distantPast) > (rhs.finishedAt ?? .distantPast)
            }.first
        }
        let visibleTasks = tasks.filter { $0.lifecycle.status != .deleted && !$0.isHiddenFromTaskManagementUI }
        let cards = visibleTasks
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { TaskManagementUICard(task: $0, latestRun: latestRunByTask[$0.id]) }
        return TaskManagementUIPresentation(
            summary: TaskManagementUISummary(
                totalTaskCount: cards.count,
                scheduledTaskCount: visibleTasks.filter { $0.trigger.kind == .scheduled }.count,
                eventTriggeredTaskCount: visibleTasks.filter { $0.trigger.kind == .eventTriggered }.count,
                systemTaskCount: visibleTasks.filter { $0.origin == .system }.count,
                userTaskCount: visibleTasks.filter { $0.origin == .user }.count,
                aiTaskCount: visibleTasks.filter { $0.origin == .ai }.count,
                stoppedTaskCount: visibleTasks.filter { $0.lifecycle.status == .stopped }.count,
                failedTaskCount: visibleTasks.filter { $0.lifecycle.status == .failed }.count
            ),
            cards: cards
        )
    }
}

private extension ConnorTaskDefinition {
    var isHiddenFromTaskManagementUI: Bool {
        target.targetKind == "media.transcription" && target.operationName == "run"
    }
}

private extension TaskManagementUICard {
    init(task: ConnorTaskDefinition, latestRun: ConnorTaskRunRecord?) {
        let protected = task.origin == .system && task.metadata.isProtectedSystemTask
        self.init(
            id: task.id,
            title: task.name,
            originBadge: task.origin.uiBadge,
            triggerLabel: task.trigger.kind.uiLabel,
            statusLabel: task.lifecycle.status.rawValue,
            targetLabel: "\(task.target.targetKind):\(task.target.targetID).\(task.target.operationName)",
            nextRunLabel: task.lifecycle.nextRunAt?.ISO8601Format() ?? "",
            lastRunLabel: latestRun?.startedAt.ISO8601Format() ?? task.lifecycle.lastRunAt?.ISO8601Format() ?? "",
            lastErrorLabel: latestRun?.errorMessage ?? task.lifecycle.lastErrorMessage ?? "",
            rationaleLabel: task.metadata.rationale ?? "",
            canStop: task.lifecycle.status != .stopped && task.lifecycle.status != .deleted,
            canRestore: task.lifecycle.status == .stopped,
            canDelete: !protected,
            deleteDisabledReason: protected ? "系统任务受保护" : nil,
            severity: task.lifecycle.status.taskUISeverity(latestRun: latestRun)
        )
    }
}

private extension ConnorTaskOrigin {
    var uiBadge: String {
        switch self {
        case .system: "系统"
        case .user: "用户"
        case .ai: "AI"
        }
    }
}

private extension ConnorTaskTriggerKind {
    var uiLabel: String {
        switch self {
        case .scheduled: "定时"
        case .eventTriggered: "事件触发"
        }
    }
}

private extension ConnorTaskLifecycleStatus {
    func taskUISeverity(latestRun: ConnorTaskRunRecord?) -> AgentEventPresentationSeverity {
        if latestRun?.status == .failed { return .error }
        return switch self {
        case .active, .succeeded: .success
        case .running: .info
        case .stopped: .warning
        case .failed: .error
        case .deleted: .warning
        }
    }
}
