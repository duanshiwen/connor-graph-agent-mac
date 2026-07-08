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

    @Test func defaultSearchURLUsesSelectedSearchEngine() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.defaultSearchEngine = .google

        let url = try #require(fixture.viewModel.defaultSearchURL(for: "connor search"))

        #expect(url.host == "www.google.com")
        #expect(url.path == "/search")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value == "connor search")
    }

    @Test func globalSearchWebSearchUsesSelectedDefaultSearchEngine() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.defaultSearchEngine = .baidu
        fixture.viewModel.updateGlobalSearchQuery("康纳 搜索")
        fixture.viewModel.performGlobalSearchWebSearch()

        let url = try #require(URL(string: fixture.viewModel.browserTargetURLString))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.host == "www.baidu.com")
        #expect(url.path == "/s")
        #expect(components.queryItems?.first(where: { $0.name == "wd" })?.value == "康纳 搜索")
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
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

    @Test func showAllMailCarriesGlobalSearchQueryIntoMailFilter() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let account = MailAccount(id: accountID, provider: .genericIMAPSMTP, displayName: "诗闻邮箱", identities: [])
        let mailbox = MailMailbox(id: mailboxID, accountID: accountID, name: "收件箱", path: "INBOX", role: .inbox)
        let matching = MailMessageSummary(
            id: MailMessageID(rawValue: "matching-mail"),
            accountID: accountID,
            mailboxID: mailboxID,
            subject: "林北 全国二线中高端外国岗位",
            from: MailAddress(email: "jobs@example.com"),
            to: [MailAddress(email: "shiwen@example.com")],
            date: Date(timeIntervalSince1970: 1_783_148_400),
            snippet: "#外国女 #兼职"
        )
        let other = MailMessageSummary(
            id: MailMessageID(rawValue: "other-mail"),
            accountID: accountID,
            mailboxID: mailboxID,
            subject: "Apple Store 订单",
            from: MailAddress(email: "store@example.com"),
            to: [MailAddress(email: "shiwen@example.com")],
            date: Date(timeIntervalSince1970: 1_783_148_401),
            snippet: "西湖店取货提醒"
        )
        fixture.viewModel.mailBrowserPresentation = NativeMailBrowserPresentation(
            accounts: [account],
            mailboxes: [mailbox],
            messages: [other, matching]
        )
        fixture.viewModel.updateGlobalSearchQuery("外国")

        fixture.viewModel.showAllGlobalSearchResults(kind: .mail)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.mailSearchQuery == "外国")
        #expect(fixture.viewModel.mailListMessages(direction: .all).map(\.id.rawValue) == ["matching-mail"])
    }

    @Test func openingMailSearchResultSelectsMessageContextAndClearsMailFilter() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "global-mail-target", subject: "全国二线中高端岗位")
        let other = makeMailFixture(messageID: "global-mail-other", subject: "Apple Store 订单")
        fixture.viewModel.mailBrowserPresentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [other.summary, mail.summary]
        )
        fixture.viewModel.mailSearchQuery = "旧筛选词"
        fixture.viewModel.isGlobalSearchOverlayPresented = true

        fixture.viewModel.openGlobalSearchResult(mail.searchResult)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.selectedMailMessageID == mail.summary.id)
        #expect(fixture.viewModel.selectedMailAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.selectedMailMailboxID == mail.summary.mailboxID)
        #expect(fixture.viewModel.mailListMessages(direction: .all).contains { $0.id == mail.summary.id })
        #expect(fixture.viewModel.mailSearchQuery.isEmpty)
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
    }

    @Test func openingMailSearchResultAcceptsPrefixedExternalID() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "prefixed-mail-target", subject: "带前缀的邮件结果")
        fixture.viewModel.mailBrowserPresentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )
        var result = mail.searchResult
        result.externalID = "mail:\(mail.summary.id.rawValue)"

        fixture.viewModel.openGlobalSearchResult(result)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.selectedMailMessageID == mail.summary.id)
        #expect(fixture.viewModel.selectedMailAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.selectedMailMailboxID == mail.summary.mailboxID)
    }

    @Test func openingMailSearchResultAcceptsLegacySluggedExternalID() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "yakii_d@icloud.com-INBOX-100", subject: "旧索引邮件结果")
        fixture.viewModel.mailBrowserPresentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )
        var result = mail.searchResult
        result.id = "mail:mail-yakii-d-icloud-com-INBOX-100"
        result.externalID = "mail-yakii-d-icloud-com-INBOX-100"

        fixture.viewModel.openGlobalSearchResult(result)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.selectedMailMessageID == mail.summary.id)
        #expect(fixture.viewModel.selectedMailAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.selectedMailMailboxID == mail.summary.mailboxID)
    }

    @Test func performingSelectedMailSearchItemSelectsMessageContext() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "keyboard-mail-target", subject: "键盘打开邮件")
        fixture.viewModel.mailBrowserPresentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )
        fixture.viewModel.globalSearchPreviewState = GlobalSearchPreviewState(
            query: "键盘",
            mailResults: [mail.searchResult],
            searchTokens: ["键盘"]
        )
        fixture.viewModel.globalSearchSelectedItem = .nativeResult(mail.searchResult.id)
        fixture.viewModel.isGlobalSearchOverlayPresented = true

        fixture.viewModel.performSelectedGlobalSearchItem()

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.selectedMailMessageID == mail.summary.id)
        #expect(fixture.viewModel.selectedMailAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.selectedMailMailboxID == mail.summary.mailboxID)
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
    }

    @Test func openingMailSearchResultShowsLocatingStateWhileLoadingFromStore() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "locating-mail-target", subject: "正在定位的搜索邮件")
        fixture.viewModel.mailBrowserPresentation = .empty
        fixture.viewModel.isGlobalSearchOverlayPresented = true

        fixture.viewModel.openGlobalSearchResult(mail.searchResult)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.selectedMailMessageID == mail.summary.id)
        #expect(fixture.viewModel.mailNavigationTargetID == mail.summary.id)
        #expect(fixture.viewModel.mailNavigationMessage == "正在打开搜索结果中的邮件…")
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
    }

    @Test func openingMailSearchResultLoadsMessageFromStoreWhenPresentationIsStale() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "stale-presentation-mail", subject: "缓存中存在但展示未刷新")
        let store = FileBackedMailSourceStore(storagePaths: fixture.paths)
        try await store.saveAccount(mail.account)
        try await store.saveMailbox(mail.mailbox)
        try await store.saveMessage(mail.detail)
        fixture.viewModel.mailBrowserPresentation = .empty
        fixture.viewModel.mailSearchQuery = "旧筛选词"
        fixture.viewModel.isGlobalSearchOverlayPresented = true

        fixture.viewModel.openGlobalSearchResult(mail.searchResult)
        for _ in 0..<20 {
            if fixture.viewModel.selectedMailAccountID == mail.summary.accountID,
               fixture.viewModel.selectedMailMailboxID == mail.summary.mailboxID {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.selectedMailMessageID == mail.summary.id)
        #expect(fixture.viewModel.selectedMailAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.selectedMailMailboxID == mail.summary.mailboxID)
        #expect(fixture.viewModel.selectedMailMessageForDetail()?.id == mail.summary.id)
        #expect(fixture.viewModel.mailBrowserPresentation.message(id: mail.summary.id) != nil)
        #expect(fixture.viewModel.mailListMessages(direction: .all).contains { $0.id == mail.summary.id })
        #expect(fixture.viewModel.mailSearchQuery.isEmpty)
        #expect(!fixture.viewModel.isGlobalSearchOverlayPresented)
    }

    @Test func selectedMailDetailUsesSearchSelectionSummaryWhenPresentationIsMissing() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "detail-fallback-mail", subject: "搜索打开后详情可见")
        fixture.viewModel.mailBrowserPresentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )

        fixture.viewModel.openGlobalSearchResult(mail.searchResult)
        fixture.viewModel.mailBrowserPresentation = .empty

        #expect(fixture.viewModel.selectedMailMessageID == mail.summary.id)
        #expect(fixture.viewModel.selectedMailMessageForDetail()?.id == mail.summary.id)

        await fixture.viewModel.reloadMailBrowserPresentation()

        #expect(fixture.viewModel.selectedMailMessageID == mail.summary.id)
        #expect(fixture.viewModel.selectedMailMessageForDetail()?.id == mail.summary.id)
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

    @Test func globalSearchSectionStatusMessagesReflectIndexHealth() throws {
        #expect(AppViewModel.globalSearchSectionStatusMessage(
            for: .mail,
            health: NativeSourceSearchHealthSnapshot(documentCountBySource: [:])
        ) == "尚未建立索引")
        #expect(AppViewModel.globalSearchSectionStatusMessage(
            for: .rss,
            health: NativeSourceSearchHealthSnapshot(documentCountBySource: [.rss: 12], pendingUpdateCount: 2)
        ) == "后台正在更新索引，先显示已索引结果")
        #expect(AppViewModel.globalSearchSectionStatusMessage(
            for: .browserHistory,
            health: NativeSourceSearchHealthSnapshot(documentCountBySource: [.browserHistory: 4], staleSourceKinds: [.browserHistory])
        ) == "索引可能过期，先显示上次索引结果")
        #expect(AppViewModel.globalSearchSectionStatusMessage(
            for: .calendar,
            health: NativeSourceSearchHealthSnapshot(documentCountBySource: [.calendar: 3])
        ) == nil)
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

    @Test func globalSearchIncludesMailResultsInFallbackPreview() async throws {
        let viewModel = AppViewModel(entities: [], statements: [], observeLogEntries: [])
        let mails = (0..<5).map { index in
            makeMailFixture(messageID: "fallback-mail-\(index)", subject: "Phoenix mail \(index)")
        }
        viewModel.mailBrowserPresentation = NativeMailBrowserPresentation(
            accounts: [mails[0].account],
            mailboxes: [mails[0].mailbox],
            messages: mails.map(\.summary)
        )
        viewModel.updateGlobalSearchQuery("Phoenix")

        await viewModel.refreshGlobalSearchPreview(for: "Phoenix")

        #expect(viewModel.globalSearchPreviewState.mailResults.count == 3)
        #expect(viewModel.globalSearchPreviewState.mailResults.allSatisfy { $0.sourceKind == .mail })
        #expect(viewModel.globalSearchPreviewState.mailResults.allSatisfy { $0.title.contains("Phoenix mail") })
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
        return Fixture(root: root, paths: paths, viewModel: viewModel, repository: repository)
    }

    private func makeMailFixture(messageID: String, subject: String) -> MailFixture {
        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let date = Date(timeIntervalSince1970: 1_783_148_400)
        let account = MailAccount(id: accountID, provider: .genericIMAPSMTP, displayName: "诗闻邮箱", identities: [])
        let mailbox = MailMailbox(id: mailboxID, accountID: accountID, name: "收件箱", path: "INBOX", role: .inbox)
        let summary = MailMessageSummary(
            id: MailMessageID(rawValue: messageID),
            accountID: accountID,
            mailboxID: mailboxID,
            subject: subject,
            from: MailAddress(email: "sender@example.com"),
            to: [MailAddress(email: "shiwen@example.com")],
            date: date,
            snippet: "全局搜索邮件摘要"
        )
        let detail = MailMessageDetail(
            summary: summary,
            headers: MailMessageHeaders(messageIDHeader: "<\(messageID)@example.com>"),
            body: MailMessageBody(redactedPreview: "全局搜索邮件摘要")
        )
        let result = NativeSearchResult(
            id: "mail:\(messageID)",
            sourceKind: .mail,
            externalID: messageID,
            sourceInstanceID: accountID.rawValue,
            title: subject,
            snippet: "sender@example.com · 全局搜索邮件摘要",
            score: 1,
            lexicalScore: 1,
            freshnessScore: 1,
            fieldScore: 1,
            temporal: NativeSearchTemporalMetadata(primaryTime: date, primaryTimeKind: .sentAt, sentAt: date),
            resultTimeLabel: date.connorLocalFormatted(date: .medium, time: .short)
        )
        return MailFixture(account: account, mailbox: mailbox, summary: summary, detail: detail, searchResult: result)
    }

    private struct MailFixture {
        var account: MailAccount
        var mailbox: MailMailbox
        var summary: MailMessageSummary
        var detail: MailMessageDetail
        var searchResult: NativeSearchResult
    }

    private struct Fixture {
        var root: URL
        var paths: AppStoragePaths
        var viewModel: AppViewModel
        var repository: AppChatSessionRepository

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
