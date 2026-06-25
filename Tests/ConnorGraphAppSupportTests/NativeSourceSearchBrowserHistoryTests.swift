import Foundation
import Testing
@testable import ConnorGraphAppSupport
import ConnorGraphCore

@Suite("Native Source Search Browser History Tests")
struct NativeSourceSearchBrowserHistoryTests {
    @Test func browserHistoryAdapterIndexesTitleURLSessionAndContent() async throws {
        let visitedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let record = BrowserHistoryRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            url: "https://developer.apple.com/documentation/swift/concurrency",
            title: "Swift Concurrency Documentation",
            sessionID: "session-1",
            sessionTitle: "Agent OS Research",
            visitedAt: visitedAt,
            contentMarkdown: "Actors and structured concurrency improve search indexing reliability.",
            contentFetchedAt: visitedAt.addingTimeInterval(30),
            contentFetchStatus: .fetched
        )

        let document = NativeSourceSearchAdapters.browserHistoryDocument(from: record)

        #expect(document.id == "browser-history:11111111-1111-1111-1111-111111111111")
        #expect(document.sourceKind == .browserHistory)
        #expect(document.externalID == record.id.uuidString)
        #expect(document.title == "Swift Concurrency Documentation")
        #expect(document.summary.contains("developer.apple.com"))
        #expect(document.participants.contains("Agent OS Research"))
        #expect(document.metadata["host"] == "developer.apple.com")
        #expect(document.metadata["sessionID"] == "session-1")
        #expect(document.temporal.primaryTime == visitedAt)
        #expect(document.temporal.primaryTimeKind == .updatedAt)

        let service = NativeSourceSearchService()
        try await service.upsert([document])

        let titleResults = try await service.search(NativeSearchQuery(text: "Swift Concurrency", sourceKinds: [.browserHistory], limit: 5, includeBodySnippets: true))
        #expect(titleResults.map(\.id) == [document.id])
        #expect(titleResults.first?.resultTimeLabel == "Updated")

        let hostResults = try await service.search(NativeSearchQuery(text: "developer apple", sourceKinds: [.browserHistory], limit: 5, includeBodySnippets: true))
        #expect(hostResults.map(\.id) == [document.id])

        let sessionResults = try await service.search(NativeSearchQuery(text: "Agent OS", sourceKinds: [.browserHistory], limit: 5, includeBodySnippets: true))
        #expect(sessionResults.map(\.id) == [document.id])

        let bodyResults = try await service.search(NativeSearchQuery(text: "structured concurrency", sourceKinds: [.browserHistory], limit: 5, includeBodySnippets: true))
        #expect(bodyResults.map(\.id) == [document.id])
    }

    @Test func browserHistoryTitleAndHostOutrankBodyOnlyMatches() async throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exact = BrowserHistoryRecord(
            url: "https://sqlite.org/fts5.html",
            title: "SQLite FTS5 Search",
            sessionID: "s1",
            sessionTitle: "Database Notes",
            visitedAt: now,
            contentMarkdown: "Official full text search docs."
        )
        let noisy = BrowserHistoryRecord(
            url: "https://example.com/notes",
            title: "Long Notes",
            sessionID: "s2",
            sessionTitle: "Scratch",
            visitedAt: now.addingTimeInterval(3600),
            contentMarkdown: String(repeating: "sqlite search ", count: 40)
        )
        let docs = [exact, noisy].map { NativeSourceSearchAdapters.browserHistoryDocument(from: $0) }
        let service = NativeSourceSearchService()
        try await service.upsert(docs)

        let results = try await service.search(NativeSearchQuery(text: "sqlite search", sourceKinds: [.browserHistory], limit: 10, includeBodySnippets: true))

        #expect(results.first?.id == docs[0].id)
    }
}
