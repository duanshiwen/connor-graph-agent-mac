import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Management Presentation Tests")
struct TaskManagementPresentationTests {
    @Test func presentationGroupsScheduledAndEventTriggeredTasks() {
        let now = Date(timeIntervalSince1970: 0)
        let eventTask = ConnorTaskDefinition(
            id: "ai.watch-keyword",
            name: "Watch keyword",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .eventTriggered, eventName: "rss.item.arrived", eventFilter: ["keyword": "Connor"]),
            target: ConnorTaskTarget(targetKind: "external.runtime", targetID: "rss", operationName: "watch"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(createdBySessionID: "session-1", rationale: "Track Connor news"),
            createdAt: now,
            updatedAt: now
        )
        let systemDefaults = ConnorTaskDefinition.systemDefaults(now: now)
        let presentation = TaskManagementUIPresentation.build(tasks: systemDefaults + [eventTask], runHistory: [])

        #expect(presentation.scheduledTasks.count == systemDefaults.count)
        #expect(presentation.eventTriggeredTasks.map(\.id) == ["ai.watch-keyword"])
        #expect(presentation.summary.manualTaskCount == 0)
        #expect(presentation.summary.reviewControlCount == 0)
    }

    @Test func systemTaskCardDisablesDeleteAndShowsLocalizedTarget() throws {
        let task = makeProtectedCalendarRefreshTask(accountID: "calendar-account-a")
        let presentation = TaskManagementUIPresentation.build(tasks: [task], runHistory: [])
        let card = try #require(presentation.cards.first)

        #expect(card.originBadge == "系统")
        #expect(card.triggerLabel == "定时")
        #expect(card.statusLabel == "已启用")
        #expect(card.targetLabel == "刷新日历账户")
        #expect(card.canStop == false)
        #expect(card.canRestore == false)
        #expect(card.canDelete == false)
        #expect(card.deleteDisabledReason == "系统任务受保护，不可暂停或删除")
        #expect(card.hasReviewControls == false)
        #expect(card.hasManualTaskControls == false)
    }

    @Test func userAndAITaskCardsCanDeleteAndShowRationale() throws {
        let userTask = ConnorTaskDefinition(
            id: "user.summary",
            name: "Summary",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 86_400),
            target: ConnorTaskTarget(targetKind: "external.runtime", targetID: "summary", operationName: "create"),
            lifecycle: ConnorTaskLifecycle(status: .failed, lastErrorMessage: "external runtime failed"),
            metadata: ConnorTaskMetadata(rationale: "Daily summary", tags: ["summary"])
        )
        let run = ConnorTaskRunRecord(taskID: "user.summary", status: .failed, startedAt: Date(timeIntervalSince1970: 1), outputSummary: "failed", errorMessage: "external runtime failed")
        let presentation = TaskManagementUIPresentation.build(tasks: [userTask], runHistory: [run])
        let card = try #require(presentation.cards.first)

        #expect(card.originBadge == "用户")
        #expect(card.canDelete)
        #expect(card.canStop)
        #expect(card.statusLabel == "失败")
        #expect(card.lastErrorLabel == "external runtime failed")
        #expect(card.rationaleLabel == "Daily summary")
        #expect(card.severity == .error)
    }

    @Test func presentationLocalizesKnownSystemTextAndTaskTargets() throws {
        let task = ConnorTaskDefinition(
            id: "system.rss.refresh",
            name: "检查 RSS",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled),
            target: ConnorTaskTarget(
                targetKind: "source.runtime",
                targetID: "rss",
                operationName: "refresh",
                parameters: ["sourceKind": "rss"]
            ),
            lifecycle: ConnorTaskLifecycle(
                status: .stopped,
                lastErrorMessage: "Previous process ended before the scheduled run reached a terminal state"
            ),
            metadata: ConnorTaskMetadata(rationale: "Materialized from RSS source fetch policy.")
        )

        let card = try #require(TaskManagementUIPresentation.build(tasks: [task], runHistory: []).cards.first)

        #expect(card.statusLabel == "已暂停")
        #expect(card.targetLabel == "刷新 RSS 订阅源")
        #expect(card.lastErrorLabel == "上次进程在定时任务完成前已结束。")
        #expect(card.rationaleLabel == "根据 RSS 订阅源刷新策略自动创建。")
    }

    private func makeProtectedCalendarRefreshTask(accountID: String) -> ConnorTaskDefinition {
        ConnorTaskDefinition(
            id: "system.calendar.account.\(accountID).refresh",
            name: "检查日历：Calendar A",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "calendar", operationName: "refresh", parameters: ["sourceKind": "calendar", "sourceInstanceID": accountID]),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem
        )
    }
}
