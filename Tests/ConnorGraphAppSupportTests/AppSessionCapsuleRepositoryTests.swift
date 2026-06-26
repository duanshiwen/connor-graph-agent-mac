import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("App session capsule repository")
struct AppSessionCapsuleRepositoryTests {
    @Test("save and load session state round trips")
    func saveAndLoadSessionStateRoundTrips() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let state = AppSessionStateSnapshot(
            sessionID: "session-a",
            updatedAt: Date(timeIntervalSince1970: 1_800),
            selectedPane: "browser",
            recordSummary: AppSessionRecordSummary(count: 12, updatedAt: Date(timeIntervalSince1970: 1_799)),
            attachmentSummary: AppSessionAttachmentSummary(count: 2, totalBytes: 64, updatedAt: Date(timeIntervalSince1970: 1_798))
        )

        try fixture.repository.saveState(state, sessionID: "session-a")

        let loaded = try fixture.repository.loadState(sessionID: "session-a")
        #expect(loaded == state)
    }

    @Test("session state preserves workspace reference")
    func sessionStatePreservesWorkspaceReference() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let workspace = AppSessionWorkspaceReference(
            workingDirectoryPath: "/tmp/session-project",
            source: "runtimeSettings",
            updatedAt: Date(timeIntervalSince1970: 1_900)
        )
        let state = AppSessionStateSnapshot(
            sessionID: "session-a",
            updatedAt: Date(timeIntervalSince1970: 1_901),
            workspace: workspace
        )

        try fixture.repository.saveState(state, sessionID: "session-a")

        let loaded = try fixture.repository.loadState(sessionID: "session-a")
        #expect(loaded?.workspace == workspace)
    }

    @Test("session state preserves workspace root references")
    func sessionStatePreservesWorkspaceRootReferences() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let roots = [
            AppSessionWorkspaceRootReference(id: "app", displayName: "App", path: "/tmp/session-app", role: "project", isPrimary: true, updatedAt: Date(timeIntervalSince1970: 1_900)),
            AppSessionWorkspaceRootReference(id: "docs", displayName: "Docs", path: "/tmp/session-docs", role: "docs", isPrimary: false, updatedAt: Date(timeIntervalSince1970: 1_901))
        ]
        let workspace = AppSessionWorkspaceReference(
            workingDirectoryPath: "/tmp/session-app",
            source: "session",
            updatedAt: Date(timeIntervalSince1970: 1_902),
            roots: roots
        )
        let state = AppSessionStateSnapshot(
            sessionID: "session-a",
            updatedAt: Date(timeIntervalSince1970: 1_903),
            workspace: workspace
        )

        try fixture.repository.saveState(state, sessionID: "session-a")

        let loaded = try fixture.repository.loadState(sessionID: "session-a")
        let manifest = try fixture.repository.loadManifest(sessionID: "session-a")
        #expect(loaded?.workspace?.roots == roots)
        #expect(manifest?.workspace?.roots == roots)
    }

    @Test("append and load records preserves more than ten records")
    func appendAndLoadRecordsPreservesMoreThanTenRecords() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let records = (0..<12).map { index in
            AppSessionRecord(
                id: "record-\(index)",
                sessionID: "session-a",
                kind: "selection-question",
                createdAt: Date(timeIntervalSince1970: Double(2_000 + index)),
                title: "Record \(index)",
                body: "Body \(index)",
                metadata: ["index": "\(index)"]
            )
        }
        for record in records {
            try fixture.repository.appendRecord(record, sessionID: "session-a")
        }

        let loaded = try fixture.repository.loadRecords(sessionID: "session-a")
        #expect(loaded == records)
        #expect(loaded.count == 12)

        let state = try fixture.repository.loadState(sessionID: "session-a")
        #expect(state?.recordSummary?.count == 12)

        let manifest = try fixture.repository.loadManifest(sessionID: "session-a")
        #expect(manifest?.recordSummary?.count == 12)
    }

    @Test("browser state is part of session capsule")
    func browserStateIsPartOfSessionCapsule() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let tabID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let threadID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let browser = AppBrowserStateSnapshot(
            updatedAt: Date(timeIntervalSince1970: 3_000),
            tabs: [
                AppBrowserTabSnapshot(
                    id: tabID,
                    initialURLString: "https://example.com",
                    title: "Example",
                    currentURLString: "https://example.com/article",
                    isLoading: false,
                    canGoBack: true,
                    canGoForward: false
                )
            ],
            selectedTabID: tabID,
            selectionPopover: AppBrowserSelectionPopoverSnapshot(
                tabID: tabID,
                pageURL: "https://example.com/article",
                pageTitle: "Example",
                pageText: "Full page text",
                selectedText: "Selected text",
                rect: AppBrowserSelectionRect(x: 10, y: 20, width: 120, height: 24),
                threadID: threadID
            ),
            threads: [
                threadID: AppBrowserSelectionThreadSnapshot(
                    id: threadID,
                    tabID: tabID,
                    pageURL: "https://example.com/article",
                    selectedText: "Selected text",
                    messages: [
                        AppBrowserSelectionThreadMessageSnapshot(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                            role: .user,
                            text: "Question 1",
                            createdAt: Date(timeIntervalSince1970: 3_001)
                        ),
                        AppBrowserSelectionThreadMessageSnapshot(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                            role: .user,
                            text: "Question 2",
                            createdAt: Date(timeIntervalSince1970: 3_002)
                        )
                    ]
                )
            ]
        )

        try fixture.repository.saveBrowserState(browser, sessionID: "session-a")

        let loaded = try fixture.repository.loadBrowserState(sessionID: "session-a")
        #expect(loaded == browser)
        #expect(FileManager.default.fileExists(atPath: try fixture.repository.browserStateURL(sessionID: "session-a").path))

        let state = try fixture.repository.loadState(sessionID: "session-a")
        #expect(state?.browser?.path == "browser/browser-state.json")
        #expect(state?.browser?.tabCount == 1)
        #expect(state?.browser?.threadCount == 1)
    }

    @Test("browser tab restores current URL instead of initial URL")
    func browserTabRestoresCurrentURLInsteadOfInitialURL() {
        let tab = AppBrowserTabSnapshot(
            initialURLString: "https://example.com",
            title: "Article",
            currentURLString: "https://example.com/article"
        )

        #expect(tab.restoredURLString == "https://example.com/article")
    }

    @Test("browser tab restore falls back to blank page when URLs are empty")
    func browserTabRestoreFallsBackToBlankPageWhenURLsAreEmpty() {
        let tab = AppBrowserTabSnapshot(initialURLString: "", currentURLString: "")

        #expect(tab.restoredURLString == BrowserBuiltInPage.blankURLString)
        #expect(BrowserBuiltInPage.blankHTML.contains("康纳同学 · 浏览器"))
        #expect(BrowserBuiltInPage.blankHTML.contains("康纳同学的浏览起点"))
        #expect(BrowserBuiltInPage.blankHTML.contains("每个会话都有独立的浏览标签、网页选区和工作上下文"))

        let errorHTML = BrowserBuiltInPage.errorHTML(failedURLString: "https://bad.example?q=<x>", message: "offline & blocked")
        #expect(errorHTML.contains("<title>这个页面暂时打不开</title>"))
        #expect(errorHTML.contains("康纳同学 · 页面状态"))
        #expect(errorHTML.contains("这个页面暂时打不开"))
        #expect(errorHTML.contains("换一种方式查找资料"))
        #expect(errorHTML.contains("https://bad.example?q=&lt;x&gt;"))
        #expect(errorHTML.contains("offline &amp; blocked"))
    }

    @Test("built in pages do not expose custom URL scheme to WebKit loading")
    func builtInPagesDoNotExposeCustomURLSchemeToWebKitLoading() {
        #expect(BrowserBuiltInPage.webViewBaseURL == nil)
    }

    @Test("different sessions have isolated capsules")
    func differentSessionsHaveIsolatedCapsules() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        for index in 0..<12 {
            try fixture.repository.appendRecord(
                AppSessionRecord(id: "a-\(index)", sessionID: "session-a", kind: "record", createdAt: Date(timeIntervalSince1970: Double(index))),
                sessionID: "session-a"
            )
        }
        try fixture.repository.appendRecord(
            AppSessionRecord(id: "b-0", sessionID: "session-b", kind: "record", createdAt: Date(timeIntervalSince1970: 100)),
            sessionID: "session-b"
        )

        #expect(try fixture.repository.loadRecords(sessionID: "session-a").count == 12)
        #expect(try fixture.repository.loadRecords(sessionID: "session-b").count == 1)
    }

    @Test("ensure directories creates full capsule layout")
    func ensureDirectoriesCreatesFullCapsuleLayout() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let directories = try fixture.repository.directories(sessionID: "session-a")

        for directory in directories.all {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
        #expect(directories.state.lastPathComponent == "state")
        #expect(directories.browser.lastPathComponent == "browser")
    }
}

private struct CapsuleFixture {
    var root: URL
    var repository: AppSessionCapsuleRepository

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func makeFixture() throws -> CapsuleFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorSessionCapsuleTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    return CapsuleFixture(root: root, repository: AppSessionCapsuleRepository(storagePaths: paths))
}
