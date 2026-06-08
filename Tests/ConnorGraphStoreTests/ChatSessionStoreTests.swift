import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryChatDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func graphStoreSavesAndLoadsChatSession() throws {
    let store = try SQLiteGraphStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let session = AgentSession(
        id: "session-1",
        title: "Graph memory",
        messages: [],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )

    try store.upsert(chatSession: session)
    let loaded = try #require(try store.chatSession(id: "session-1"))

    #expect(loaded.id == "session-1")
    #expect(loaded.title == "Graph memory")
    #expect(loaded.createdAt == Date(timeIntervalSince1970: 1_000))
    #expect(loaded.updatedAt == Date(timeIntervalSince1970: 2_000))
    #expect(loaded.messages.isEmpty)
}

@Test func graphStoreAppendsAndLoadsChatMessagesInOrder() throws {
    let store = try SQLiteGraphStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let session = AgentSession(id: "session-1", title: "Graph memory")
    let user = AgentMessage(id: "message-1", role: .user, content: "What is memory?", createdAt: Date(timeIntervalSince1970: 1_000))
    let assistant = AgentMessage(
        id: "message-2",
        role: .assistant,
        content: "Graph memory.",
        createdAt: Date(timeIntervalSince1970: 2_000),
        citations: ["node:memory"],
        contextSnapshot: "Node[work_object] Memory"
    )

    try store.upsert(chatSession: session)
    try store.append(chatMessage: assistant, sessionID: session.id)
    try store.append(chatMessage: user, sessionID: session.id)

    let messages = try store.chatMessages(sessionID: session.id)

    #expect(messages.map(\.id) == ["message-1", "message-2"])
    #expect(messages[1].citations == ["node:memory"])
    #expect(messages[1].contextSnapshot == "Node[work_object] Memory")
}

@Test func graphStorePersistsPromptInspectionSnapshotOnChatMessage() throws {
    let store = try SQLiteGraphStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let session = AgentSession(id: "session-1", title: "Graph memory")
    let snapshot = AgentPromptInspectionSnapshot(
        includesSummary: true,
        recentMessageCount: 2,
        currentRequest: "What next?",
        renderedPrompt: "Rendered prompt"
    )
    let assistant = AgentMessage(
        id: "message-1",
        role: .assistant,
        content: "Answer",
        createdAt: Date(timeIntervalSince1970: 1_000),
        promptInspection: snapshot
    )

    try store.upsert(chatSession: session)
    try store.append(chatMessage: assistant, sessionID: session.id)

    let loaded = try #require(try store.chatMessages(sessionID: session.id).first)

    #expect(loaded.promptInspection == snapshot)
}

@Test func graphStoreLoadsRecentChatSessionsByUpdatedAt() throws {
    let store = try SQLiteGraphStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let old = AgentSession(id: "session-old", title: "Old", createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
    let new = AgentSession(id: "session-new", title: "New", createdAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 3_000))

    try store.upsert(chatSession: old)
    try store.upsert(chatSession: new)

    let sessions = try store.chatSessions(limit: 10)

    #expect(sessions.map(\.id) == ["session-new", "session-old"])
    #expect(sessions.allSatisfy { $0.messages.isEmpty })
}

@Test func graphStoreMigratesChatSessionSummariesTable() throws {
    let store = try SQLiteGraphStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("chat_session_summaries"))
}

@Test func graphStoreSavesAndLoadsLatestChatSessionSummary() throws {
    let store = try SQLiteGraphStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()
    let session = AgentSession(id: "session-1", title: "Graph memory")
    let old = AgentSessionSummary(
        id: "summary-old",
        sessionID: "session-1",
        content: "Old summary",
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000),
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let latest = AgentSessionSummary(
        id: "summary-latest",
        sessionID: "session-1",
        content: "Latest summary",
        createdAt: Date(timeIntervalSince1970: 2_000),
        updatedAt: Date(timeIntervalSince1970: 3_000),
        sourceMessageCount: 4,
        lastMessageID: "message-4"
    )

    try store.upsert(chatSession: session)
    try store.upsert(chatSessionSummary: old)
    try store.upsert(chatSessionSummary: latest)

    let loaded = try #require(try store.latestChatSessionSummary(sessionID: "session-1"))

    #expect(loaded == latest)
}
