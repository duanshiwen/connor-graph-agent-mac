import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func sessionGetStatusToolReadsCurrentSessionStatus() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "session-status-read", title: "Status Read")
    try repository.saveSession(session)
    let tool = SessionGetStatusTool(repository: repository)

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{}"#),
        context: sessionStatusToolContext(sessionID: session.id, toolCallID: "get-status")
    )

    let object = try resultJSONObject(result)
    #expect(result.toolName == "session_get_status")
    #expect(object["sessionID"] as? String == session.id)
    #expect(object["status"] as? String == "todo")
    #expect(object["statusDisplayName"] as? String == "待办")
}

@Test func sessionSetStatusToolUpdatesCurrentSessionStatus() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "session-status-set", title: "Status Set")
    try repository.saveSession(session)
    let tool = SessionSetStatusTool(repository: repository)

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"status":"done","reason":"User asked to mark this complete"}"#),
        context: sessionStatusToolContext(sessionID: session.id, toolCallID: "set-status")
    )

    let loaded = try #require(try repository.loadSession(id: session.id))
    let object = try resultJSONObject(result)
    #expect(result.toolName == "session_set_status")
    #expect(loaded.governance.status == .done)
    #expect(object["status"] as? String == "done")
    #expect(object["previousStatus"] as? String == "todo")
}

@Test func sessionSetStatusToolRejectsUnsupportedStatus() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    try repository.saveSession(AgentSession(id: "session-status-invalid"))
    let tool = SessionSetStatusTool(repository: repository)

    await #expect(throws: AgentToolError.invalidArguments("Unsupported status 'complete'. Available status IDs: todo, in_progress, waiting, needs_review, blocked, done, cancelled, archived. Call session_list_statuses to get the current list.")) {
        try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"status":"complete"}"#),
            context: sessionStatusToolContext(sessionID: "session-status-invalid", toolCallID: "set-invalid")
        )
    }
}

private func temporarySessionStatusToolDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private func sessionStatusToolContext(sessionID: String, toolCallID: String) -> AgentToolExecutionContext {
    AgentToolExecutionContext(
        runID: "run-status-tool",
        sessionID: sessionID,
        groupID: "default",
        userPrompt: "status",
        toolCallID: toolCallID,
        policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
    )
}

private func resultJSONObject(_ result: AgentToolResult) throws -> [String: Any] {
    let contentJSON = try #require(result.contentJSON)
    return try #require(JSONSerialization.jsonObject(with: Data(contentJSON.utf8)) as? [String: Any])
}
