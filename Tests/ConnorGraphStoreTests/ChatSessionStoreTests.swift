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

@Test func graphKernelStoreMigratesAgentSessionsTable() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryChatDatabaseURL().path)
    try store.migrate()

    let tables = try store.tableNames()

    #expect(tables.contains("agent_sessions"))
}
