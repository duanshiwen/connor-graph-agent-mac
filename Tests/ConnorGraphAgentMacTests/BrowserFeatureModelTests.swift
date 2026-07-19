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

    @Test func downloadStateCanBeCancelledAndClearedWithoutLateFailureOverride() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let id = UUID()
        let preparing = BrowserDownloadItem(
            id: id,
            sourceURL: URL(string: "https://example.com/archive.zip"),
            filename: "archive.zip",
            destinationURL: nil,
            progress: 0,
            status: .preparing,
            errorMessage: nil,
            startedAt: Date()
        )

        fixture.model.updateDownload(preparing)
        fixture.model.markDownloadCancelled(id)
        var lateFailure = preparing
        lateFailure.status = .failed
        lateFailure.errorMessage = "cancelled"
        fixture.model.updateDownload(lateFailure)

        #expect(fixture.model.downloadItems.first?.status == .cancelled)
        fixture.model.clearCompletedDownloads()
        #expect(fixture.model.downloadItems.isEmpty)
    }

    @Test func sitePermissionsPersistPerOriginAndCanBeReset() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let origin = "https://example.com"

        fixture.model.setPermissionDecision(.allow, for: origin, kind: .camera)
        fixture.model.setPermissionDecision(.deny, for: origin, kind: .microphone)

        #expect(fixture.model.permissionDecision(for: origin, kind: .camera) == .allow)
        #expect(fixture.model.permissionDecision(for: origin, kind: .microphone) == .deny)

        let reloaded = BrowserFeatureModel(
            historyStore: nil,
            bookmarkStore: nil,
            nativeSourceSearchBackend: nil,
            userDefaults: fixture.userDefaults
        )
        #expect(reloaded.permissionDecision(for: origin, kind: .camera) == .allow)
        reloaded.resetPermissions(for: origin)
        #expect(reloaded.permissionDecision(for: origin, kind: .camera) == nil)
        reloaded.shutdown()
    }

    @Test func recentHistoryFallbackSearchesCurrentInMemoryRecords() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.model.recordHistory(
            url: "https://www.microsoftstore.com.cn/surface/surface-laptop",
            title: "认识 Surface Laptop",
            sessionID: "session-1"
        )

        let results = fixture.model.recentFallbackSearchResults(
            query: "Surface Laptop",
            now: Date(),
            limit: 3
        )

        #expect(results.count == 1)
        #expect(results.first?.title == "认识 Surface Laptop")
    }

    @Test func readerPageEscapesUntrustedPageContent() {
        let html = BrowserReaderPage.html(BrowserReaderPayload(
            title: "<script>alert('title')</script>",
            url: "https://example.com/?q=\"unsafe\"&x=1",
            text: "Hello <img src=x onerror=alert(1)> & goodbye"
        ))

        #expect(!html.contains("<script>alert"))
        #expect(!html.contains("<img src=x"))
        #expect(html.contains("&lt;script&gt;"))
        #expect(html.contains("&lt;img src=x onerror=alert(1)&gt; &amp; goodbye"))
        #expect(html.contains("q=&quot;unsafe&quot;&amp;x=1"))
    }

    @Test func webViewCompatibilityDelegatesRemainWiredAndUserAgentIsNative() throws {
        let source = try String(contentsOf: browserProjectSourceURL(named: "BrowserLiveWebViewStore.swift"), encoding: .utf8)

        #expect(source.contains("runOpenPanelWith parameters"))
        #expect(source.contains("runJavaScriptAlertPanelWithMessage"))
        #expect(source.contains("requestMediaCapturePermissionFor origin"))
        #expect(source.contains("didBecome download"))
        #expect(source.contains("webViewDidClose"))
        #expect(source.contains("webViewWebContentProcessDidTerminate"))
        #expect(!source.contains("customUserAgent"))
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let historyStore: BrowserHistoryStore
        let model: BrowserFeatureModel
        let userDefaults: UserDefaults
        let userDefaultsSuiteName: String

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("browser-feature-model-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            historyStore = BrowserHistoryStore(historyURL: root.appendingPathComponent("history.json"))
            let bookmarkStore = BrowserBookmarkStore(bookmarksURL: root.appendingPathComponent("bookmarks.json"))
            userDefaultsSuiteName = "BrowserFeatureModelTests.\(UUID().uuidString)"
            userDefaults = try #require(UserDefaults(suiteName: userDefaultsSuiteName))
            model = BrowserFeatureModel(
                historyStore: historyStore,
                bookmarkStore: bookmarkStore,
                nativeSourceSearchBackend: nil,
                userDefaults: userDefaults
            )
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
            userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private func browserProjectSourceURL(named filename: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/ConnorGraphAgentMac")
        .appendingPathComponent(filename)
}
