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

@Test func graphKernelStorePersistsAgentSessionReadState() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    var readState = SessionReadState.initial(updatedAt: Date(timeIntervalSince1970: 1_000))
    readState.markUnread(
        messageID: "message-2",
        preview: "Assistant finished the work",
        level: .actionable,
        at: Date(timeIntervalSince1970: 2_000)
    )
    let session = AgentSession(
        id: "session-1",
        title: "Needs attention",
        messages: [],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 3_000),
        governance: .default,
        readState: readState
    )

    try store.upsertSession(session)
    let loaded = try #require(try store.session(id: "session-1"))

    #expect(loaded.readState == readState)
    #expect(loaded.readState.highestLevel == .actionable)
    #expect(loaded.readState.unreadCount == 1)
}

@Test func graphKernelStoreUpdatesSessionReadStateWithoutChangingUpdatedAt() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let originalUpdatedAt = Date(timeIntervalSince1970: 3_000)
    let session = AgentSession(
        id: "session-1",
        title: "Stable order",
        messages: [],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: originalUpdatedAt
    )
    try store.upsertSession(session)
    var readState = SessionReadState.initial(updatedAt: Date(timeIntervalSince1970: 4_000))
    readState.markUnread(messageID: "message-3", preview: "Preview", level: .interruptive, at: Date(timeIntervalSince1970: 4_000))

    try store.updateSessionReadState(sessionID: "session-1", readState: readState)
    let loaded = try #require(try store.session(id: "session-1"))

    #expect(loaded.readState == readState)
    #expect(loaded.updatedAt == originalUpdatedAt)
}

@Test func graphKernelStorePersistsNoteSessionKind() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    var governance = AgentSessionGovernanceMetadata.default
    governance.kind = .note
    let session = AgentSession(
        id: "note-session-1",
        title: "未命名的笔记",
        messages: [],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000),
        governance: governance
    )

    try store.upsertSession(session)
    let loaded = try #require(try store.session(id: "note-session-1"))

    #expect(loaded.governance.kind == .note)
    #expect(loaded.title == "未命名的笔记")
}

@Test func graphKernelStoreDefaultsChatSessionKind() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let session = AgentSession(
        id: "chat-session-1",
        title: "New Chat",
        messages: [],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )

    try store.upsertSession(session)
    let loaded = try #require(try store.session(id: "chat-session-1"))

    #expect(loaded.governance.kind == .chat)
}

@Test func graphKernelStorePersistsNoteSessionInRecentSessions() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    var governance = AgentSessionGovernanceMetadata.default
    governance.kind = .note
    let noteSession = AgentSession(
        id: "note-session-2",
        title: "Another Note",
        messages: [],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000),
        governance: governance
    )

    try store.upsertSession(noteSession)
    let allSessions = try store.recentSessions()
    let loaded = try #require(allSessions.first { $0.id == "note-session-2" })

    #expect(loaded.governance.kind == .note)
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
    let old = AgentSession(
        id: "session-old",
        title: "Old",
        messages: [AgentMessage(role: .user, content: "large transcript")],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )
    let new = AgentSession(id: "session-new", title: "New", createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 3_000))

    try store.upsertSession(old)
    try store.upsertSession(new)

    let sessions = try store.recentSessionMetadata(limit: 10)
    let messageCounts = try store.sessionMessageCounts()

    #expect(sessions.map(\.id) == ["session-new", "session-old"])
    #expect(sessions.allSatisfy { $0.messages.isEmpty })
    #expect(messageCounts == ["session-old": 1, "session-new": 0])
    #expect(try store.session(id: "session-old")?.messages.map(\.content) == ["large transcript"])
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

@Test func graphKernelStoreSoftDeletesSessionWithoutRemovingRecordsOrTasks() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    try store.upsertSession(AgentSession(id: "session-1", title: "One", createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000)))
    try store.upsertSession(AgentSession(id: "session-2", title: "Two", createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 2_000)))
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
    let deletedAt = Date(timeIntervalSince1970: 3_000)

    try store.deleteSession(id: "session-1", deletedAt: deletedAt)

    let deleted = try #require(try store.session(id: "session-1"))
    #expect(deleted.governance.deletedAt == deletedAt)
    #expect(try store.recentSessions(limit: 10).map(\.id) == ["session-2"])
    #expect(try store.recentSessions(limit: 10, includeDeleted: true).map(\.id) == ["session-1", "session-2"])
    #expect(try store.sessionBackgroundTasks(sessionID: "session-1").map(\.id) == ["task-1"])
    #expect(try store.sessionBackgroundTasks(sessionID: "session-2").map(\.id) == ["task-2"])
}
