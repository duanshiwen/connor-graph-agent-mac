import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func sessionListReturnsStableCompletePages() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    for index in 0..<7 {
        var governance = AgentSessionGovernanceMetadata.default
        try repository.saveSession(AgentSession(
            id: "session-page-\(index)",
            title: "Session \(index)",
            createdAt: Date(timeIntervalSince1970: Double(index)),
            updatedAt: Date(timeIntervalSince1970: Double(index)),
            governance: governance
        ))
    }
    let tool = SessionListTool(repository: repository)
    let properties = try #require(tool.inputSchema.jsonObject["properties"] as? [String: Any])
    let pageSize = try #require(properties["pageSize"] as? [String: Any])
    #expect((pageSize["description"] as? String)?.contains("must remain unchanged") == true)
    var page = 1
    var collected: [String] = []

    while true {
        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "page": .int(page),
                "pageSize": .int(2)
            ]),
            context: sessionStatusToolContext(sessionID: "session-page-0", toolCallID: "list-page-\(page)")
        )
        let object = try resultJSONObject(result)
        let sessions = try #require(object["sessions"] as? [[String: Any]])
        #expect(sessions.allSatisfy { $0["sessionID"] as? String != nil && $0["status"] == nil && $0["statusDisplayName"] == nil })
        let modelContent = AgentToolResultGate().gatedContent(for: result)
        #expect(modelContent.contains("\"sessions\""))
        #expect(modelContent.contains("\"sessionID\""))
        #expect(modelContent.contains("session-page-\(6 - collected.count)"))
        collected.append(contentsOf: sessions.compactMap { $0["sessionID"] as? String })
        #expect(object["totalItems"] as? Int == 7)
        #expect(object["totalPages"] as? Int == 4)
        if let nextPage = object["nextPage"] as? Int {
            #expect(object["hasNextPage"] as? Bool == true)
            page = nextPage
        } else {
            #expect(object["hasNextPage"] as? Bool == false)
            break
        }
    }

    #expect(collected == ["session-page-6", "session-page-5", "session-page-4", "session-page-3", "session-page-2", "session-page-1", "session-page-0"])
    #expect(Set(collected).count == collected.count)
}

@Test func sessionBatchDeleteToolDeletesSessionsAndReportsPartialResults() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    try repository.saveSession(AgentSession(id: "del-a", title: "Delete A"))
    try repository.saveSession(AgentSession(id: "del-current", title: "Current"))
    try repository.saveSession(AgentSession(id: "del-task", title: "Busy"))
    try repository.saveBackgroundTask(PersistedSessionBackgroundTask(
        id: "task-1",
        sessionID: "del-task",
        kind: "custom",
        title: "Running",
        detail: "",
        status: .running,
        createdAt: Date(),
        updatedAt: Date()
    ))
    let tool = SessionBatchDeleteTool(repository: repository)

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"sessionIDs":["del-a","del-current","del-missing","del-task"]}"#),
        context: sessionStatusToolContext(sessionID: "del-current", toolCallID: "batch-delete")
    )

    let object = try resultJSONObject(result)
    let items = try #require(object["results"] as? [[String: Any]])
    let outcomes = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
        guard let id = item["sessionID"] as? String, let outcome = item["outcome"] as? String else { return nil }
        return (id, outcome)
    })
    #expect(object["deletedItems"] as? Int == 1)
    #expect(object["failedItems"] as? Int == 3)
    #expect(outcomes["del-a"] == "deleted")
    #expect(outcomes["del-current"] == "failed")
    #expect(outcomes["del-missing"] == "not_found")
    #expect(outcomes["del-task"] == "running_tasks")
    #expect(try repository.loadSession(id: "del-a")?.governance.isDeleted == true)
    #expect(try repository.loadSession(id: "del-current")?.governance.isDeleted != true)
    #expect(try repository.loadSession(id: "del-task")?.governance.isDeleted != true)
}

@Test func sessionBatchDeleteToolRejectsEmptySessionIDs() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let tool = SessionBatchDeleteTool(repository: AppChatSessionRepository(store: store))

    await #expect(throws: AgentToolError.invalidArguments("sessionIDs must not be empty")) {
        try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"sessionIDs":[]}"#),
            context: sessionStatusToolContext(sessionID: "del-current", toolCallID: "batch-delete-empty")
        )
    }
}

@Test func sessionBatchDeleteIsDeniedInReadOnlyModeWithoutMutations() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    try repository.saveSession(AgentSession(id: "del-read-only"))
    var registry = AgentToolRegistry()
    registry.register(SessionBatchDeleteTool(repository: repository))
    let context = AgentToolExecutionContext(
        runID: "run-delete-ro",
        sessionID: "del-read-only",
        groupID: "default",
        userPrompt: "delete",
        toolCallID: "delete-ro-call",
        policyEngine: AgentPolicyEngine(permissionMode: .readOnly)
    )

    await #expect(throws: AgentToolError.self) {
        try await registry.execute(
            AgentToolCall(name: "session_batch_delete", argumentsJSON: #"{"sessionIDs":["del-read-only"]}"#),
            context: context
        )
    }
    #expect(try repository.loadSession(id: "del-read-only") != nil)
}

@Test func sessionBatchDeleteToolEnforcesPerCallLimit() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let tool = SessionBatchDeleteTool(repository: AppChatSessionRepository(store: store))
    let ids = (0..<51).map { "\"sess-\($0)\"" }.joined(separator: ",")

    await #expect(throws: AgentToolError.invalidArguments("sessionIDs accepts at most 50 items per call; delete in batches of at most 50 and continue until all selected sessions are handled.")) {
        try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"sessionIDs":["# + ids + #"]}"#),
            context: sessionStatusToolContext(sessionID: "del-current", toolCallID: "batch-delete-limit")
        )
    }
}

@Test func sessionBatchDeleteToolAllowsUpToLimitPerCall() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let ids = (0..<50).map { "batch-limit-\($0)" }
    for id in ids {
        try repository.saveSession(AgentSession(id: id, title: id))
    }
    let tool = SessionBatchDeleteTool(repository: repository)
    let jsonIDs = ids.map { "\"\($0)\"" }.joined(separator: ",")

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"sessionIDs":["# + jsonIDs + #"]}"#),
        context: sessionStatusToolContext(sessionID: "del-current", toolCallID: "batch-delete-50")
    )

    let object = try resultJSONObject(result)
    #expect(object["requestedItems"] as? Int == ids.count)
    #expect(object["deletedItems"] as? Int == ids.count)
    #expect(object["failedItems"] as? Int == 0)
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
