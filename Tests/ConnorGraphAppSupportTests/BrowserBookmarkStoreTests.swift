import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Browser Bookmark Store Tests")
struct BrowserBookmarkStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("browser-bookmarks-test-\(UUID().uuidString).jsonl")
    }

    private func makeStore() -> (BrowserBookmarkStore, URL) {
        let url = tempURL()
        let store = BrowserBookmarkStore(bookmarksURL: url)
        return (store, url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Add and load bookmarks")
    func addAndLoad() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        let bookmark = BrowserBookmarkRecord(
            url: "https://example.com",
            title: "Example",
            groupName: "默认",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        store.upsertBookmark(bookmark)

        let loaded = store.loadBookmarks()
        #expect(loaded.count == 1)
        #expect(loaded.first?.url == "https://example.com")
        #expect(loaded.first?.title == "Example")
        #expect(loaded.first?.groupName == "默认")
    }

    @Test("Upsert by URL updates title and group")
    func upsertByURL() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        store.upsertBookmark(BrowserBookmarkRecord(
            url: "https://example.com",
            title: "Old",
            groupName: "默认",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        ))
        store.upsertBookmark(BrowserBookmarkRecord(
            url: "https://example.com",
            title: "New",
            groupName: "研究",
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        ))

        let loaded = store.loadBookmarks()
        #expect(loaded.count == 1)
        #expect(loaded.first?.title == "New")
        #expect(loaded.first?.groupName == "研究")
        #expect(loaded.first?.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(loaded.first?.updatedAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test("Search filters by URL title and group")
    func searchFilter() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        store.upsertBookmark(BrowserBookmarkRecord(url: "https://apple.com", title: "Apple", groupName: "科技"))
        store.upsertBookmark(BrowserBookmarkRecord(url: "https://github.com", title: "GitHub", groupName: "开发"))
        store.upsertBookmark(BrowserBookmarkRecord(url: "https://swift.org", title: "Swift", groupName: "开发"))

        #expect(store.searchBookmarks(query: "apple").map(\.url) == ["https://apple.com"])
        #expect(store.searchBookmarks(query: "开发").count == 2)
        #expect(store.searchBookmarks(query: "nonexistent").isEmpty)
        #expect(store.searchBookmarks(query: "").count == 3)
    }

    @Test("Group filtering and group list")
    func groupFiltering() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        store.upsertBookmark(BrowserBookmarkRecord(url: "https://a.com", title: "A", groupName: "默认"))
        store.upsertBookmark(BrowserBookmarkRecord(url: "https://b.com", title: "B", groupName: "研究"))
        store.upsertBookmark(BrowserBookmarkRecord(url: "https://c.com", title: "C", groupName: "研究"))

        #expect(store.groups() == ["默认", "研究"])
        #expect(store.bookmarks(groupName: "研究").map(\.url) == ["https://b.com", "https://c.com"])
    }

    @Test("Delete bookmark")
    func deleteBookmark() {
        let (store, url) = makeStore()
        defer { cleanup(url) }

        let a = BrowserBookmarkRecord(url: "https://a.com", title: "A", groupName: "默认")
        let b = BrowserBookmarkRecord(url: "https://b.com", title: "B", groupName: "默认")
        store.upsertBookmark(a)
        store.upsertBookmark(b)

        store.deleteBookmark(id: a.id)
        #expect(store.loadBookmarks().map(\.url) == ["https://b.com"])
    }
}
