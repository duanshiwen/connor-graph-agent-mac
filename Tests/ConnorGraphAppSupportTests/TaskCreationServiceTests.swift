import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Creation Service Tests")
struct TaskCreationServiceTests {
    @Test func createsScheduledSessionMessageTaskForAI() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let service = TaskCreationService(repository: repository)

        let task = try service.createScheduledSessionMessageTask(
            origin: .ai,
            name: "Daily planning",
            runAt: Date(timeIntervalSince1970: 100),
            recurrence: .daily,
            timezoneIdentifier: "Asia/Shanghai",
            message: "Plan today",
            title: "Daily Plan",
            createdBySessionID: "session-1",
            rationale: "Daily planning"
        )

        #expect(task.origin == .ai)
        #expect(task.trigger.kind == .scheduled)
        #expect(task.trigger.recurrence == .daily)
        #expect(task.target == .createSessionAndSendMessage(message: "Plan today", title: "Daily Plan"))
        #expect(task.metadata.createdBySessionID == "session-1")
        #expect(try repository.loadTask(id: task.id) != nil)
    }

    @Test func createsSessionStatusMessageTaskForUser() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let service = TaskCreationService(repository: repository)

        let task = try service.createSessionStatusMessageTask(
            origin: .user,
            name: "Done summary",
            toStatus: "done",
            message: "Summarize this done session",
            sessionID: nil,
            createdBySessionID: nil,
            rationale: "Summarize done work"
        )

        #expect(task.origin == .user)
        #expect(task.trigger.eventName == ConnorTaskEventName.sessionStatusChanged)
        #expect(task.trigger.eventFilter == ["toStatus": "done"])
        #expect(task.target == .sendMessageToSession(message: "Summarize this done session"))
        #expect(try repository.loadTask(id: task.id) != nil)
    }

    @Test func rejectsSystemOriginAndInvalidRecurrenceForUserCreatableTasks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let service = TaskCreationService(repository: repository)

        #expect(throws: TaskCreationServiceError.self) {
            try service.createScheduledSessionMessageTask(origin: .system, name: "Bad", runAt: Date(), recurrence: .daily, timezoneIdentifier: nil, message: "Bad")
        }
        #expect(throws: ConnorTaskValidationError.self) {
            try service.createScheduledSessionMessageTask(origin: .ai, name: "Bad interval", runAt: Date(), recurrence: .interval, timezoneIdentifier: nil, message: "Bad")
        }
    }
}
