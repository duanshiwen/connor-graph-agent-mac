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

@Test func sessionListByStatusReturnsStableCompletePages() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    for index in 0..<7 {
        var governance = AgentSessionGovernanceMetadata.default
        governance.status = index < 5 ? .done : .todo
        try repository.saveSession(AgentSession(
            id: "session-page-\(index)",
            title: "Session \(index)",
            createdAt: Date(timeIntervalSince1970: Double(index)),
            updatedAt: Date(timeIntervalSince1970: Double(index)),
            governance: governance
        ))
    }
    let tool = SessionListByStatusTool(repository: repository)
    let properties = try #require(tool.inputSchema.jsonObject["properties"] as? [String: Any])
    let pageSize = try #require(properties["pageSize"] as? [String: Any])
    #expect((pageSize["description"] as? String)?.contains("must remain unchanged") == true)
    var page = 1
    var collected: [String] = []

    while true {
        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "status": .string("done"),
                "page": .int(page),
                "pageSize": .int(2)
            ]),
            context: sessionStatusToolContext(sessionID: "session-page-0", toolCallID: "list-page-\(page)")
        )
        let object = try resultJSONObject(result)
        let sessions = try #require(object["sessions"] as? [[String: Any]])
        #expect(sessions.allSatisfy { $0["sessionID"] as? String != nil && $0["session_id"] == nil })
        let modelContent = AgentToolResultGate().gatedContent(for: result)
        #expect(modelContent.contains("\"sessions\""))
        #expect(modelContent.contains("\"sessionID\""))
        #expect(modelContent.contains("session-page-\(4 - collected.count)"))
        collected.append(contentsOf: sessions.compactMap { $0["sessionID"] as? String })
        #expect(object["totalItems"] as? Int == 5)
        #expect(object["totalPages"] as? Int == 3)
        if let nextPage = object["nextPage"] as? Int {
            #expect(object["hasNextPage"] as? Bool == true)
            page = nextPage
        } else {
            #expect(object["hasNextPage"] as? Bool == false)
            break
        }
    }

    #expect(collected == ["session-page-4", "session-page-3", "session-page-2", "session-page-1", "session-page-0"])
    #expect(Set(collected).count == collected.count)
}

@Test func sessionStatusListReturnsOperationReadyStatusField() async throws {
    let tool = SessionListStatusesTool(governanceConfig: .default)
    let result = try await tool.execute(
        arguments: AgentToolArguments(values: [:]),
        context: sessionStatusToolContext(sessionID: "session-status-list", toolCallID: "list-statuses")
    )
    let json = try #require(result.contentJSON)
    let statuses = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    #expect(statuses.allSatisfy { $0["status"] as? String == $0["id"] as? String })
    #expect(AgentToolResultGate().gatedContent(for: result) == json)
}

@Test func sessionBatchSetStatusReportsPartialSuccessConflictsAndIdempotency() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let baseline = Date(timeIntervalSince1970: 20_000)
    try repository.saveSession(AgentSession(id: "batch-update", title: "Update", updatedAt: baseline))
    var doneGovernance = AgentSessionGovernanceMetadata.default
    doneGovernance.status = .done
    try repository.saveSession(AgentSession(id: "batch-unchanged", title: "Unchanged", updatedAt: baseline, governance: doneGovernance))
    try repository.saveSession(AgentSession(id: "batch-conflict", title: "Conflict", updatedAt: baseline))
    let stale = ISO8601DateFormatter().string(from: baseline.addingTimeInterval(-60))
    let tool = SessionBatchSetStatusTool(repository: repository)

    let result = try await tool.execute(
        arguments: AgentToolArguments(json: """
        {
          "updates": [
            {"sessionID":"batch-update"},
            {"sessionID":"batch-update"},
            {"sessionID":"batch-unchanged"},
            {"sessionID":"batch-missing"},
            {"sessionID":"batch-conflict","expectedUpdatedAt":"\(stale)"}
          ],
          "status":"done",
          "reason":"Bulk completion"
        }
        """),
        context: sessionStatusToolContext(sessionID: "batch-update", toolCallID: "batch-set")
    )

    let object = try resultJSONObject(result)
    let items = try #require(object["results"] as? [[String: Any]])
    let modelContent = AgentToolResultGate().gatedContent(for: result)
    #expect(modelContent.contains("\"results\""))
    #expect(modelContent.contains("\"sessionID\":\"batch-update\""))
    let outcomes = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
        guard let id = item["sessionID"] as? String, let outcome = item["outcome"] as? String else { return nil }
        return (id, outcome)
    })
    #expect(object["updatedItems"] as? Int == 1)
    #expect(object["unchangedItems"] as? Int == 1)
    #expect(object["failedItems"] as? Int == 2)
    #expect(outcomes["batch-update"] == "updated")
    #expect(outcomes["batch-unchanged"] == "unchanged")
    #expect(outcomes["batch-missing"] == "not_found")
    #expect(outcomes["batch-conflict"] == "conflict")
    let updatedSession = try #require(try repository.loadSession(id: "batch-update"))
    #expect(updatedSession.governance.status == .done)
    #expect(updatedSession.updatedAt > baseline)
    #expect(try repository.loadSession(id: "batch-conflict")?.governance.status == .todo)

    let retry = try await tool.execute(
        arguments: AgentToolArguments(json: #"{"updates":[{"sessionID":"batch-update"}],"status":"done"}"#),
        context: sessionStatusToolContext(sessionID: "batch-update", toolCallID: "batch-retry")
    )
    let retryObject = try resultJSONObject(retry)
    #expect(retryObject["updatedItems"] as? Int == 0)
    #expect(retryObject["unchangedItems"] as? Int == 1)
}

@Test func sessionBatchSetStatusIsDeniedInReadOnlyModeWithoutMutations() async throws {
    let store = try SQLiteGraphKernelStore(path: temporarySessionStatusToolDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    try repository.saveSession(AgentSession(id: "batch-read-only"))
    var registry = AgentToolRegistry()
    registry.register(SessionBatchSetStatusTool(repository: repository))
    let context = AgentToolExecutionContext(
        runID: "run-read-only",
        sessionID: "batch-read-only",
        groupID: "default",
        userPrompt: "mark done",
        toolCallID: "batch-read-only-call",
        policyEngine: AgentPolicyEngine(permissionMode: .readOnly)
    )

    await #expect(throws: AgentToolError.self) {
        try await registry.execute(
            AgentToolCall(name: "session_batch_set_status", argumentsJSON: #"{"updates":[{"sessionID":"batch-read-only"}],"status":"done"}"#),
            context: context
        )
    }
    #expect(try repository.loadSession(id: "batch-read-only")?.governance.status == .todo)
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
