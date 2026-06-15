import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryChatDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphKernelStoreSavesAndLoadsAgentSession() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let session = AgentSession(
        id: "session-1",
        title: "Graph memory",
        messages: [],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )

    try store.upsertSession(session)
    let loaded = try #require(try store.session(id: "session-1"))

    #expect(loaded.id == "session-1")
    #expect(loaded.title == "Graph memory")
    #expect(loaded.createdAt == Date(timeIntervalSince1970: 1_000))
    #expect(loaded.updatedAt == Date(timeIntervalSince1970: 2_000))
    #expect(loaded.messages.isEmpty)
}

@Test func graphKernelStorePersistsAgentSessionMessagesInOrder() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let user = AgentMessage(id: "message-1", role: .user, content: "What is memory?", createdAt: Date(timeIntervalSince1970: 1_000))
    let assistant = AgentMessage(
        id: "message-2",
        role: .assistant,
        content: "Graph memory.",
        createdAt: Date(timeIntervalSince1970: 2_000),
        citations: ["entity:memory"],
        contextSnapshot: "Entity[work_object] Memory"
    )
    let session = AgentSession(id: "session-1", title: "Graph memory", messages: [user, assistant])

    try store.upsertSession(session)

    let loaded = try #require(try store.session(id: session.id))
    #expect(loaded.messages.map(\.id) == ["message-1", "message-2"])
    #expect(loaded.messages[1].citations == ["entity:memory"])
    #expect(loaded.messages[1].contextSnapshot == "Entity[work_object] Memory")
}

@Test func graphKernelStorePersistsPromptInspectionSnapshotOnAgentSessionMessage() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let snapshot = AgentPromptInspectionSnapshot(
        includesSummary: true,
        recentMessageCount: 2,
        currentRequest: "What next?",
        renderedPrompt: "Rendered prompt",
        renderedPromptCharacterCount: 15,
        estimatedPromptTokenCount: 4,
        promptBudgetStatus: .warning
    )
    let assistant = AgentMessage(
        id: "message-1",
        role: .assistant,
        content: "Answer",
        createdAt: Date(timeIntervalSince1970: 1_000),
        promptInspection: snapshot
    )
    let session = AgentSession(id: "session-1", title: "Graph memory", messages: [assistant])

    try store.upsertSession(session)

    let loaded = try #require(try store.session(id: session.id)?.messages.first)
    #expect(loaded.promptInspection == snapshot)
}

@Test func graphKernelStoreLoadsRecentAgentSessionsByUpdatedAt() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let old = AgentSession(id: "session-old", title: "Old", createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
    let new = AgentSession(id: "session-new", title: "New", createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 3_000))

    try store.upsertSession(old)
    try store.upsertSession(new)

    let sessions = try store.recentSessions(limit: 10)

    #expect(sessions.map(\.id) == ["session-new", "session-old"])
    #expect(sessions.allSatisfy { $0.messages.isEmpty })
}

@Test func graphKernelStoreLoadsRecentSessionListItemsWithoutDecodingMessages() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let old = AgentSession(
        id: "session-old",
        title: "Old",
        messages: [AgentMessage(id: "old-message", role: .user, content: "old", createdAt: Date(timeIntervalSince1970: 1_000))],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )
    let new = AgentSession(
        id: "session-new",
        title: "New",
        messages: [
            AgentMessage(id: "new-message-1", role: .user, content: "new", createdAt: Date(timeIntervalSince1970: 2_000)),
            AgentMessage(id: "new-message-2", role: .assistant, content: "answer", createdAt: Date(timeIntervalSince1970: 2_100))
        ],
        createdAt: Date(timeIntervalSince1970: 2_000),
        updatedAt: Date(timeIntervalSince1970: 3_000),
        governance: AgentSessionGovernanceMetadata(status: .inProgress, labels: [AgentSessionLabel(id: "project", value: "connor")], isArchived: false, isFlagged: true)
    )

    try store.upsertSession(old)
    try store.upsertSession(new)

    let items = try store.recentSessionListItems(limit: 10)

    #expect(items.map(\.id) == ["session-new", "session-old"])
    #expect(items.first?.messageCount == 2)
    #expect(items.first?.governance.status == .inProgress)
    #expect(items.first?.governance.labels == [AgentSessionLabel(id: "project", value: "connor")])
    #expect(items.first?.governance.isFlagged == true)
}

@Test func graphKernelStoreMigratesAgentSessionsTable() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("agent_sessions"))
}

@Test func graphKernelStoreMigratesSessionBackgroundTasksTable() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()
    let indexes = try store.indexNames()

    #expect(tables.contains("session_background_tasks"))
    #expect(indexes.contains("idx_session_background_tasks_session"))
    #expect(indexes.contains("idx_session_background_tasks_status"))
}

@Test func graphKernelStorePersistsSessionBackgroundTasksIsolatedBySession() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let task1 = PersistedSessionBackgroundTask(
        id: "task-1",
        sessionID: "session-1",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "生成中",
        status: .running,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_001),
        errorMessage: nil,
        payloadJSON: "{}"
    )
    let task2 = PersistedSessionBackgroundTask(
        id: "task-2",
        sessionID: "session-2",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "另一个会话",
        status: .queued,
        createdAt: Date(timeIntervalSince1970: 2_000),
        updatedAt: Date(timeIntervalSince1970: 2_001),
        errorMessage: nil,
        payloadJSON: "{}"
    )

    try store.upsertSessionBackgroundTask(task1)
    try store.upsertSessionBackgroundTask(task2)

    let session1Tasks = try store.sessionBackgroundTasks(sessionID: "session-1")
    let session2Tasks = try store.sessionBackgroundTasks(sessionID: "session-2")

    #expect(session1Tasks.map(\.id) == ["task-1"])
    #expect(session2Tasks.map(\.id) == ["task-2"])
}

@Test func graphKernelStoreUpdatesSessionBackgroundTaskWithoutDuplicating() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    var task = PersistedSessionBackgroundTask(
        id: "task-1",
        sessionID: "session-1",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "生成中",
        status: .running,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_001),
        errorMessage: nil,
        payloadJSON: "{}"
    )

    try store.upsertSessionBackgroundTask(task)
    task.status = .succeeded
    task.detail = "已更新为：新标题"
    task.updatedAt = Date(timeIntervalSince1970: 1_100)
    try store.upsertSessionBackgroundTask(task)

    let tasks = try store.sessionBackgroundTasks(sessionID: "session-1")

    #expect(tasks.count == 1)
    #expect(tasks.first?.status == .succeeded)
    #expect(tasks.first?.detail == "已更新为：新标题")
}

@Test func graphKernelStoreDeletesBackgroundTasksWhenDeletingSession() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    try store.upsertSession(AgentSession(id: "session-1", title: "One"))
    try store.upsertSession(AgentSession(id: "session-2", title: "Two"))
    try store.upsertSessionBackgroundTask(PersistedSessionBackgroundTask(
        id: "task-1",
        sessionID: "session-1",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "生成中",
        status: .running,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_001),
        errorMessage: nil,
        payloadJSON: "{}"
    ))
    try store.upsertSessionBackgroundTask(PersistedSessionBackgroundTask(
        id: "task-2",
        sessionID: "session-2",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "另一个会话",
        status: .queued,
        createdAt: Date(timeIntervalSince1970: 2_000),
        updatedAt: Date(timeIntervalSince1970: 2_001),
        errorMessage: nil,
        payloadJSON: "{}"
    ))

    try store.deleteSession(id: "session-1")

    #expect(try store.sessionBackgroundTasks(sessionID: "session-1").isEmpty)
    #expect(try store.sessionBackgroundTasks(sessionID: "session-2").map(\.id) == ["task-2"])
}
