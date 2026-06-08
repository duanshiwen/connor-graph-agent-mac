import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphStore
import ConnorGraphSearch

private func temporaryAppChatDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func appChatRepositoryCreatesFirstSession() throws {
    let store = try SQLiteGraphStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let now = Date(timeIntervalSince1970: 1_000)

    let session = try repository.createSession(now: now)
    let loaded = try #require(try repository.loadSession(id: session.id))

    #expect(loaded.title == "New Chat")
    #expect(loaded.createdAt == now)
    #expect(loaded.updatedAt == now)
}

@Test func appChatRepositoryLoadsRecentSessions() throws {
    let store = try SQLiteGraphStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let old = AgentSession(id: "old", title: "Old", createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
    let new = AgentSession(id: "new", title: "New", createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 3_000))
    try store.upsert(chatSession: old)
    try store.upsert(chatSession: new)

    let sessions = try repository.loadRecentSessions(limit: 10)

    #expect(sessions.map(\.id) == ["new", "old"])
}

@Test func appChatRepositorySavesGraphAgentTurn() throws {
    let store = try SQLiteGraphStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let originalSession = AgentSession(id: "session-1", title: "New Chat", createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
    try store.upsert(chatSession: originalSession)
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
    let response = GraphAgentAskResponse(
        answer: LLMResponse(text: assistant.content, citations: assistant.citations),
        context: AgentContext(query: "memory", items: []),
        session: responseSession,
        observeLogEntries: []
    )

    let saved = try repository.saveTurn(previousMessageCount: 0, response: response)
    let loaded = try #require(try repository.loadSession(id: "session-1"))

    #expect(saved.id == "session-1")
    #expect(loaded.messages.map(\.id) == ["user-1", "assistant-1"])
    #expect(loaded.messages[1].citations == ["node:memory"])
}

@Test func appChatRepositorySavesAndLoadsLatestSummary() throws {
    let store = try SQLiteGraphStore(path: temporaryAppChatDatabaseURL().path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "session-1", title: "Graph memory")
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "The session discussed graph memory.",
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000),
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )

    try store.upsert(chatSession: session)
    let saved = try repository.saveSummary(summary)
    let loaded = try #require(try repository.loadLatestSummary(sessionID: "session-1"))

    #expect(saved == summary)
    #expect(loaded == summary)
}
