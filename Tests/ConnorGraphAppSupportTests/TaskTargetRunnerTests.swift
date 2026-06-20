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
        let tasks = ConnorTaskDefinition.systemDefaults(now: Date(timeIntervalSince1970: 0))

        for task in tasks {
            _ = try await runner.run(task: task, runID: "run-")
        }

        #expect(await mail.count == 1)
        #expect(await calendar.count == 1)
        #expect(await rss.count == 1)
    }

    @Test func runnerDispatchesMediaTranscriptionTargets() async throws {
        let media = MediaTranscriptionSpy()
        let runner = TaskTargetRunner(
            mailRefresher: { _ in "mail" },
            calendarRefresher: { _ in "calendar" },
            rssRefresher: { _ in "rss" },
            sessionMessenger: { _ in "session" },
            mediaTranscriptionRunner: media.perform
        )
        let task = ConnorTaskDefinition(
            id: "media.job-1",
            name: "Transcribe media",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .scheduled, runAt: Date(timeIntervalSince1970: 0), recurrence: .once),
            target: .mediaTranscriptionRun(jobID: "job-1", ownerSessionID: "session-1"),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(scope: .global, ownerSessionID: "session-1", isRecoverable: true, recoveryPolicy: .restoreIfQueuedOrRunning)
        )

        let result = try await runner.run(task: task, runID: "run-1")
        let calls = await media.calls

        #expect(result.summary == "media job-1 for session-1")
        #expect(calls == [MediaTranscriptionTaskRequest(jobID: "job-1", ownerSessionID: "session-1", runID: "run-1")])
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

private actor MailRefreshSpy { var count = 0; func refresh(_ request: SourceRefreshTaskRequest) async throws -> String { count += 1; return "mail refreshed" } }
private actor CalendarRefreshSpy { var count = 0; func refresh(_ request: SourceRefreshTaskRequest) async throws -> String { count += 1; return "calendar refreshed" } }
private actor RSSRefreshSpy { var count = 0; private(set) var requests: [SourceRefreshTaskRequest] = []; func refresh(_ request: SourceRefreshTaskRequest) async throws -> String { count += 1; requests.append(request); return "rss refreshed" } }

private actor MediaTranscriptionSpy {
    var calls: [MediaTranscriptionTaskRequest] = []
    func perform(_ request: MediaTranscriptionTaskRequest) async throws -> String {
        calls.append(request)
        return "media \(request.jobID) for \(request.ownerSessionID)"
    }
}

private actor SessionMessageSpy {
    struct Call: Equatable { var sessionID: String?; var title: String?; var message: String; var createNewSession: Bool }
    var calls: [Call] = []
    func perform(_ request: TaskSessionMessageRequest) async throws -> String {
        calls.append(Call(sessionID: request.sessionID, title: request.title, message: request.message, createNewSession: request.createNewSession))
        if request.createNewSession { return "created session for \(request.title ?? "untitled")" }
        return "sent message to \(request.sessionID ?? "unknown")"
    }
}
