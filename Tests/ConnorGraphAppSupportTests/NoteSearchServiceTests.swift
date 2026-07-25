import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

private func indexedNoteFixture() throws -> (SQLiteGraphKernelStore, AppChatSessionRepository, NoteSearchService) {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    return (store, repository, NoteSearchService(repository: AppNoteRepository(store: store)))
}

@Test func noteSearchIndexesFullBodyWithCJKAndStableIDs() throws {
    let (store, sessions, search) = try indexedNoteFixture()
    var governance = AgentSessionGovernanceMetadata.default
    governance.kind = .note
    let body = String(repeating: "前言 ", count: 100) + "增量索引与中文检索命中" + String(repeating: " 后文", count: 100)
    try sessions.saveSession(AgentSession(id: "cjk", title: "工程笔记", messages: [AgentMessage(id: "source", role: .user, content: body)], governance: governance))

    let page = try search.search(query: "中文检索", page: 1)

    #expect(page.totalItems == 1)
    #expect(page.records.first?.noteID == "note:cjk")
    #expect(page.records.first?.sessionID == "cjk")
    #expect(page.records.first?.snippet.contains("中文检索") == true)
    #expect(try AppNoteRepository(store: store).note(sessionID: "cjk")?.indexVersion == NoteSearchService.currentIndexVersion)
}

@Test func noteSearchPaginatesWithoutDuplicatesAndSupportsEmptyQuery() throws {
    let (_, sessions, search) = try indexedNoteFixture()
    var governance = AgentSessionGovernanceMetadata.default
    governance.kind = .note
    for index in 0..<5 {
        try sessions.saveSession(AgentSession(
            id: "note-\(index)", title: "Topic \(index)", messages: [AgentMessage(role: .user, content: "shared topic body")],
            createdAt: Date(timeIntervalSince1970: Double(index)), updatedAt: Date(timeIntervalSince1970: Double(index)), governance: governance
        ))
    }

    let first = try search.search(query: "shared", page: 1, pageSize: 2)
    let second = try search.search(query: "shared", page: 2, pageSize: 2)
    let all = try search.search(query: "", page: 1, pageSize: 10)

    #expect(first.totalItems == 5)
    #expect(Set(first.records.map(\.noteID)).isDisjoint(with: Set(second.records.map(\.noteID))))
    #expect(all.totalItems == 5)
    #expect(throws: NoteSearchServiceError.invalidPage(4)) { try search.search(query: "shared", page: 4, pageSize: 2) }
}

@Test func noteSearchDeletionRemovesIndexedDocument() throws {
    let (_, sessions, search) = try indexedNoteFixture()
    var governance = AgentSessionGovernanceMetadata.default
    governance.kind = .note
    try sessions.saveSession(AgentSession(id: "delete", messages: [AgentMessage(role: .user, content: "unique searchable")], governance: governance))
    #expect(try search.search(query: "unique").totalItems == 1)

    try sessions.deleteSession(sessionID: "delete")

    #expect(try search.search(query: "unique").totalItems == 0)
}
