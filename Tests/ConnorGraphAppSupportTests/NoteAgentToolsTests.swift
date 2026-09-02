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

@Test func noteGetToolPaginatesLongBodyAcrossPagesAndReassembles() async throws {
    let (repository, _, tool) = try noteToolFixture()
    var note = try #require(try repository.note(sessionID: "session-0"))
    let fullBody = String(repeating: "完整正文段落。", count: 1_000)
    note.body = fullBody
    note.contentHash = AppNoteProjectionService.contentHash(note.body)
    try repository.upsert(note)

    let firstResult = try await tool.execute(arguments: AgentToolArguments(values: [
        "noteIDs": .array([.string(note.id)])
    ]), context: noteToolContext("page1"))
    let firstData = try #require(firstResult.contentJSON?.data(using: .utf8))
    let first = try JSONDecoder.noteTool.decode(NoteGetToolResponse.self, from: firstData)

    let item = try #require(first.records.first)
    #expect(item.status == "found")
    #expect(item.page == 1)
    #expect(item.pageSize == NoteGetTool.defaultPageSize)
    #expect(item.characterOffset == 0)
    #expect(item.totalCharacters == fullBody.count)
    #expect(item.returnedCharacters == NoteGetTool.defaultPageSize)
    #expect(item.isTruncated)
    #expect(item.hasMore)
    #expect(item.nextPage == 2)
    #expect(item.body == String(fullBody.prefix(NoteGetTool.defaultPageSize)))
    #expect(first.page == 1)
    #expect(first.pageSize == NoteGetTool.defaultPageSize)

    // 按 nextPage 翻到最后一页，整篇正文应能完整重装。
    var assembled = item.body ?? ""
    var page = 2
    var guardCount = 0
    while true {
        guardCount += 1
        #expect(guardCount < 100)
        let result = try await tool.execute(arguments: AgentToolArguments(values: [
            "noteIDs": .array([.string(note.id)]), "page": .int(page)
        ]), context: noteToolContext("page\(page)"))
        let data = try #require(result.contentJSON?.data(using: .utf8))
        let response = try JSONDecoder.noteTool.decode(NoteGetToolResponse.self, from: data)
        let current = try #require(response.records.first)
        assembled += current.body ?? ""
        if !current.hasMore { break }
        page += 1
    }
    #expect(assembled == fullBody)
}

@Test func noteGetToolRespectsExplicitPageAndPageSize() async throws {
    let (repository, _, tool) = try noteToolFixture()
    var note = try #require(try repository.note(sessionID: "session-0"))
    let fullBody = String(repeating: "正文", count: 900)
    note.body = fullBody
    note.contentHash = AppNoteProjectionService.contentHash(note.body)
    try repository.upsert(note)

    // page=2, pageSize=300 → 返回 offset 300..<600 这一段。
    let result = try await tool.execute(arguments: AgentToolArguments(values: [
        "noteIDs": .array([.string(note.id)]), "page": .int(2), "pageSize": .int(300)
    ]), context: noteToolContext("explicit"))
    let data = try #require(result.contentJSON?.data(using: .utf8))
    let response = try JSONDecoder.noteTool.decode(NoteGetToolResponse.self, from: data)
    let item = try #require(response.records.first)

    #expect(item.page == 2)
    #expect(item.pageSize == 300)
    #expect(item.characterOffset == 300)
    #expect(item.returnedCharacters == 300)
    #expect(item.totalCharacters == 1800)
    #expect(item.body == String(fullBody.dropFirst(300).prefix(300)))
    #expect(item.hasMore)
    #expect(item.nextPage == 3)
    #expect(item.isTruncated)

    // 模型常把整数发成字符串，应同样接受；第 6 页是最后一页。
    let stringResult = try await tool.execute(arguments: AgentToolArguments(values: [
        "noteIDs": .array([.string(note.id)]), "page": .string("6"), "pageSize": .string("300")
    ]), context: noteToolContext("string"))
    let stringData = try #require(stringResult.contentJSON?.data(using: .utf8))
    let stringResponse = try JSONDecoder.noteTool.decode(NoteGetToolResponse.self, from: stringData)
    let lastItem = try #require(stringResponse.records.first)
    #expect(lastItem.page == 6)
    #expect(lastItem.body == String(fullBody.dropFirst(1500).prefix(300)))
    #expect(!lastItem.hasMore)
    #expect(lastItem.nextPage == nil)
    #expect(!lastItem.isTruncated)
}

@Test func noteGetToolRejectsInvalidPageAndPageSize() async throws {
    let (repository, _, tool) = try noteToolFixture()
    let note = try #require(try repository.note(sessionID: "session-0"))

    await #expect(throws: AgentToolError.self) {
        try await tool.execute(arguments: AgentToolArguments(values: [
            "noteIDs": .array([.string(note.id)]), "page": .int(0)
        ]), context: noteToolContext("zeroPage"))
    }
    await #expect(throws: AgentToolError.self) {
        try await tool.execute(arguments: AgentToolArguments(values: [
            "noteIDs": .array([.string(note.id)]), "pageSize": .int(100)
        ]), context: noteToolContext("smallPageSize"))
    }
    await #expect(throws: AgentToolError.self) {
        try await tool.execute(arguments: AgentToolArguments(values: [
            "noteIDs": .array([.string(note.id)]), "pageSize": .int(100_000)
        ]), context: noteToolContext("bigPageSize"))
    }
}

private extension JSONDecoder {
    static var noteTool: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
