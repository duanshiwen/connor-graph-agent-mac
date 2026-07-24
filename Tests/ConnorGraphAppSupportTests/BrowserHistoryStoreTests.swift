import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Browser History Store Tests")
struct BrowserHistoryStoreTests {
    @Test("Pages every JSONL record backwards without duplicates")
    func pagesEveryRecord() {
        let (store, url) = makeStore()
        defer { cleanup(url) }
        for index in 0..<137 {
            store.appendRecord(.init(
                url: "https://example.com/\(index)",
                title: "Page \(index)",
                sessionID: "session",
                sessionTitle: "Session",
                visitedAt: Date(timeIntervalSince1970: Double(index))
            ))
        }

        var titles: [String] = []
        var cursor: String?
        repeat {
            let page = store.loadHistoryPage(cursor: cursor, pageSize: 50)
            titles += page.records.map(\.title)
            cursor = page.nextCursor
        } while cursor != nil

        #expect(titles == (0..<137).reversed().map { "Page \($0)" })
        #expect(Set(titles).count == 137)
    }

    @Test("Search pages continue scanning past nonmatching records")
    func pagesSearchResults() {
        let (store, url) = makeStore()
        defer { cleanup(url) }
        for index in 0..<137 {
            store.appendRecord(.init(
                url: "https://example.com/\(index)",
                title: index.isMultiple(of: 3) ? "Matched \(index)" : "Other \(index)",
                sessionID: "session",
                sessionTitle: "Session",
                visitedAt: Date(timeIntervalSince1970: Double(index))
            ))
        }

        var records: [BrowserHistoryRecord] = []
        var cursor: String?
        repeat {
            let page = store.loadHistoryPage(cursor: cursor, query: "matched", pageSize: 17)
            records += page.records
            cursor = page.nextCursor
        } while cursor != nil

        #expect(records.count == 46)
        #expect(records.allSatisfy { $0.title.hasPrefix("Matched") })
        #expect(Set(records.map(\.id)).count == 46)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("browser-history-test-\(UUID().uuidString).jsonl")
    }

    private func makeStore() -> (BrowserHistoryStore, URL) {
        let url = tempURL()
        let store = BrowserHistoryStore(historyURL: url)
        return (store, url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Append and load records")
    func appendAndLoad() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        let record = BrowserHistoryRecord(
            url: "https://example.com",
            title: "Example",
            sessionID: "s1",
            sessionTitle: "Test Session"
        )
        store.appendRecord(record)

        let loaded = store.loadHistory()
        #expect(loaded.count == 1)
        #expect(loaded.first?.url == "https://example.com")
        #expect(loaded.first?.title == "Example")
        #expect(loaded.first?.sessionID == "s1")
        #expect(loaded.first?.sessionTitle == "Test Session")
    }

    @Test("Deduplication within time window")
    func deduplication() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        let r1 = BrowserHistoryRecord(url: "https://example.com", title: "Page", sessionID: "s1", sessionTitle: "Session", visitedAt: Date())
        store.appendRecord(r1)
        // Second record within 5 seconds should be deduplicated
        let r2 = BrowserHistoryRecord(url: "https://example.com", title: "Page Updated", sessionID: "s1", sessionTitle: "Session", visitedAt: Date().addingTimeInterval(2))
        store.appendRecord(r2)

        let loaded = store.loadHistory()
        #expect(loaded.count == 1)
        // First record is kept because dedup checks last record
        #expect(loaded.first?.title == "Page")
    }

    @Test("Different sessions are not deduplicated")
    func differentSessionNotDeduped() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        let r1 = BrowserHistoryRecord(url: "https://example.com", title: "Page", sessionID: "s1", sessionTitle: "Session A", visitedAt: Date())
        store.appendRecord(r1)
        let r2 = BrowserHistoryRecord(url: "https://example.com", title: "Page", sessionID: "s2", sessionTitle: "Session B", visitedAt: Date().addingTimeInterval(2))
        store.appendRecord(r2)

        let loaded = store.loadHistory()
        #expect(loaded.count == 2)
    }

    @Test("Search filters by URL and title")
    func searchFilter() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        store.appendRecord(BrowserHistoryRecord(url: "https://apple.com", title: "Apple", sessionID: "s1", sessionTitle: "S"))
        store.appendRecord(BrowserHistoryRecord(url: "https://github.com", title: "GitHub", sessionID: "s1", sessionTitle: "S"))
        store.appendRecord(BrowserHistoryRecord(url: "https://swift.org", title: "Swift", sessionID: "s1", sessionTitle: "S"))

        let appleResults = store.searchHistory(query: "apple")
        #expect(appleResults.count == 1)
        #expect(appleResults.first?.url == "https://apple.com")

        let githubResults = store.searchHistory(query: "github")
        #expect(githubResults.count == 1)

        let emptyResults = store.searchHistory(query: "nonexistent")
        #expect(emptyResults.isEmpty)

        let allResults = store.searchHistory(query: "")
        #expect(allResults.count == 3)
    }

    @Test("Delete single record")
    func deleteRecord() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        let r1 = BrowserHistoryRecord(url: "https://a.com", title: "A", sessionID: "s1", sessionTitle: "S")
        let r2 = BrowserHistoryRecord(url: "https://b.com", title: "B", sessionID: "s1", sessionTitle: "S")
        store.appendRecord(r1)
        store.appendRecord(r2)

        store.deleteRecord(id: r1.id)
        let loaded = store.loadHistory()
        #expect(loaded.count == 1)
        #expect(loaded.first?.url == "https://b.com")
    }

    @Test("Clear all history")
    func clearAll() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        store.appendRecord(BrowserHistoryRecord(url: "https://a.com", title: "A", sessionID: "s1", sessionTitle: "S"))
        store.appendRecord(BrowserHistoryRecord(url: "https://b.com", title: "B", sessionID: "s1", sessionTitle: "S"))
        #expect(store.loadHistory().count == 2)

        store.clearHistory()
        #expect(store.loadHistory().isEmpty)
    }

    @Test("Max record count is enforced")
    func maxRecordCount() {
        let url = tempURL()
        defer { cleanup(url) }

        let limit = 25
        let store = BrowserHistoryStore(historyURL: url, maxRecordCount: limit)
        // Append records with different URLs to avoid dedup
        for i in 0..<(limit + 5) {
            let record = BrowserHistoryRecord(
                url: "https://example.com/\(i)",
                title: "Page \(i)",
                sessionID: "s1",
                sessionTitle: "Session",
                visitedAt: Date(timeIntervalSince1970: Double(i))
            )
            store.appendRecord(record)
        }

        let loaded = store.loadHistory()
        #expect(loaded.count == limit)
        // Oldest records should be trimmed
        #expect(loaded.first?.url == "https://example.com/5")
    }

    @Test("Search by session title")
    func searchBySessionTitle() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        store.appendRecord(BrowserHistoryRecord(url: "https://a.com", title: "Page A", sessionID: "s1", sessionTitle: "SwiftUI 项目"))
        store.appendRecord(BrowserHistoryRecord(url: "https://b.com", title: "Page B", sessionID: "s2", sessionTitle: "Agent OS 设计"))

        let results = store.searchHistory(query: "SwiftUI")
        #expect(results.count == 1)
        #expect(results.first?.sessionTitle == "SwiftUI 项目")
    }

    @Test("Update and persist fetched page content")
    func updateAndPersistFetchedPageContent() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        let record = BrowserHistoryRecord(
            url: "https://example.com/article",
            title: "Article",
            sessionID: "s1",
            sessionTitle: "Research",
            contentFetchStatus: .pending
        )
        let appended = store.appendRecord(record)
        #expect(appended?.id == record.id)

        store.updateContent(
            id: record.id,
            markdown: "# Article\n\nThis page discusses graph-memory-native Agent OS design.",
            fetchedAt: Date(timeIntervalSince1970: 100),
            status: .fetched
        )

        let reloadedStore = BrowserHistoryStore(historyURL: url)
        let loaded = reloadedStore.loadHistory()
        #expect(loaded.count == 1)
        #expect(loaded.first?.contentFetchStatus == .fetched)
        #expect(loaded.first?.contentFetchedAt == Date(timeIntervalSince1970: 100))
        #expect(loaded.first?.contentMarkdown?.contains("graph-memory-native") == true)
        #expect(loaded.first?.contentFetchError == nil)
    }

    @Test("Search filters by fetched page content")
    func searchByFetchedPageContent() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        let record = BrowserHistoryRecord(url: "https://example.com", title: "Unrelated", sessionID: "s1", sessionTitle: "S")
        store.appendRecord(record)
        store.updateContent(
            id: record.id,
            markdown: "Connor browser history stores cleaned Markdown page bodies for later retrieval.",
            status: .fetched
        )

        let results = store.searchHistory(query: "cleaned markdown")
        #expect(results.count == 1)
        #expect(results.first?.id == record.id)
    }

    @Test("Search tokenizes Chinese sentence queries")
    func searchTokenizesChineseSentenceQueries() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        store.appendRecord(BrowserHistoryRecord(url: "https://example.com/thailand", title: "泰国数字游民签证指南", sessionID: "s1", sessionTitle: "东南亚研究"))
        store.appendRecord(BrowserHistoryRecord(url: "https://example.com/vietnam", title: "越南旅行记录", sessionID: "s1", sessionTitle: "东南亚研究"))

        let results = store.searchHistory(query: "帮我找泰国签证")

        #expect(results.map(\.title) == ["泰国数字游民签证指南"])
    }
}
