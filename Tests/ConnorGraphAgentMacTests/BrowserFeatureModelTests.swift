import Foundation
import Testing
@testable import ConnorGraphAgentMac
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Suite("BrowserFeatureModel Tests")
struct BrowserFeatureModelTests {
    @Test func localHTMLPreviewPersistsRestrictedReadAccessAndReusesTab() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let workspace = fixture.root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let html = workspace.appendingPathComponent("index.html")
        try "<h1>Local preview</h1>".write(to: html, atomically: true, encoding: .utf8)

        fixture.model.openLocalHTMLPreview(fileURL: html, readAccessRootURL: workspace)
        fixture.model.openLocalHTMLPreview(fileURL: html, readAccessRootURL: workspace)

        let snapshot = try #require(fixture.model.workspaceSnapshotsBySessionID["session-1"])
        let tab = try #require(snapshot.tabs.first)
        #expect(snapshot.tabs.count == 1)
        #expect(tab.currentURLString == html.absoluteString)
        #expect(tab.localFileReadAccessPath == workspace.path)
        #expect(fixture.model.isVisible)
        #expect(fixture.model.errorMessage == nil)
    }

    @Test func localHTMLPreviewRejectsFilesOutsideWorkspaceRoot() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let workspace = fixture.root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let outside = fixture.root.appendingPathComponent("outside.html")
        try "<p>Outside</p>".write(to: outside, atomically: true, encoding: .utf8)

        fixture.model.openLocalHTMLPreview(fileURL: outside, readAccessRootURL: workspace)

        #expect(fixture.model.workspaceSnapshotsBySessionID["session-1"] == nil)
        #expect(fixture.model.errorMessage?.contains("不在当前工作区范围内") == true)
    }

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

    @Test func globalTabsPreserveSessionOwnershipAndActivateAtomically() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.model.sessionContextProvider = {
            BrowserFeatureModel.SessionContext(
                selectedSessionID: "session-1",
                activeSessionID: "session-1",
                sessionTitlesByID: ["session-1": "Research", "session-2": "Launch"]
            )
        }
        let first = AppBrowserTabSnapshot(initialURLString: "https://example.com/research", title: "Research", currentURLString: "https://example.com/research")
        let second = AppBrowserTabSnapshot(initialURLString: "https://example.com/launch", title: "Launch", currentURLString: "https://example.com/launch")
        fixture.model.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(tabs: [first], selectedTabID: first.id), for: "session-1")
        fixture.model.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(tabs: [second], selectedTabID: second.id), for: "session-2")
        var shownSessionID: String?
        fixture.model.onShowWorkspace = { shownSessionID = $0 }

        let reference = try #require(fixture.model.globalTabs.first(where: { $0.reference.sessionID == "session-2" })?.reference)
        #expect(fixture.model.activateGlobalTab(reference))

        #expect(fixture.model.globalTabs.map(\.sessionTitle) == ["Research", "Launch"])
        #expect(fixture.model.workspaceSessionID == "session-2")
        #expect(fixture.model.workspaceSnapshotsBySessionID["session-2"]?.selectedTabID == second.id)
        #expect(shownSessionID == "session-2")
    }

    @Test func globalTabOrderPersistsAndRemovedSessionIsPurged() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = AppBrowserTabSnapshot(initialURLString: "https://example.com/one", currentURLString: "https://example.com/one")
        let second = AppBrowserTabSnapshot(initialURLString: "https://example.com/two", currentURLString: "https://example.com/two")
        fixture.model.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(tabs: [first], selectedTabID: first.id), for: "session-1")
        fixture.model.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(tabs: [second], selectedTabID: second.id), for: "session-2")

        let reloaded = BrowserFeatureModel(
            historyStore: nil,
            bookmarkStore: nil,
            nativeSourceSearchBackend: nil,
            userDefaults: fixture.userDefaults
        )
        reloaded.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(tabs: [first], selectedTabID: first.id), for: "session-1")
        reloaded.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(tabs: [second], selectedTabID: second.id), for: "session-2")
        #expect(reloaded.globalTabOrder.map(\.sessionID) == ["session-1", "session-2"])

        reloaded.retainWorkspaceSessions(["session-2"])
        #expect(reloaded.globalTabOrder.map(\.sessionID) == ["session-2"])
        reloaded.shutdown()
    }

    @Test func verticalTabPreferencesPersistAcrossModelInstances() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.model.setTabLayoutMode(.vertical)
        fixture.model.setVerticalTabSidebarPinned(true)

        let reloaded = BrowserFeatureModel(
            historyStore: nil,
            bookmarkStore: nil,
            nativeSourceSearchBackend: nil,
            userDefaults: fixture.userDefaults
        )
        #expect(reloaded.tabLayoutMode == .vertical)
        #expect(reloaded.isVerticalTabSidebarPinned)
        reloaded.shutdown()
    }

    @Test func verticalTabsGroupBySessionTitleAndFilterWithoutExposingIDs() throws {
        let researchOne = BrowserGlobalTabItem(
            reference: BrowserGlobalTabReference(sessionID: "session-private-id-1", tabID: UUID()),
            sessionTitle: "产品调研",
            tab: AppBrowserTabSnapshot(
                initialURLString: "https://example.com/surface",
                title: "Surface Laptop",
                currentURLString: "https://example.com/surface"
            )
        )
        let launch = BrowserGlobalTabItem(
            reference: BrowserGlobalTabReference(sessionID: "session-private-id-2", tabID: UUID()),
            sessionTitle: "发布计划",
            tab: AppBrowserTabSnapshot(
                initialURLString: "https://example.com/launch",
                title: "Launch checklist",
                currentURLString: "https://example.com/launch"
            )
        )
        let researchTwo = BrowserGlobalTabItem(
            reference: BrowserGlobalTabReference(sessionID: "session-private-id-1", tabID: UUID()),
            sessionTitle: "产品调研",
            tab: AppBrowserTabSnapshot(
                initialURLString: "https://example.com/notes",
                title: "Interview notes",
                currentURLString: "https://example.com/notes"
            )
        )
        let builder = BrowserGlobalTabGroupBuilder()

        let groups = builder.groups(from: [researchOne, launch, researchTwo])
        #expect(groups.map(\.sessionTitle) == ["产品调研", "发布计划"])
        #expect(groups.map(\.tabs.count) == [2, 1])

        let sessionMatch = try #require(builder.groups(from: [researchOne, launch, researchTwo], query: "产品").first)
        #expect(sessionMatch.sessionTitle == "产品调研")
        #expect(sessionMatch.tabs.count == 2)

        let tabMatch = try #require(builder.groups(from: [researchOne, launch, researchTwo], query: "checklist").first)
        #expect(tabMatch.sessionTitle == "发布计划")
        #expect(tabMatch.tabs.map(\.displayTitle) == ["Launch checklist"])
    }

    @Test func closingGlobalTabKeepsOtherSessionAvailableAsReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let first = AppBrowserTabSnapshot(initialURLString: "https://example.com/one", currentURLString: "https://example.com/one")
        let second = AppBrowserTabSnapshot(initialURLString: "https://example.com/two", currentURLString: "https://example.com/two")
        fixture.model.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(tabs: [first], selectedTabID: first.id), for: "session-1")
        fixture.model.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(tabs: [second], selectedTabID: second.id), for: "session-2")
        let firstReference = BrowserGlobalTabReference(sessionID: "session-1", tabID: first.id)

        let replacement = fixture.model.replacementGlobalTab(afterClosing: firstReference)
        fixture.model.removeGlobalTab(firstReference)

        #expect(replacement == BrowserGlobalTabReference(sessionID: "session-2", tabID: second.id))
        #expect(fixture.model.workspaceSnapshotsBySessionID["session-1"]?.tabs.isEmpty == true)
        #expect(fixture.model.globalTabs.map(\.reference) == [try #require(replacement)])
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

    @Test func historyIndexFailureIsRepairedBeforeSearchContinues() async throws {
        let backend = BrowserHistoryIndexTestBackend(failFirstUpsert: true)
        let fixture = try Fixture(nativeSourceSearchBackend: backend)
        defer { fixture.cleanup() }

        fixture.model.recordHistory(
            url: "https://www.microsoftstore.com.cn/surface/surface-laptop",
            title: "认识 Surface Laptop",
            sessionID: "session-1"
        )
        await fixture.model.synchronizeHistorySearchIndex()

        #expect(await backend.indexedTitles() == ["认识 Surface Laptop"])
        #expect(await backend.rebuildCount() == 1)
    }

    @Test func historyIndexRebuildAndIncrementalWritesAreSerialized() async throws {
        let backend = BrowserHistoryIndexTestBackend(rebuildDelayNanoseconds: 40_000_000)
        let fixture = try Fixture(nativeSourceSearchBackend: backend)
        defer { fixture.cleanup() }

        fixture.model.applyStartupHistory(.success([]))
        fixture.model.recordHistory(
            url: "https://www.microsoftstore.com.cn/surface/surface-laptop",
            title: "认识 Surface Laptop",
            sessionID: "session-1"
        )
        await fixture.model.synchronizeHistorySearchIndex()

        #expect(await backend.operationLog() == ["rebuild-start", "rebuild-end", "upsert"])
        #expect(await backend.indexedTitles() == ["认识 Surface Laptop"])
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

    @Test func faviconResolverAcceptsWebIconsAndRejectsUnsupportedSchemes() {
        #expect(BrowserFaviconResolver.normalizedURLString(from: "https://example.com/icon.png") == "https://example.com/icon.png")
        #expect(BrowserFaviconResolver.normalizedURLString(from: "http://example.com/favicon.ico") == "http://example.com/favicon.ico")
        #expect(BrowserFaviconResolver.normalizedURLString(from: "data:image/png;base64,abc") == nil)
        #expect(BrowserFaviconResolver.normalizedURLString(from: NSNull()) == nil)
        #expect(BrowserFaviconResolver.javaScript.contains("/favicon.ico"))
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

        let backgroundSource = try String(contentsOf: browserProjectSourceURL(named: "BrowserBackgroundTaskRunnerView.swift"), encoding: .utf8)
        #expect(!backgroundSource.contains("customUserAgent"))
        #expect(backgroundSource.contains("assistedTaskWebView"))

        let automationSource = try String(contentsOf: browserProjectSourceURL(named: "BrowserAutomationRuntime.swift"), encoding: .utf8)
        #expect(automationSource.contains("WKContentWorld.world"))
        #expect(automationSource.contains("serialized(key:"))
        #expect(automationSource.contains("Task.detached(priority: .utility)"))
        #expect(automationSource.contains("The referenced element is obscured"))
        #expect(automationSource.contains("Sensitive fields require user handoff"))
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let historyStore: BrowserHistoryStore
        let model: BrowserFeatureModel
        let userDefaults: UserDefaults
        let userDefaultsSuiteName: String

        init(nativeSourceSearchBackend: (any NativeSourceSearchBackend)? = nil) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("browser-feature-model-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            historyStore = BrowserHistoryStore(historyURL: root.appendingPathComponent("history.json"))
            let bookmarkStore = BrowserBookmarkStore(bookmarksURL: root.appendingPathComponent("bookmarks.json"))
            userDefaultsSuiteName = "BrowserFeatureModelTests.\(UUID().uuidString)"
            userDefaults = try #require(UserDefaults(suiteName: userDefaultsSuiteName))
            model = BrowserFeatureModel(
                historyStore: historyStore,
                bookmarkStore: bookmarkStore,
                nativeSourceSearchBackend: nativeSourceSearchBackend,
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

private actor BrowserHistoryIndexTestBackend: NativeSourceSearchBackend {
    private var documentsByID: [String: NativeSearchDocument] = [:]
    private var shouldFailNextUpsert: Bool
    private var rebuildDelayNanoseconds: UInt64
    private var rebuilds = 0
    private var operations: [String] = []

    init(failFirstUpsert: Bool = false, rebuildDelayNanoseconds: UInt64 = 0) {
        self.shouldFailNextUpsert = failFirstUpsert
        self.rebuildDelayNanoseconds = rebuildDelayNanoseconds
    }

    func upsert(_ documents: [NativeSearchDocument]) async throws {
        operations.append("upsert")
        if shouldFailNextUpsert {
            shouldFailNextUpsert = false
            throw TestIndexError.upsertFailed
        }
        for document in documents { documentsByID[document.id] = document }
    }

    func delete(documentIDs: [String]) async throws {
        for id in documentIDs { documentsByID[id] = nil }
    }

    func deleteBySource(kind: NativeSearchSourceKind, sourceInstanceID: String?) async throws {
        documentsByID = documentsByID.filter { $0.value.sourceKind != kind }
    }

    func rebuildSource(kind: NativeSearchSourceKind, sourceInstanceID: String?, documents: [NativeSearchDocument]) async throws {
        operations.append("rebuild-start")
        if rebuildDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: rebuildDelayNanoseconds) }
        documentsByID = documentsByID.filter { $0.value.sourceKind != kind }
        for document in documents { documentsByID[document.id] = document }
        rebuilds += 1
        operations.append("rebuild-end")
    }

    func search(_ query: NativeSearchQuery) async throws -> [NativeSearchResult] { [] }
    func health() async -> NativeSourceSearchHealthSnapshot { NativeSourceSearchHealthSnapshot() }

    func indexedTitles() -> [String] { documentsByID.values.map(\.title).sorted() }
    func rebuildCount() -> Int { rebuilds }
    func operationLog() -> [String] { operations }

    private enum TestIndexError: Error { case upsertFailed }
}

private func browserProjectSourceURL(named filename: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/ConnorGraphAgentMac")
        .appendingPathComponent(filename)
}
