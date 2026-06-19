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
}
