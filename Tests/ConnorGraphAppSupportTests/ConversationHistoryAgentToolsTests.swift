import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func conversationHistorySearchReturnsUserAndAssistantMessagesWithinRange() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryConversationHistoryDatabaseURL().path)
    try store.migrate()
    let start = Date(timeIntervalSince1970: 10_000)
    let end = start.addingTimeInterval(86_400)
    try store.upsertSession(AgentSession(
        id: "session-in-range",
        title: "Yesterday work",
        messages: [
            AgentMessage(id: "user-inside", role: .user, content: "Please review the release task", createdAt: start.addingTimeInterval(60)),
            AgentMessage(id: "assistant-inside", role: .assistant, content: "The release task was completed", createdAt: start.addingTimeInterval(120)),
            AgentMessage(id: "assistant-outside", role: .assistant, content: "Older reply", createdAt: start.addingTimeInterval(-60)),
            AgentMessage(id: "system-inside", role: .system, content: "Hidden instruction", createdAt: start.addingTimeInterval(180))
        ],
        createdAt: start.addingTimeInterval(-60),
        updatedAt: start.addingTimeInterval(180)
    ))
    let tool = ConversationHistorySearchTool(repository: AppChatSessionRepository(store: store))
    let result = try await tool.execute(
        arguments: AgentToolArguments(json: """
        {"query":"","startDate":"\(iso8601ConversationHistory(start))","endDate":"\(iso8601ConversationHistory(end))"}
        """),
        context: conversationHistoryToolContext()
    )
    let response = try conversationHistoryDecoder().decode(ConversationHistorySearchResponse.self, from: Data(try #require(result.contentJSON).utf8))

    #expect(response.messages.map(\.messageID) == ["user-inside", "assistant-inside"])
    #expect(response.messages.map(\.role) == [.user, .assistant])
    #expect(response.messages.allSatisfy { $0.sessionTitle == "Yesterday work" })
    #expect(!response.hasMore)
}

@Test func conversationHistorySearchAppliesOptionalTopicFilter() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryConversationHistoryDatabaseURL().path)
    try store.migrate()
    let start = Date(timeIntervalSince1970: 40_000)
    let end = start.addingTimeInterval(3_600)
    try store.upsertSession(AgentSession(
        id: "topic-session",
        title: "Topics",
        messages: [
            AgentMessage(id: "release-message", role: .user, content: "Release planning task", createdAt: start.addingTimeInterval(60)),
            AgentMessage(id: "design-message", role: .assistant, content: "Design review", createdAt: start.addingTimeInterval(120))
        ],
        createdAt: start,
        updatedAt: start.addingTimeInterval(120)
    ))

    let result = try await ConversationHistorySearchTool(repository: AppChatSessionRepository(store: store)).execute(
        arguments: AgentToolArguments(json: """
        {"query":"release task","startDate":"\(iso8601ConversationHistory(start))","endDate":"\(iso8601ConversationHistory(end))"}
        """),
        context: conversationHistoryToolContext()
    )
    let response = try conversationHistoryDecoder().decode(ConversationHistorySearchResponse.self, from: Data(try #require(result.contentJSON).utf8))
    #expect(response.messages.map(\.messageID) == ["release-message"])
}

@Test func conversationHistorySearchReportsMoreMessagesBeyondLimit() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryConversationHistoryDatabaseURL().path)
    try store.migrate()
    let start = Date(timeIntervalSince1970: 70_000)
    let end = start.addingTimeInterval(3_600)
    try store.upsertSession(AgentSession(
        id: "limited-session",
        title: "Limited recap",
        messages: [
            AgentMessage(id: "first-message", role: .user, content: "First task", createdAt: start.addingTimeInterval(60)),
            AgentMessage(id: "second-message", role: .assistant, content: "Second task", createdAt: start.addingTimeInterval(120))
        ],
        createdAt: start,
        updatedAt: start.addingTimeInterval(120)
    ))

    let result = try await ConversationHistorySearchTool(repository: AppChatSessionRepository(store: store)).execute(
        arguments: AgentToolArguments(json: """
        {"query":"","startDate":"\(iso8601ConversationHistory(start))","endDate":"\(iso8601ConversationHistory(end))","limit":1}
        """),
        context: conversationHistoryToolContext()
    )
    let response = try conversationHistoryDecoder().decode(ConversationHistorySearchResponse.self, from: Data(try #require(result.contentJSON).utf8))

    #expect(response.messages.map(\.messageID) == ["first-message"])
    #expect(response.hasMore)
}

private func conversationHistoryToolContext() -> AgentToolExecutionContext {
    AgentToolExecutionContext(
        runID: "conversation-history-run",
        sessionID: "current-session",
        groupID: "default",
        userPrompt: "review yesterday",
        toolCallID: "conversation-history-call",
        policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
    )
}

private func iso8601ConversationHistory(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func conversationHistoryDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func temporaryConversationHistoryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("conversation-history-tool-\(UUID().uuidString).sqlite")
}
