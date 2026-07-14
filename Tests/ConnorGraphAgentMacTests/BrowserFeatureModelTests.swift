import Foundation
import Testing
@testable import ConnorGraphAgentMac
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Suite("BrowserFeatureModel Tests")
struct BrowserFeatureModelTests {
    @Test func workspaceOpenPersistsSnapshotAndEmitsTypedIntent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var shownSessionID: String?
        var persistedSessionID: String?
        fixture.model.onShowWorkspace = { shownSessionID = $0 }
        fixture.model.persistWorkspaceSnapshot = { _, sessionID in persistedSessionID = sessionID }

        fixture.model.openURL(try #require(URL(string: "https://example.com/docs")))

        #expect(fixture.model.isVisible)
        #expect(fixture.model.workspaceSessionID == "session-1")
        #expect(shownSessionID == "session-1")
        #expect(persistedSessionID == "session-1")
        #expect(fixture.model.workspaceSnapshotsBySessionID["session-1"]?.tabs.count == 1)
    }

    @Test func bookmarkStateAndFilteringHaveSingleOwner() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.model.addBookmark(url: "https://example.com/swift", title: "Swift Guide", groupName: "Docs")
        fixture.model.addBookmark(url: "https://example.com/news", title: "Daily News", groupName: "News")
        fixture.model.filterBookmarks(query: "swift", groupName: "Docs")

        #expect(fixture.model.bookmarkRecords.count == 2)
        #expect(fixture.model.filteredBookmarkRecords.map(\.title) == ["Swift Guide"])
        #expect(fixture.model.selectedBookmarkGroupName == "Docs")
        #expect(fixture.model.bookmarkGroupNames == ["Docs", "News"])
    }

    @Test func historyReadAndFilteringUseInjectedStore() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let swift = BrowserHistoryRecord(url: "https://example.com/swift", title: "Swift Concurrency", sessionID: "session-1", sessionTitle: "Work")
        let rust = BrowserHistoryRecord(url: "https://example.com/rust", title: "Rust Ownership", sessionID: "session-1", sessionTitle: "Work")
        _ = fixture.historyStore.appendRecord(swift)
        _ = fixture.historyStore.appendRecord(rust)

        fixture.model.loadHistory()
        fixture.model.filterHistory(query: "Swift")

        #expect(fixture.model.historyRecords.count == 2)
        #expect(fixture.model.filteredHistoryRecords.map(\.title) == ["Swift Concurrency"])
        #expect(fixture.model.fallbackSearchResults(query: "Rust", now: Date(), limit: 3).map(\.title) == ["Rust Ownership"])
    }

    @Test func assistedFetchCompletionResumesExactlyOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let resultTask = Task {
            await fixture.model.performAssistedWebFetch(BrowserAssistedWebFetchRequest(
                urlString: "https://example.com/rendered",
                extractMode: "text",
                waitUntil: "load",
                timeoutMilliseconds: 10_000,
                revealImmediately: false
            ))
        }
        await Task.yield()
        let taskID = try #require(fixture.model.assistedTasksByID.keys.first)

        fixture.model.completeAssistedWebFetch(taskID, title: "Rendered", finalURLString: "https://example.com/rendered", text: "hello")
        fixture.model.failAssistedTask(taskID, message: "late failure")
        let result = try #require(await resultTask.value)

        #expect(result.status == .fetched)
        #expect(result.contentText == "hello")
        #expect(fixture.model.assistedTasksByID[taskID]?.status == .failed)
    }

    @Test func shutdownReleasesPendingAssistedFetch() async throws {
        let fixture = try Fixture()
        let resultTask = Task {
            await fixture.model.performAssistedWebFetch(BrowserAssistedWebFetchRequest(
                urlString: "https://example.com/pending",
                extractMode: "markdown",
                waitUntil: "load",
                timeoutMilliseconds: 10_000,
                revealImmediately: false
            ))
        }
        await Task.yield()
        fixture.model.shutdown()
        let result = try #require(await resultTask.value)

        #expect(result.status == .failed)
        #expect(result.errorMessage == "Browser feature shut down")
        fixture.cleanup()
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let historyStore: BrowserHistoryStore
        let model: BrowserFeatureModel

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("browser-feature-model-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            historyStore = BrowserHistoryStore(historyURL: root.appendingPathComponent("history.json"))
            let bookmarkStore = BrowserBookmarkStore(bookmarksURL: root.appendingPathComponent("bookmarks.json"))
            model = BrowserFeatureModel(historyStore: historyStore, bookmarkStore: bookmarkStore, nativeSourceSearchBackend: nil)
            model.sessionContextProvider = {
                BrowserFeatureModel.SessionContext(
                    selectedSessionID: "session-1",
                    activeSessionID: "session-1",
                    sessionTitlesByID: ["session-1": "Work"]
                )
            }
        }

        func cleanup() {
            model.shutdown()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
