import Foundation
import Testing
@testable import ConnorGraphCore

@Suite("Task Management Domain Tests")
struct TaskManagementDomainTests {
    @Test func triggerKindsOnlyIncludeScheduledAndEventTriggered() {
        #expect(ConnorTaskTriggerKind.allCases == [.scheduled, .eventTriggered])
    }

    @Test func defaultSystemTasksDescribeMailCalendarAndRSSChecks() {
        let defaults = ConnorTaskDefinition.systemDefaults(now: Date(timeIntervalSince1970: 0))

        let mail = defaults.first { $0.id == "system.mail.check-every-10-minutes" }
        let calendar = defaults.first { $0.id == "system.calendar.check-every-10-minutes" }
        let rss = defaults.first { $0.id == "system.rss.check-every-30-minutes" }

        #expect(mail?.origin == .system)
        #expect(mail?.trigger.kind == .scheduled)
        #expect(mail?.trigger.intervalSeconds == 600)
        #expect(mail?.target == ConnorTaskTarget(targetKind: "source.runtime", targetID: "mail", operationName: "check", parameters: [:]))
        #expect(mail?.metadata.isProtectedSystemTask == true)
        #expect(mail?.metadata.scope == .global)
        #expect(mail?.metadata.ownerSessionID == nil)
        #expect(mail?.metadata.isRecoverable == false)
        #expect(mail?.metadata.recoveryPolicy == ConnorTaskRecoveryPolicy.none)

        #expect(calendar?.origin == .system)
        #expect(calendar?.trigger.intervalSeconds == 600)
        #expect(calendar?.target.targetID == "calendar")
        #expect(calendar?.metadata.isProtectedSystemTask == true)

        #expect(rss?.origin == .system)
        #expect(rss?.trigger.intervalSeconds == 1_800)
        #expect(rss?.target.targetID == "rss")
        #expect(rss?.metadata.isProtectedSystemTask == true)
    }

    @Test func userAndAITasksRoundTripThroughCodable() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let task = ConnorTaskDefinition(
            id: "user.daily-summary",
            name: "Daily summary",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .eventTriggered, eventName: "session.status.changed", eventFilter: ["status": "done"]),
            target: ConnorTaskTarget(targetKind: "external.runtime", targetID: "summary", operationName: "create", parameters: ["scope": "session"]),
            lifecycle: ConnorTaskLifecycle(status: .active),
            metadata: ConnorTaskMetadata(createdBySessionID: "session-1", rationale: "Summarize completed work", tags: ["summary"]),
            createdAt: now,
            updatedAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(task)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConnorTaskDefinition.self, from: data)

        #expect(decoded == task)
        #expect(decoded.metadata.isProtectedSystemTask == false)
        #expect(decoded.metadata.userEditableFields.contains(.target))
    }

    @Test func sessionScopedTaskMetadataRoundTripsThroughCodable() throws {
        let metadata = ConnorTaskMetadata(
            createdBySessionID: "session-1",
            rationale: "Recover browser-assisted background work",
            tags: ["background", "session"],
            scope: .session,
            ownerSessionID: "session-1",
            isRecoverable: true,
            recoveryPolicy: .restoreIfInterrupted
        )
        let task = ConnorTaskDefinition(
            id: "session.session-1.background.task-1",
            name: "Recover background task",
            origin: .ai,
            trigger: ConnorTaskTrigger(kind: .eventTriggered, eventName: "session.background-task.created"),
            target: ConnorTaskTarget(targetKind: "session.background-runtime", targetID: "session-1", operationName: "browser.web-fetch"),
            lifecycle: ConnorTaskLifecycle(status: .stopped),
            metadata: metadata
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(task)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConnorTaskDefinition.self, from: data)

        #expect(decoded.metadata.scope == .session)
        #expect(decoded.metadata.ownerSessionID == "session-1")
        #expect(decoded.metadata.isRecoverable == true)
        #expect(decoded.metadata.recoveryPolicy == .restoreIfInterrupted)
    }

    @Test func legacyTaskMetadataDecodesWithGlobalScopeDefaults() throws {
        let json = """
        {
          "createdBySessionID": "session-legacy",
          "createdByDisplayName": null,
          "rationale": "legacy",
          "tags": ["legacy"],
          "isProtectedSystemTask": false,
          "userEditableFields": ["name", "trigger", "target", "tags", "rationale"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ConnorTaskMetadata.self, from: json)

        #expect(decoded.scope == .global)
        #expect(decoded.ownerSessionID == nil)
        #expect(decoded.isRecoverable == false)
        #expect(decoded.recoveryPolicy == ConnorTaskRecoveryPolicy.none)
    }

    @Test func recoveryPolicyOnlyContainsExpectedValues() {
        #expect(ConnorTaskRecoveryPolicy.allCases == [.none, .restoreIfInterrupted, .restoreIfQueuedOrRunning])
        #expect(ConnorTaskScope.allCases == [.global, .session])
    }
}
