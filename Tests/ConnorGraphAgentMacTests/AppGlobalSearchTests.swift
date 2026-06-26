import AppKit
import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct AppGlobalSearchTests {
    @Test func updateGlobalSearchQueryShowsAndClearsOverlay() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.sessionSearchQuery = "existing session filter"
        fixture.viewModel.updateGlobalSearchQuery(" quarterly planning ")

        #expect(fixture.viewModel.globalSearchQuery == " quarterly planning ")
        #expect(fixture.viewModel.sessionSearchQuery == "existing session filter")
        #expect(fixture.viewModel.isGlobalSearchOverlayPresented)
        #expect(fixture.viewModel.globalSearchPreviewState.query == "quarterly planning")
        #expect(!fixture.viewModel.globalSearchPreviewState.isLoading)

        fixture.viewModel.clearGlobalSearch()

        #expect(fixture.viewModel.globalSearchQuery.isEmpty)
        #expect(fixture.viewModel.sessionSearchQuery == "existing session filter")
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
        #expect(fixture.viewModel.globalSearchPreviewState == .empty)
    }

    @Test func focusRestoresOverlayForExistingQueryAndBlurDismissesIt() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.updateGlobalSearchQuery("invoice")
        fixture.viewModel.dismissGlobalSearchOverlay()

        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)

        fixture.viewModel.activateGlobalSearchField()

        #expect(fixture.viewModel.isGlobalSearchFieldFocused)
        #expect(fixture.viewModel.isGlobalSearchOverlayPresented)

        fixture.viewModel.deactivateGlobalSearchField()

        #expect(!fixture.viewModel.isGlobalSearchFieldFocused)
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
        #expect(fixture.viewModel.globalSearchQuery == "invoice")
    }

    @Test func showAllGlobalSearchResultsNavigatesToSourceLists() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.updateGlobalSearchQuery("invoice")
        fixture.viewModel.showAllGlobalSearchResults(kind: .mail)

        #expect(fixture.viewModel.selection == .mail)
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)

        fixture.viewModel.updateGlobalSearchQuery("standup")
        fixture.viewModel.showAllGlobalSearchResults(kind: .calendar)

        #expect(fixture.viewModel.selection == .calendar)

        fixture.viewModel.updateGlobalSearchQuery("swift")
        fixture.viewModel.showAllGlobalSearchResults(kind: .rss)

        #expect(fixture.viewModel.selection == .rss)

        fixture.viewModel.updateGlobalSearchQuery("docs")
        fixture.viewModel.showAllGlobalSearchResults(kind: .browserHistory)

        #expect(fixture.viewModel.selection == .agentChat)
        #expect(fixture.viewModel.isBrowserVisible)
        #expect(fixture.viewModel.isBrowserHistoryPanelVisible)
    }

    @Test func showAllBrowserHistoryCarriesGlobalSearchQueryIntoHistoryFilter() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        fixture.viewModel.recordBrowserHistory(url: "https://example.com/thailand", title: "泰国签证指南", sessionID: sessionID)
        fixture.viewModel.recordBrowserHistory(url: "https://example.com/vietnam", title: "越南旅行记录", sessionID: sessionID)
        fixture.viewModel.updateGlobalSearchQuery("泰国")

        fixture.viewModel.showAllGlobalSearchResults(kind: .browserHistory)

        #expect(fixture.viewModel.browserHistorySearchQuery == "泰国")
        #expect(fixture.viewModel.filteredBrowserHistoryRecords.map(\.title) == ["泰国签证指南"])
    }

    @Test func globalSearchSectionEmptyTitlesCoverEverySource() {
        #expect(GlobalSearchSectionKind.chatSessions.emptyTitle == "没有匹配的对话")
        #expect(GlobalSearchSectionKind.mail.emptyTitle == "没有匹配的邮件")
        #expect(GlobalSearchSectionKind.calendar.emptyTitle == "没有匹配的日程")
        #expect(GlobalSearchSectionKind.rss.emptyTitle == "没有匹配的 RSS")
        #expect(GlobalSearchSectionKind.browserHistory.emptyTitle == "没有匹配的浏览历史")
    }

    @Test func globalSearchProvidesDisplayTokensForChineseQueries() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.updateGlobalSearchQuery("泰国数字游民签证")
        await fixture.viewModel.refreshGlobalSearchPreview(for: "泰国数字游民签证")

        #expect(fixture.viewModel.globalSearchPreviewState.searchTokens.contains("泰国数字游民签证"))
        #expect(fixture.viewModel.globalSearchPreviewState.searchTokens.contains("泰国"))
    }

    @Test func globalSearchDisplayTokensHideLowValueQuestionFillers() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.updateGlobalSearchQuery("去雅加达玩一个星期需要多少钱")
        await fixture.viewModel.refreshGlobalSearchPreview(for: "去雅加达玩一个星期需要多少钱")

        let tokens = fixture.viewModel.globalSearchPreviewState.searchTokens
        #expect(tokens.contains("雅加达"))
        #expect(!tokens.contains("一个"))
        #expect(!tokens.contains("星期"))
        #expect(!tokens.contains("需要"))
        #expect(!tokens.contains("多少"))
    }

    @Test func globalSearchDisplayTokensHideFallbackCJKGrams() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.updateGlobalSearchQuery("西雅图不相信眼泪")
        await fixture.viewModel.refreshGlobalSearchPreview(for: "西雅图不相信眼泪")

        let tokens = fixture.viewModel.globalSearchPreviewState.searchTokens
        #expect(tokens.contains("西雅图不相信眼泪"))
        #expect(tokens.contains("西雅图"))
        #expect(tokens.contains("相信"))
        #expect(tokens.contains("眼泪"))
        #expect(!tokens.contains("雅图"))
        #expect(!tokens.contains("图不"))
        #expect(!tokens.contains("不相"))
        #expect(!tokens.contains("信眼"))
    }

    @Test func globalSearchMarksLoadingBySectionInsteadOfGlobally() throws {
        var state = GlobalSearchPreviewState(query: "泰国", loadingSections: [.mail, .rss], searchTokens: ["泰国"])

        #expect(state.isSectionLoading(.mail))
        #expect(state.isSectionLoading(.rss))
        #expect(!state.isSectionLoading(.chatSessions))
        #expect(state.isLoading)

        state.loadingSections.remove(.mail)
        state.loadingSections.remove(.rss)

        #expect(!state.isLoading)
    }

    @Test func globalSearchTimeoutErrorsAreNotShownAsUserFacingPreviewErrors() throws {
        let error = GlobalSearchTimeoutError.hardTimeout(milliseconds: 800)

        #expect(AppViewModel.userFacingGlobalSearchErrorMessage(for: error) == nil)
        #expect(AppViewModel.userFacingGlobalSearchErrorMessage(for: NSError(domain: "test", code: 1)) != nil)
    }

    @Test func globalSearchMatchesChineseSentenceQueriesInChatSessions() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(
            title: "海外生活研究",
            messages: [AgentMessage(role: .user, content: "请帮我整理泰国数字游民签证的资料")]
        )
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.updateGlobalSearchQuery("帮我找泰国签证")

        await fixture.viewModel.refreshGlobalSearchPreview(for: "帮我找泰国签证")

        let result = try #require(fixture.viewModel.globalSearchPreviewState.chatSessionResults.first { $0.id == session.id })
        #expect(result.snippet.contains("泰国"))
    }

    @Test func globalSearchIncludesChatSessionTitleResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国长期生活计划")
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.updateGlobalSearchQuery("泰国")

        await fixture.viewModel.refreshGlobalSearchPreview(for: "泰国")

        #expect(fixture.viewModel.globalSearchPreviewState.chatSessionResults.map(\.id).contains(session.id))
        #expect(fixture.viewModel.globalSearchPreviewState.chatSessionResults.first(where: { $0.id == session.id })?.title == "泰国长期生活计划")
    }

    @Test func globalSearchIncludesChatSessionMessageBodyResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(
            title: "海外生活研究",
            messages: [AgentMessage(role: .user, content: "请帮我整理泰国数字游民签证的资料")]
        )
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.updateGlobalSearchQuery("泰国")

        await fixture.viewModel.refreshGlobalSearchPreview(for: "泰国")

        let result = try #require(fixture.viewModel.globalSearchPreviewState.chatSessionResults.first { $0.id == session.id })
        #expect(result.snippet.contains("泰国"))
        #expect(result.messageCount == 1)
    }

    @Test func openingChatSessionSearchResultSelectsSession() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国行程")
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()

        fixture.viewModel.openGlobalSearchChatSessionResult(session.id)

        #expect(fixture.viewModel.selection == .agentChat)
        #expect(fixture.viewModel.selectedChatSessionID == session.id)
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
    }

    @Test func globalSearchKeyboardSelectionMovesAcrossActionsAndResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国行程")
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.updateGlobalSearchQuery("泰国")
        await fixture.viewModel.refreshGlobalSearchPreview(for: "泰国")

        #expect(fixture.viewModel.globalSearchSelectedItem == .action(.newChat))
        fixture.viewModel.moveGlobalSearchSelectionDown()
        #expect(fixture.viewModel.globalSearchSelectedItem == .action(.webSearch))
        fixture.viewModel.moveGlobalSearchSelectionDown()
        #expect(fixture.viewModel.globalSearchSelectedItem == .chatSession(session.id))
        fixture.viewModel.moveGlobalSearchSelectionUp()
        #expect(fixture.viewModel.globalSearchSelectedItem == .action(.webSearch))
    }

    @Test func performingSelectedChatSessionSearchItemSelectsSession() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国行程")
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.updateGlobalSearchQuery("泰国")
        await fixture.viewModel.refreshGlobalSearchPreview(for: "泰国")
        fixture.viewModel.moveGlobalSearchSelectionDown()
        fixture.viewModel.moveGlobalSearchSelectionDown()

        fixture.viewModel.performSelectedGlobalSearchItem()

        #expect(fixture.viewModel.selectedChatSessionID == session.id)
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
    }

    @Test func globalSearchIncludesBrowserHistoryResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        fixture.viewModel.recordBrowserHistory(url: "https://example.com/swift-history", title: "Swift History", sessionID: sessionID)
        fixture.viewModel.updateGlobalSearchQuery("swift-history")

        await fixture.viewModel.refreshGlobalSearchPreview(for: "swift-history")

        #expect(fixture.viewModel.globalSearchPreviewState.browserHistoryResults.count == 1)
        #expect(fixture.viewModel.globalSearchPreviewState.browserHistoryResults.first?.title == "Swift History")
    }

    @Test func globalSearchKeepsPreviewLimitedBrowserHistoryPages() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        for index in 0..<5 {
            fixture.viewModel.recordBrowserHistory(url: "https://example.com/paged-history-\(index)", title: "Paged History \(index)", sessionID: sessionID)
        }
        fixture.viewModel.updateGlobalSearchQuery("paged-history")

        await fixture.viewModel.refreshGlobalSearchPreview(for: "paged-history")

        #expect(fixture.viewModel.globalSearchPreviewState.browserHistoryResults.count == 3)
    }

    @Test func openingBrowserHistoryResultFocusesExistingTab() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        let urlString = "https://example.com/open-tab"
        let tabID = UUID()
        fixture.viewModel.browserWorkspaceSnapshotsBySessionID[sessionID] = AppBrowserStateSnapshot(
            tabs: [
                AppBrowserTabSnapshot(
                    id: tabID,
                    initialURLString: urlString,
                    title: "Open Tab",
                    currentURLString: urlString
                )
            ],
            selectedTabID: nil
        )
        let record = BrowserHistoryRecord(url: urlString, title: "Open Tab", sessionID: sessionID, sessionTitle: "Session")

        fixture.viewModel.openGlobalSearchBrowserHistoryResult(record)

        #expect(fixture.viewModel.selection == .agentChat)
        #expect(fixture.viewModel.isBrowserVisible)
        #expect(fixture.viewModel.browserWorkspaceSessionID == sessionID)
        #expect(fixture.viewModel.browserWorkspaceSnapshotsBySessionID[sessionID]?.selectedTabID == tabID)
    }

    @Test func openingBrowserHistoryResultCreatesSessionWhenOriginalSessionIsMissing() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let originalSessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        let urlString = "https://example.com/deleted-session"
        let record = BrowserHistoryRecord(url: urlString, title: "Deleted Session Page", sessionID: "missing-session", sessionTitle: "Deleted")

        fixture.viewModel.openGlobalSearchBrowserHistoryResult(record)

        let newSessionID = try #require(fixture.viewModel.selectedChatSessionID)
        #expect(newSessionID != originalSessionID)
        #expect(fixture.viewModel.selection == .agentChat)
        #expect(fixture.viewModel.isBrowserVisible)
        #expect(fixture.viewModel.browserWorkspaceSessionID == newSessionID)
        #expect(fixture.viewModel.browserWorkspaceSnapshotsBySessionID[newSessionID]?.tabs.contains { $0.currentURLString == urlString || $0.initialURLString == urlString } == true)
    }

    private func makeFixture() throws -> Fixture {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-app-global-search-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        let graphRepository = try AppGraphRepository.bootstrap(paths: paths)
        let viewModel = AppViewModel(
            entities: [],
            statements: [],
            observeLogEntries: [],
            repository: graphRepository,
            databasePath: paths.databaseURL.path,
            storagePaths: paths
        )
        let repository = AppChatSessionRepository(store: graphRepository.store, storagePaths: paths)
        return Fixture(root: root, viewModel: viewModel, repository: repository)
    }

    private struct Fixture {
        var root: URL
        var viewModel: AppViewModel
        var repository: AppChatSessionRepository

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
