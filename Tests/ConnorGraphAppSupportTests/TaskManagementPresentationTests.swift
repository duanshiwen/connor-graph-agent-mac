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
        let presentation = TaskManagementUIPresentation.build(tasks: ConnorTaskDefinition.systemDefaults(now: now) + [eventTask], runHistory: [])

        #expect(presentation.scheduledTasks.count == 3)
        #expect(presentation.eventTriggeredTasks.map(\.id) == ["ai.watch-keyword"])
        #expect(presentation.summary.manualTaskCount == 0)
        #expect(presentation.summary.reviewControlCount == 0)
    }

    @Test func systemTaskCardDisablesDeleteAndExposesOpaqueTarget() throws {
        let task = try #require(ConnorTaskDefinition.systemDefaults(now: Date(timeIntervalSince1970: 0)).first { $0.id == "system.rss.check-every-30-minutes" })
        let presentation = TaskManagementUIPresentation.build(tasks: [task], runHistory: [])
        let card = try #require(presentation.cards.first)

        #expect(card.originBadge == "系统")
        #expect(card.triggerLabel == "定时")
        #expect(card.targetLabel == "source.runtime:rss.refresh")
        #expect(card.canDelete == false)
        #expect(card.deleteDisabledReason == "系统任务受保护")
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
        #expect(card.statusLabel == "failed")
        #expect(card.lastErrorLabel == "external runtime failed")
        #expect(card.rationaleLabel == "Daily summary")
        #expect(card.severity == .error)
    }
}
