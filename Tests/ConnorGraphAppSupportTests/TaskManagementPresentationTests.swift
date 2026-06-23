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

    @Test func presentationHidesMediaTranscriptionBackgroundTasksFromScheduledList() {
        let now = Date(timeIntervalSince1970: 0)
        let mediaTask = ConnorTaskDefinition(
            id: "media.transcription.media-job-1",
            name: "转写媒体：Example",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: now, recurrence: .once),
            target: .mediaTranscriptionRun(jobID: "media-job-1", ownerSessionID: "session-1"),
            lifecycle: ConnorTaskLifecycle(status: .active, nextRunAt: now),
            metadata: ConnorTaskMetadata(
                createdBySessionID: "session-1",
                rationale: "Transcribe browser media into a session-owned attachment",
                tags: ["media", "transcription", "browser"],
                scope: .global,
                ownerSessionID: "session-1",
                isRecoverable: true,
                recoveryPolicy: .restoreIfQueuedOrRunning
            ),
            createdAt: now,
            updatedAt: now
        )

        let systemDefaults = ConnorTaskDefinition.systemDefaults(now: now)
        let presentation = TaskManagementUIPresentation.build(tasks: systemDefaults + [mediaTask], runHistory: [])

        #expect(!presentation.cards.contains { $0.id == mediaTask.id })
        #expect(!presentation.scheduledTasks.contains { $0.id == mediaTask.id })
        #expect(presentation.scheduledTasks.count == systemDefaults.count)
        #expect(presentation.summary.scheduledTaskCount == systemDefaults.count)
        #expect(presentation.summary.totalTaskCount == systemDefaults.count)
    }

    @Test func systemTaskCardDisablesDeleteAndExposesOpaqueTarget() throws {
        let task = makeProtectedCalendarRefreshTask(accountID: "calendar-account-a")
        let presentation = TaskManagementUIPresentation.build(tasks: [task], runHistory: [])
        let card = try #require(presentation.cards.first)

        #expect(card.originBadge == "系统")
        #expect(card.triggerLabel == "定时")
        #expect(card.targetLabel == "source.runtime:calendar.refresh")
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
        #expect(card.statusLabel == "failed")
        #expect(card.lastErrorLabel == "external runtime failed")
        #expect(card.rationaleLabel == "Daily summary")
        #expect(card.severity == .error)
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
