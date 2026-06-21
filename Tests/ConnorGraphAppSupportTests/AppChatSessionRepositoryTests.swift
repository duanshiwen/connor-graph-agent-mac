import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

private func temporaryAppChatDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private func temporaryAppChatStoragePaths(_ name: String = UUID().uuidString) -> AppStoragePaths {
    AppStoragePaths(applicationSupportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true))
}

@Test func appChatRepositoryPersistsMarkdownRenderCacheForSavedAssistantMessages() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let paths = temporaryAppChatStoragePaths()
    let repository = AppChatSessionRepository(store: store, storagePaths: paths)
    let user = AgentMessage(id: "user-1", role: .user, content: "Question")
    let assistant = AgentMessage(id: "assistant-1", role: .assistant, content: "# Answer\n\nBody with **markdown**")
    let session = AgentSession(id: "session-cache", messages: [user, assistant])

    try repository.saveSession(session, previousMessageCount: 1)

    let cacheStore = AgentMarkdownRenderCacheStore(storagePaths: paths)
    let cachedBlocks = try cacheStore.loadBlocks(sessionID: session.id, messageID: assistant.id, content: assistant.content)
    #expect(cachedBlocks == AgentMarkdownBlockParser().parse(assistant.content))
    #expect(try cacheStore.loadBlocks(sessionID: session.id, messageID: user.id, content: user.content) == nil)
}

@Test func appChatRepositoryUpdatesSessionReadState() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let updatedAt = Date(timeIntervalSince1970: 2_000)
    let session = AgentSession(id: "session-read-state", title: "Read State", updatedAt: updatedAt)
    try repository.saveSession(session)
    var readState = SessionReadState.initial(updatedAt: Date(timeIntervalSince1970: 3_000))
    readState.markUnread(messageID: "assistant-1", preview: "Done", level: .actionable, at: Date(timeIntervalSince1970: 3_000))

    let updated = try repository.updateReadState(sessionID: session.id, readState: readState)
    let loaded = try #require(try repository.loadSession(id: session.id))

    #expect(updated.readState == readState)
    #expect(loaded.readState == readState)
    #expect(loaded.updatedAt == updatedAt)
}

@Test func appChatRepositoryPersistsBackgroundTasksIsolatedBySession() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let task1 = PersistedSessionBackgroundTask(
        id: "task-1",
        sessionID: "session-1",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "生成中",
        status: .running,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_001),
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
        payloadJSON: "{}"
    )

    try repository.saveBackgroundTask(task1)
    try repository.saveBackgroundTask(task2)

    #expect(try repository.loadBackgroundTasks(sessionID: "session-1").map(\.id) == ["task-1"])
    #expect(try repository.loadBackgroundTasks(sessionID: "session-2").map(\.id) == ["task-2"])
}

@Test func appChatRepositoryUpdatesBackgroundTaskBySessionAndTaskID() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    try repository.saveBackgroundTask(PersistedSessionBackgroundTask(
        id: "task-1",
        sessionID: "session-1",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "生成中",
        status: .running,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_001),
        payloadJSON: "{}"
    ))

    try repository.updateBackgroundTask(
        sessionID: "session-1",
        taskID: "task-1",
        status: .failed,
        detail: "生成失败",
        errorMessage: "LLM unavailable",
        updatedAt: Date(timeIntervalSince1970: 1_100)
    )

    let task = try #require(try repository.loadBackgroundTasks(sessionID: "session-1").first)
    #expect(task.status == .failed)
    #expect(task.detail == "生成失败")
    #expect(task.errorMessage == "LLM unavailable")
    #expect(task.updatedAt == Date(timeIntervalSince1970: 1_100))
}

@Test func appChatRepositoryRejectsDeletingSessionWithRunningBackgroundTasks() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    try repository.saveSession(AgentSession(id: "session-1", title: "One"))
    try repository.saveBackgroundTask(PersistedSessionBackgroundTask(
        id: "task-running",
        sessionID: "session-1",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "生成中",
        status: .running,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_001),
        payloadJSON: "{}"
    ))

    #expect(throws: AppChatSessionRepositoryError.sessionHasRunningBackgroundTasks("session-1")) {
        try repository.deleteSession(sessionID: "session-1")
    }
    let session = try #require(try repository.loadSession(id: "session-1"))
    #expect(!session.governance.isDeleted)
}

@Test func appChatRepositorySoftDeletesSessionWithoutRemovingRecordsOrTasks() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    try repository.saveSession(AgentSession(id: "session-1", title: "One"))
    try repository.saveSession(AgentSession(id: "session-2", title: "Two"))
    try repository.saveBackgroundTask(PersistedSessionBackgroundTask(
        id: "task-1",
        sessionID: "session-1",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "生成中",
        status: .succeeded,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_001),
        payloadJSON: "{}"
    ))
    try repository.saveBackgroundTask(PersistedSessionBackgroundTask(
        id: "task-2",
        sessionID: "session-2",
        kind: "title_generation",
        title: "重新生成会话标题",
        detail: "另一个会话",
        status: .queued,
        createdAt: Date(timeIntervalSince1970: 2_000),
        updatedAt: Date(timeIntervalSince1970: 2_001),
        payloadJSON: "{}"
    ))

    try repository.deleteSession(sessionID: "session-1")

    let deleted = try #require(try repository.loadSession(id: "session-1"))
    #expect(deleted.governance.isDeleted)
    #expect(try repository.loadSessions(filter: .all).map(\.id) == ["session-2"])
    #expect(try repository.loadBackgroundTasks(sessionID: "session-1").map(\.id) == ["task-1"])
    #expect(try repository.loadBackgroundTasks(sessionID: "session-2").map(\.id) == ["task-2"])
}

@Test func appChatRepositoryCreatesFirstSession() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let now = Date(timeIntervalSince1970: 1_000)

    let session = try repository.createSession(now: now)
    let loaded = try #require(try repository.loadSession(id: session.id))

    #expect(loaded.title == "新对话")
    #expect(loaded.createdAt == now)
    #expect(loaded.updatedAt == now)
}

@Test func appChatRepositoryLoadsRecentSessions() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let old = AgentSession(id: "old", title: "Old", createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
    let new = AgentSession(id: "new", title: "New", createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 3_000))
    try repository.saveSession(old)
    try repository.saveSession(new)

    let sessions = try repository.loadRecentSessions(limit: 10)

    #expect(sessions.map(\.id) == ["new", "old"])
}

@Test func appChatRepositorySavesNativeSessionTurn() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let originalSession = AgentSession(id: "session-1", title: "New Chat", createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
    try repository.saveSession(originalSession)
    let user = AgentMessage(id: "user-1", role: .user, content: "memory", createdAt: Date(timeIntervalSince1970: 2_000))
    let assistant = AgentMessage(
        id: "assistant-1",
        role: .assistant,
        content: "Use graph memory.",
        createdAt: Date(timeIntervalSince1970: 3_000),
        citations: ["node:memory"],
        contextSnapshot: "Node[work_object] Memory"
    )
    let responseSession = AgentSession(
        id: "session-1",
        title: "memory",
        messages: [user, assistant],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 3_000)
    )
    let saved = try repository.saveSession(responseSession)
    let loaded = try #require(try repository.loadSession(id: "session-1"))

    #expect(saved.id == "session-1")
    #expect(loaded.messages.map(\.id) == ["user-1", "assistant-1"])
    #expect(loaded.messages[1].citations == ["node:memory"])
}

@Test func appChatRepositoryPreservesEarlierMessagesWhenSavingSecondTurn() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let originalSession = AgentSession(id: "session-1", title: "New Chat", createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
    try repository.saveSession(originalSession)

    let user1 = AgentMessage(id: "user-1", role: .user, content: "你好", createdAt: Date(timeIntervalSince1970: 2_000))
    let assistant1 = AgentMessage(id: "assistant-1", role: .assistant, content: "你好！", createdAt: Date(timeIntervalSince1970: 3_000))
    let firstSession = AgentSession(
        id: "session-1",
        title: "你好",
        messages: [user1, assistant1],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 3_000)
    )
    try repository.saveSession(firstSession)

    let user2 = AgentMessage(id: "user-2", role: .user, content: "我们会说些什么呢？", createdAt: Date(timeIntervalSince1970: 4_000))
    let assistant2 = AgentMessage(id: "assistant-2", role: .assistant, content: "我们可以聊图谱。", createdAt: Date(timeIntervalSince1970: 5_000))
    let secondSession = AgentSession(
        id: "session-1",
        title: "你好",
        messages: [user1, assistant1, user2, assistant2],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 5_000)
    )

    try repository.saveSession(secondSession)

    let loaded = try #require(try repository.loadSession(id: "session-1"))

    #expect(loaded.messages.map(\.id) == ["user-1", "assistant-1", "user-2", "assistant-2"])
    #expect(loaded.messages.map(\.content) == ["你好", "你好！", "我们会说些什么呢？", "我们可以聊图谱。"])
}
