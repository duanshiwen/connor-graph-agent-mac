import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Task Agent Tools Tests")
struct TaskAgentToolsTests {
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
}
