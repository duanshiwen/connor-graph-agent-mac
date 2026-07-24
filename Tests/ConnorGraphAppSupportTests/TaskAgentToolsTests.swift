import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Agent Tools Tests")
struct TaskAgentToolsTests {
    private struct ListPage: Decodable {
        var page: Int
        var pageSize: Int
        var totalItems: Int
        var totalPages: Int
        var hasNextPage: Bool
        var nextPage: Int?
        var tasks: [ConnorTaskDefinition]
    }

    @Test func aiToolCreatesScheduledTask() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let service = TaskCreationService(repository: repository)
        let tool = TaskCreateScheduledSessionMessageTool(service: service)

        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: """
            {"name":"Daily planning","runAt":"1970-01-01T00:01:40Z","recurrence":"daily","timezone":"Asia/Shanghai","message":"Plan today","title":"Daily Plan","rationale":"Daily planning"}
            """),
            context: AgentToolExecutionContext(runID: "run-1", sessionID: "session-1", groupID: "group-1", userPrompt: "create task", toolCallID: "tool-1", policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
        )
        let tasks = try repository.loadTasks()

        #expect(result.toolName == "tasks_create_scheduled_session_message")
        #expect(tasks.count == 1)
        #expect(tasks.first?.origin == .ai)
        #expect(tasks.first?.metadata.createdBySessionID == "session-1")
    }

    @Test func aiToolCreatesStatusTriggeredTask() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let service = TaskCreationService(repository: repository)
        let tool = TaskCreateSessionStatusMessageTool(service: service)

        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: """
            {"name":"Done summary","toStatus":"done","message":"Summarize","rationale":"Summarize done session"}
            """),
            context: AgentToolExecutionContext(runID: "run-1", sessionID: "session-1", groupID: "group-1", userPrompt: "create task", toolCallID: "tool-1", policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
        )
        let task = try #require(try repository.loadTasks().first)

        #expect(task.origin == .ai)
        #expect(task.trigger.eventFilter["toStatus"] == "done")
        #expect(task.target.parameters["message"] == "Summarize")
    }

    @Test func taskListReturnsEveryTaskOnceAcrossStablePages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let service = TaskCreationService(repository: repository)
        for index in 0..<5 {
            _ = try service.createScheduledSessionMessageTask(origin: .ai, name: "Task \(index)", runAt: Date(timeIntervalSince1970: Double(100 + index)), recurrence: .daily, timezoneIdentifier: nil, message: "Message \(index)")
        }
        let tool = TaskListTool(repository: repository)
        var page = 1
        var ids: [String] = []
        var reportedTotal = 0
        repeat {
            let result = try await tool.execute(arguments: try AgentToolArguments(json: "{\"page\":\(page),\"page_size\":2}"), context: taskContext())
            let json = try #require(result.contentJSON)
            let payload = try JSONDecoder.taskDecoder.decode(ListPage.self, from: Data(json.utf8))
            #expect(payload.page == page)
            #expect(payload.pageSize == 2)
            #expect(payload.totalPages == 3)
            #expect(payload.hasNextPage == (payload.nextPage != nil))
            ids.append(contentsOf: payload.tasks.map { $0.id })
            reportedTotal = payload.totalItems
            guard let next = payload.nextPage else { break }
            page = next
        } while true

        #expect(ids.count == reportedTotal)
        #expect(Set(ids).count == ids.count)
        let expectedIDs = try repository.loadTasks().sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }.map { $0.id }
        #expect(ids == expectedIDs)
    }

    @Test func scheduledTaskCanUpdateAllSupportedFields() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let original = try TaskCreationService(repository: repository).createScheduledSessionMessageTask(origin: .ai, name: "Old", runAt: Date(timeIntervalSince1970: 100), recurrence: .daily, timezoneIdentifier: "UTC", message: "Old message", title: "Old title")
        let expected = ISO8601DateFormatter().string(from: try #require(try repository.loadTask(id: original.id)).updatedAt)
        let tool = TaskUpdateScheduledSessionMessageTool(repository: repository)
        _ = try await tool.execute(arguments: try AgentToolArguments(json: """
        {"task_id":"\(original.id)","expected_updated_at":"\(expected)","name":"New","runAt":"1970-01-01T00:03:20Z","recurrence":"weekly","timezone":"Asia/Shanghai","message":"New message","title":"New title"}
        """), context: taskContext())
        let updated = try #require(try repository.loadTask(id: original.id))

        #expect(updated.name == "New")
        #expect(updated.trigger.runAt == Date(timeIntervalSince1970: 200))
        #expect(updated.trigger.recurrence == .weekly)
        #expect(updated.trigger.timezoneIdentifier == "Asia/Shanghai")
        #expect(updated.lifecycle.nextRunAt == Date(timeIntervalSince1970: 200))
        #expect(updated.target.parameters["message"] == "New message")
        #expect(updated.target.parameters["title"] == "New title")
    }

    @Test func updateRejectsConcurrentChangesAndUnsupportedTasks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let service = TaskCreationService(repository: repository)
        let original = try service.createScheduledSessionMessageTask(origin: .ai, name: "Original", runAt: Date(timeIntervalSince1970: 100), recurrence: .daily, timezoneIdentifier: nil, message: "Message")
        let stale = try #require(try repository.loadTask(id: original.id)).updatedAt
        var concurrent = try #require(try repository.loadTask(id: original.id))
        concurrent.name = "Concurrent"
        try repository.saveTask(concurrent)

        #expect(throws: AppTaskManagementError.taskVersionConflict(original.id)) {
            try repository.updateScheduledSessionMessageTask(id: original.id, expectedUpdatedAt: stale) { $0.name = "Overwrite" }
        }
        let statusTask = try service.createSessionStatusMessageTask(origin: .ai, name: "Status", toStatus: "done", message: "Summarize")
        #expect(throws: AppTaskManagementError.unsupportedScheduledSessionMessageTask(statusTask.id)) {
            try repository.updateScheduledSessionMessageTask(id: statusTask.id) { $0.name = "No" }
        }
        let system = try #require(try repository.loadOrCreateDefault().first { $0.metadata.isProtectedSystemTask })
        #expect(throws: AppTaskManagementError.cannotUpdateProtectedSystemTask(system.id)) {
            try repository.updateScheduledSessionMessageTask(id: system.id) { $0.name = "No" }
        }
    }

    @Test func deleteSoftDeletesAndHandlesMissingProtectedAndReadOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppTaskManagementRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let task = try TaskCreationService(repository: repository).createScheduledSessionMessageTask(origin: .ai, name: "Delete me", runAt: Date(timeIntervalSince1970: 100), recurrence: .once, timezoneIdentifier: nil, message: "Message")
        let tool = TaskDeleteTool(repository: repository)
        _ = try await tool.execute(arguments: try AgentToolArguments(json: "{\"task_id\":\"\(task.id)\"}"), context: taskContext())
        #expect(try repository.loadTasks().contains { $0.id == task.id } == false)
        #expect(try repository.loadTask(id: task.id)?.lifecycle.status == .deleted)

        await #expect(throws: AppTaskManagementError.taskNotFound("missing")) {
            try await tool.execute(arguments: try AgentToolArguments(json: "{\"task_id\":\"missing\"}"), context: taskContext())
        }
        let system = try #require(try repository.loadOrCreateDefault().first { $0.metadata.isProtectedSystemTask })
        await #expect(throws: AppTaskManagementError.cannotDeleteProtectedSystemTask(system.id)) {
            try await tool.execute(arguments: try AgentToolArguments(json: "{\"task_id\":\"\(system.id)\"}"), context: taskContext())
        }

        var registry = AgentToolRegistry()
        registry.registerTaskManagementTools(repository: repository)
        await #expect(throws: AgentToolError.self) {
            try await registry.execute(AgentToolCall(name: "tasks_delete", argumentsJSON: "{\"task_id\":\"\(system.id)\"}"), context: taskContext(permissionMode: .readOnly))
        }
    }
}

private extension JSONDecoder {
    static var taskDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private func taskContext(permissionMode: AgentPermissionMode = .allowAll) -> AgentToolExecutionContext {
    AgentToolExecutionContext(runID: "run-task", sessionID: "session-task", groupID: "group-task", userPrompt: "manage tasks", toolCallID: UUID().uuidString, policyEngine: AgentPolicyEngine(permissionMode: permissionMode))
}
