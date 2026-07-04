import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Target Runner Tests")
struct TaskTargetRunnerTests {
    @Test func runnerDispatchesSystemRefreshTargets() async throws {
        let mail = MailRefreshSpy()
        let calendar = CalendarRefreshSpy()
        let rss = RSSRefreshSpy()
        let runner = TaskTargetRunner(mailRefresher: mail.refresh, calendarRefresher: calendar.refresh, rssRefresher: rss.refresh, sessionMessenger: SessionMessageSpy().perform)
        let task = ConnorTaskDefinition(
            id: "system.calendar.account.calendar-account-a.refresh",
            name: "检查日历：Calendar A",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "calendar", operationName: "refresh", parameters: ["sourceInstanceID": "calendar-account-a"]),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem
        )

        _ = try await runner.run(task: task, runID: "run-")

        #expect(await mail.count == 0)
        #expect(await calendar.count == 1)
        #expect(await calendar.requests == [SourceRefreshTaskRequest(sourceKind: "calendar", sourceInstanceID: "calendar-account-a", runID: "run-")])
        #expect(await rss.count == 0)
    }

    @Test func appRuntimeDispatchesMailRefreshHandler() async throws {
        let mail = MailRefreshSpy()
        let runner = TaskTargetRunner.appRuntime(
            mailRefresh: mail.refresh,
            calendarRefresh: { _ in "calendar" },
            rssRefresh: { _ in "rss" },
            sessionMessage: { _ in "session" }
        )
        let task = ConnorTaskDefinition(
            id: "system.mail.account.mail-a.refresh",
            name: "检查邮件：Mail A",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 600, recurrence: .interval),
            target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "mail", operationName: "refresh", parameters: ["sourceInstanceID": "mail-a"]),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem
        )

        _ = try await runner.run(task: task, runID: "run-mail")

        #expect(await mail.count == 1)
        #expect(await mail.requests == [SourceRefreshTaskRequest(sourceKind: "mail", sourceInstanceID: "mail-a", runID: "run-mail")])
    }

    @Test func runnerPassesSourceInstanceIDToRSSRefreshHandler() async throws {
        let rss = RSSRefreshSpy()
        let runner = TaskTargetRunner(
            mailRefresher: { _ in "mail" },
            calendarRefresher: { _ in "calendar" },
            rssRefresher: rss.refresh,
            sessionMessenger: { _ in "session" }
        )
        let task = ConnorTaskDefinition(
            id: "system.rss.source.feed-a.refresh",
            name: "检查 RSS：Feed A",
            origin: .system,
            trigger: ConnorTaskTrigger(kind: .scheduled, intervalSeconds: 900, recurrence: .interval),
            target: ConnorTaskTarget(targetKind: "source.runtime", targetID: "rss", operationName: "refresh", parameters: ["sourceInstanceID": "feed-a"]),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: .protectedSystem
        )

        _ = try await runner.run(task: task, runID: "run-1")

        #expect(await rss.requests == [SourceRefreshTaskRequest(sourceKind: "rss", sourceInstanceID: "feed-a", runID: "run-1")])
    }

    @Test func runnerDispatchesSessionMessageTargets() async throws {
        let session = SessionMessageSpy()
        let runner = TaskTargetRunner(mailRefresher: { _ in "mail" }, calendarRefresher: { _ in "calendar" }, rssRefresher: { _ in "rss" }, sessionMessenger: session.perform)
        let send = ConnorTaskDefinition(
            id: "ai.done-followup",
            name: "Done followup",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .eventTriggered, eventName: ConnorTaskEventName.sessionStatusChanged, eventFilter: ["toStatus": "done"]),
            target: .sendMessageToSession(sessionID: "session-1", message: "Summarize"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(createdBySessionID: "session-1")
        )
        let create = ConnorTaskDefinition(
            id: "user.daily",
            name: "Daily",
            origin: .user,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: Date(timeIntervalSince1970: 0), recurrence: .daily),
            target: .createSessionAndSendMessage(message: "Plan today", title: "Daily Plan"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata()
        )

        let sendResult = try await runner.run(task: send, runID: "run-1", eventPayload: ["sessionID": "event-session"])
        let createResult = try await runner.run(task: create, runID: "run-2")
        let calls = await session.calls

        #expect(sendResult.summary.contains("session-1"))
        #expect(createResult.summary.contains("created session"))
        #expect(calls.map(\.message) == ["Summarize", "Plan today"])
        #expect(calls.map(\.title) == [nil, "Daily Plan"])
    }
}

private actor MailRefreshSpy { var count = 0; private(set) var requests: [SourceRefreshTaskRequest] = []; func refresh(_ request: SourceRefreshTaskRequest) async throws -> String { count += 1; requests.append(request); return "mail refreshed" } }
private actor CalendarRefreshSpy { var count = 0; private(set) var requests: [SourceRefreshTaskRequest] = []; func refresh(_ request: SourceRefreshTaskRequest) async throws -> String { count += 1; requests.append(request); return "calendar refreshed" } }
private actor RSSRefreshSpy { var count = 0; private(set) var requests: [SourceRefreshTaskRequest] = []; func refresh(_ request: SourceRefreshTaskRequest) async throws -> String { count += 1; requests.append(request); return "rss refreshed" } }

private actor SessionMessageSpy {
    struct Call: Equatable { var sessionID: String?; var title: String?; var message: String; var createNewSession: Bool }
    var calls: [Call] = []
    func perform(_ request: TaskSessionMessageRequest) async throws -> String {
        calls.append(Call(sessionID: request.sessionID, title: request.title, message: request.message, createNewSession: request.createNewSession))
        if request.createNewSession { return "created session for \(request.title ?? "untitled")" }
        return "sent message to \(request.sessionID ?? "unknown")"
    }
}
