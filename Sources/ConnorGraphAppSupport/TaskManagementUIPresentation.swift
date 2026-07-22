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
        let visibleTasks = tasks.filter { $0.lifecycle.status != .deleted }
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

private extension TaskManagementUICard {
    init(task: ConnorTaskDefinition, latestRun: ConnorTaskRunRecord?) {
        let protected = task.origin == .system && task.metadata.isProtectedSystemTask
        self.init(
            id: task.id,
            title: task.name,
            originBadge: task.origin.uiBadge,
            triggerLabel: task.trigger.kind.uiLabel,
            statusLabel: task.lifecycle.status.uiLabel,
            targetLabel: task.target.uiLabel,
            nextRunLabel: task.lifecycle.nextRunAt?.taskManagementLocalDateTimeLabel ?? "",
            lastRunLabel: latestRun?.startedAt.taskManagementLocalDateTimeLabel ?? task.lifecycle.lastRunAt?.taskManagementLocalDateTimeLabel ?? "",
            lastErrorLabel: (latestRun?.errorMessage ?? task.lifecycle.lastErrorMessage ?? "").localizedTaskManagementSystemText,
            rationaleLabel: (task.metadata.rationale ?? "").localizedTaskManagementSystemText,
            canStop: !protected && task.lifecycle.status != .stopped && task.lifecycle.status != .deleted,
            canRestore: !protected && task.lifecycle.status == .stopped,
            canDelete: !protected,
            deleteDisabledReason: protected ? "系统任务受保护，不可暂停或删除" : nil,
            severity: task.lifecycle.status.taskUISeverity(latestRun: latestRun)
        )
    }
}

private extension Date {
    var taskManagementLocalDateTimeLabel: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: self)
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
    var uiLabel: String {
        switch self {
        case .active: "已启用"
        case .stopped: "已暂停"
        case .running: "运行中"
        case .succeeded: "已完成"
        case .failed: "失败"
        case .deleted: "已删除"
        }
    }

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

private extension ConnorTaskTarget {
    var uiLabel: String {
        switch (targetKind, operationName) {
        case ("source.runtime", "refresh"):
            switch parameters["sourceKind"] ?? targetID {
            case "rss": "刷新 RSS 订阅源"
            case "mail": "刷新邮件账户"
            case "calendar": "刷新日历账户"
            default: "刷新数据源"
            }
        case ("memory_os.pipeline", "plan_l1_unified_projection_jobs"):
            "规划 Memory OS L1 知识提升"
        case ("session.ai", "createSessionAndSendMessage"):
            "新建会话并发送消息"
        case ("session.ai", "sendMessage"):
            targetID.isEmpty ? "向当前会话发送消息" : "向指定会话发送消息"
        case ("session.background-runtime", _):
            "执行会话后台任务"
        default:
            targetID.isEmpty ? "执行自定义任务" : "自定义目标：\(targetID)"
        }
    }
}

private extension String {
    var localizedTaskManagementSystemText: String {
        switch self {
        case "Materialized from RSS source fetch policy.":
            "根据 RSS 订阅源刷新策略自动创建。"
        case "Materialized from configured mail account.":
            "根据已配置的邮件账户自动创建。"
        case "Materialized from configured calendar account.":
            "根据已配置的日历账户自动创建。"
        case "Scheduled task runner was cancelled":
            "定时任务运行已取消。"
        case "Previous process ended before the scheduled run reached a terminal state":
            "上次进程在定时任务完成前已结束。"
        default:
            self
        }
    }
}
