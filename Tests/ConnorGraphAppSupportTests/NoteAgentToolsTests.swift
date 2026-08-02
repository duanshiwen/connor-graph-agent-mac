import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

private func noteToolContext(_ id: String) -> AgentToolExecutionContext {
    AgentToolExecutionContext(runID: "run", sessionID: "session", groupID: "default", userPrompt: "notes",
        toolCallID: id, policyEngine: AgentPolicyEngine(permissionMode: .allowAll))
}

private func noteToolFixture(count: Int = 1) throws -> (AppNoteRepository, NoteSearchTool, NoteGetTool) {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let sessions = AppChatSessionRepository(store: store)
    var governance = AgentSessionGovernanceMetadata.default
    governance.kind = .note
    for index in 0..<count {
        try sessions.saveSession(AgentSession(
            id: "session-\(index)", title: "Indexed \(index)",
            messages: [AgentMessage(id: "message-\(index)", role: .user, content: "searchable body \(index)")],
            createdAt: Date(timeIntervalSince1970: Double(index + 1)),
            updatedAt: Date(timeIntervalSince1970: Double(index + 1)), governance: governance
        ))
    }
    let repository = AppNoteRepository(store: store)
    return (repository, NoteSearchTool(search: NoteSearchService(repository: repository)), NoteGetTool(repository: repository))
}

@Test func noteSearchToolReturnsSummaryOnlyPaginationEnvelope() async throws {
    let (_, tool, _) = try noteToolFixture(count: 12)
    let properties = try #require(tool.inputSchema.jsonObject["properties"] as? [String: Any])
    let result = try await tool.execute(arguments: AgentToolArguments(values: ["query": .string("searchable"), "page": .int(1)]), context: noteToolContext("search"))
    let data = try #require(result.contentJSON?.data(using: .utf8))
    let response = try JSONDecoder.noteTool.decode(NoteSearchToolResponse.self, from: data)

    #expect(response.success)
    #expect(response.page == 1)
    #expect(response.pageSize == 10)
    #expect(response.returnedItems == 10)
    #expect(response.totalItems == 12)
    #expect(response.nextPage == 2)
    #expect(result.contentJSON?.contains("\"body\":") == false)
    #expect(properties["page"] != nil)
    #expect(properties["pageSize"] == nil)
    #expect(tool.description.contains("pageSize is runtime-controlled response metadata, not an input parameter"))
}

@Test func noteSearchToolRejectsNonIntegerAndOutOfRangePagesWithoutFallback() async throws {
    let (_, tool, _) = try noteToolFixture()
    let stringPage = try await tool.execute(arguments: AgentToolArguments(values: ["query": .string("searchable"), "page": .string("1")]), context: noteToolContext("string"))
    let outOfRange = try await tool.execute(arguments: AgentToolArguments(values: ["query": .string("searchable"), "page": .int(2)]), context: noteToolContext("range"))

    #expect(stringPage.error != nil)
    #expect(stringPage.contentJSON?.contains("\"success\":false") == true)
    #expect(outOfRange.error != nil)
    #expect(outOfRange.contentJSON?.contains("\"records\":[]") == true)
}

@Test func noteGetToolPreservesOrderDeduplicatesAndReportsPerItemStatus() async throws {
    let (repository, _, tool) = try noteToolFixture(count: 2)
    try repository.delete(sessionID: "session-1")
    let result = try await tool.execute(arguments: AgentToolArguments(values: [
        "noteIDs": .array([.string("note:session-0"), .string("invalid title"), .string("note:missing"), .string("note:session-1"), .string("note:session-0")])
    ]), context: noteToolContext("get"))
    let data = try #require(result.contentJSON?.data(using: .utf8))
    let response = try JSONDecoder.noteTool.decode(NoteGetToolResponse.self, from: data)

    #expect(response.records.map(\.requestedNoteID) == ["note:session-0", "invalid title", "note:missing", "note:session-1"])
    #expect(response.records.map(\.status) == ["found", "invalid", "not_found", "deleted"])
    #expect(response.records[0].body == "searchable body 0")
    #expect(response.records[0].sourceMessageID == "message-0")
}

@Test func noteGetToolReturnsCompleteLongBody() async throws {
    let (repository, _, tool) = try noteToolFixture()
    var note = try #require(try repository.note(sessionID: "session-0"))
    note.body = String(repeating: "完整正文段落。", count: 10_000)
    note.contentHash = AppNoteProjectionService.contentHash(note.body)
    try repository.upsert(note)

    let result = try await tool.execute(arguments: AgentToolArguments(values: [
        "noteIDs": .array([.string(note.id)])
    ]), context: noteToolContext("complete"))
    let data = try #require(result.contentJSON?.data(using: .utf8))
    let response = try JSONDecoder.noteTool.decode(NoteGetToolResponse.self, from: data)

    #expect(response.records[0].body == note.body)
    #expect(!response.records[0].isTruncated)
    #expect(response.records[0].returnedCharacters == note.body.count)
    #expect(response.records[0].totalCharacters == note.body.count)
}

private extension JSONDecoder {
    static var noteTool: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
