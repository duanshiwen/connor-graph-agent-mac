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
        fixture.viewModel.globalSearchFeatureModel.updateQuery(" quarterly planning ")

        #expect(fixture.viewModel.globalSearchFeatureModel.query == " quarterly planning ")
        #expect(fixture.viewModel.sessionSearchQuery == "existing session filter")
        #expect(fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.viewModel.globalSearchFeatureModel.previewState.query == "quarterly planning")
        #expect(!fixture.viewModel.globalSearchFeatureModel.previewState.isLoading)

        fixture.viewModel.globalSearchFeatureModel.clear()

        #expect(fixture.viewModel.globalSearchFeatureModel.query.isEmpty)
        #expect(fixture.viewModel.sessionSearchQuery == "existing session filter")
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.viewModel.globalSearchFeatureModel.previewState == .empty)
    }

    @Test func focusRestoresOverlayForExistingQueryAndBlurDismissesIt() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.globalSearchFeatureModel.updateQuery("invoice")
        fixture.viewModel.globalSearchFeatureModel.dismissOverlay()

        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)

        fixture.viewModel.globalSearchFeatureModel.activateField()

        #expect(fixture.viewModel.globalSearchFeatureModel.isFieldFocused)
        #expect(fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)

        fixture.viewModel.globalSearchFeatureModel.deactivateField()

        #expect(!fixture.viewModel.globalSearchFeatureModel.isFieldFocused)
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.viewModel.globalSearchFeatureModel.query == "invoice")
    }

    @Test func focusEmptyGlobalSearchShowsRecentSearches() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.globalSearchFeatureModel.recordHistoryForTesting(query: "SwiftUI 搜索")
        fixture.viewModel.globalSearchFeatureModel.query = ""

        fixture.viewModel.globalSearchFeatureModel.activateField()

        #expect(fixture.viewModel.globalSearchFeatureModel.isFieldFocused)
        #expect(fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.viewModel.globalSearchFeatureModel.selectableItems == [.recentSearch("swiftui 搜索")])
    }

    @Test func emptyQueryWithoutHistoryDoesNotShowOverlay() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.globalSearchFeatureModel.activateField()

        #expect(fixture.viewModel.globalSearchFeatureModel.isFieldFocused)
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.viewModel.globalSearchFeatureModel.selectableItems.isEmpty)
    }

    @Test func selectingRecentSearchFillsQueryAndRefreshesPreview() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.globalSearchFeatureModel.recordHistoryForTesting(query: "Mail sync")
        let entry = try #require(fixture.viewModel.globalSearchFeatureModel.historyEntries.first)

        fixture.viewModel.globalSearchFeatureModel.selectHistoryEntry(entry)

        #expect(fixture.viewModel.globalSearchFeatureModel.query == "Mail sync")
        #expect(fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.viewModel.globalSearchFeatureModel.previewState.query == "Mail sync")
        #expect(fixture.viewModel.globalSearchFeatureModel.historyEntries.first?.normalizedQuery == "mail sync")
        #expect(fixture.viewModel.globalSearchFeatureModel.historyEntries.first?.useCount == 2)
    }

    @Test func globalSearchActionsRecordDeduplicatedHistory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.defaultSearchEngine = .google
        fixture.viewModel.globalSearchFeatureModel.updateQuery("  SwiftUI   Search  ")
        fixture.viewModel.globalSearchFeatureModel.performWebSearch()

        fixture.viewModel.globalSearchFeatureModel.updateQuery("swiftui search")
        fixture.viewModel.globalSearchFeatureModel.performWebSearch()

        #expect(fixture.viewModel.globalSearchFeatureModel.historyEntries.count == 1)
        #expect(fixture.viewModel.globalSearchFeatureModel.historyEntries[0].query == "swiftui search")
        #expect(fixture.viewModel.globalSearchFeatureModel.historyEntries[0].normalizedQuery == "swiftui search")
        #expect(fixture.viewModel.globalSearchFeatureModel.historyEntries[0].useCount == 2)
    }

    @Test func clearGlobalSearchHistoryClearsEntriesAndDismissesZeroStateOverlay() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.globalSearchFeatureModel.recordHistoryForTesting(query: "SwiftUI 搜索")
        fixture.viewModel.globalSearchFeatureModel.activateField()
        #expect(fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)

        fixture.viewModel.globalSearchFeatureModel.clearHistory()

        #expect(fixture.viewModel.globalSearchFeatureModel.historyEntries.isEmpty)
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.viewModel.globalSearchFeatureModel.isFieldFocused)
    }

    @Test func defaultSearchURLUsesSelectedSearchEngine() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.defaultSearchEngine = .google

        let url = try #require(fixture.viewModel.defaultSearchEngine.searchURL(for: "connor search"))

        #expect(url.host == "www.google.com")
        #expect(url.path == "/search")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value == "connor search")
    }

    @Test func globalSearchWebSearchUsesSelectedDefaultSearchEngine() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.defaultSearchEngine = .baidu
        fixture.viewModel.globalSearchFeatureModel.updateQuery("康纳 搜索")
        fixture.viewModel.globalSearchFeatureModel.performWebSearch()

        let url = try #require(URL(string: fixture.viewModel.browserFeatureModel.targetURLString))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.host == "www.baidu.com")
        #expect(url.path == "/s")
        #expect(components.queryItems?.first(where: { $0.name == "wd" })?.value == "康纳 搜索")
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func showAllGlobalSearchResultsNavigatesToSourceLists() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.globalSearchFeatureModel.updateQuery("invoice")
        fixture.viewModel.globalSearchFeatureModel.showAllResults(kind: .mail)

        #expect(fixture.viewModel.selection == .mail)
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)

        fixture.viewModel.globalSearchFeatureModel.updateQuery("standup")
        fixture.viewModel.globalSearchFeatureModel.showAllResults(kind: .calendar)

        #expect(fixture.viewModel.selection == .calendar)

        fixture.viewModel.globalSearchFeatureModel.updateQuery("swift")
        fixture.viewModel.globalSearchFeatureModel.showAllResults(kind: .rss)

        #expect(fixture.viewModel.selection == .rss)

        fixture.viewModel.globalSearchFeatureModel.updateQuery("docs")
        fixture.viewModel.globalSearchFeatureModel.showAllResults(kind: .browserHistory)

        #expect(fixture.viewModel.selection == .agentChat)
        #expect(fixture.viewModel.browserFeatureModel.isVisible)
        #expect(fixture.viewModel.browserFeatureModel.isHistoryPanelVisible)
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
        fixture.viewModel.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [account],
            mailboxes: [mailbox],
            messages: [other, matching]
        )
        fixture.viewModel.globalSearchFeatureModel.updateQuery("外国")

        fixture.viewModel.globalSearchFeatureModel.showAllResults(kind: .mail)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.mailFeatureModel.searchQuery == "外国")
        #expect(fixture.viewModel.mailFeatureModel.listMessages(direction: .all).map(\.id.rawValue) == ["matching-mail"])
    }

    @Test func openingMailSearchResultSelectsMessageContextAndClearsMailFilter() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "global-mail-target", subject: "全国二线中高端岗位")
        let other = makeMailFixture(messageID: "global-mail-other", subject: "Apple Store 订单")
        fixture.viewModel.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [other.summary, mail.summary]
        )
        fixture.viewModel.mailFeatureModel.searchQuery = "旧筛选词"
        fixture.viewModel.globalSearchFeatureModel.isOverlayPresented = true

        fixture.viewModel.globalSearchFeatureModel.openResult(mail.searchResult)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
        #expect(fixture.viewModel.mailFeatureModel.listMessages(direction: .all).contains { $0.id == mail.summary.id })
        #expect(fixture.viewModel.mailFeatureModel.searchQuery.isEmpty)
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func openingMailSearchResultAcceptsPrefixedExternalID() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "prefixed-mail-target", subject: "带前缀的邮件结果")
        fixture.viewModel.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )
        var result = mail.searchResult
        result.externalID = "mail:\(mail.summary.id.rawValue)"

        fixture.viewModel.globalSearchFeatureModel.openResult(result)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
    }

    @Test func openingMailSearchResultAcceptsLegacySluggedExternalID() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "yakii_d@icloud.com-INBOX-100", subject: "旧索引邮件结果")
        fixture.viewModel.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )
        var result = mail.searchResult
        result.id = "mail:mail-yakii-d-icloud-com-INBOX-100"
        result.externalID = "mail-yakii-d-icloud-com-INBOX-100"

        fixture.viewModel.globalSearchFeatureModel.openResult(result)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
    }

    @Test func performingSelectedMailSearchItemSelectsMessageContext() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "keyboard-mail-target", subject: "键盘打开邮件")
        fixture.viewModel.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )
        fixture.viewModel.globalSearchFeatureModel.installPreviewStateForTesting(GlobalSearchPreviewState(
            query: "键盘",
            mailResults: [mail.searchResult],
            searchTokens: ["键盘"]
        ))
        fixture.viewModel.globalSearchFeatureModel.selectedItem = .nativeResult(mail.searchResult.id)
        fixture.viewModel.globalSearchFeatureModel.isOverlayPresented = true

        fixture.viewModel.globalSearchFeatureModel.performSelectedItem()

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func openingMailSearchResultShowsLocatingStateWhileLoadingFromStore() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "locating-mail-target", subject: "正在定位的搜索邮件")
        fixture.viewModel.mailFeatureModel.presentation = .empty
        fixture.viewModel.globalSearchFeatureModel.isOverlayPresented = true

        fixture.viewModel.globalSearchFeatureModel.openResult(mail.searchResult)

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.navigationTargetID == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.navigationMessage == "正在打开搜索结果中的邮件…")
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func openingMailSearchResultLoadsMessageFromStoreWhenPresentationIsStale() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "stale-presentation-mail", subject: "缓存中存在但展示未刷新")
        let store = try #require(fixture.viewModel.mailFeatureModel.sharedStoreForTests)
        try await store.saveAccount(mail.account)
        try await store.saveMailbox(mail.mailbox)
        try await store.saveMessage(mail.detail)
        await fixture.viewModel.mailFeatureModel.reload()
        fixture.viewModel.mailFeatureModel.presentation = .empty
        fixture.viewModel.mailFeatureModel.searchQuery = "旧筛选词"
        fixture.viewModel.globalSearchFeatureModel.isOverlayPresented = true

        fixture.viewModel.globalSearchFeatureModel.openResult(mail.searchResult)
        for _ in 0..<20 {
            if fixture.viewModel.mailFeatureModel.presentation.message(id: mail.summary.id) != nil {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(fixture.viewModel.selection == .mail)
        #expect(fixture.viewModel.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.viewModel.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
        #expect(fixture.viewModel.mailFeatureModel.selectedMessageForDetail()?.id == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.presentation.message(id: mail.summary.id) != nil)
        #expect(fixture.viewModel.mailFeatureModel.listMessages(direction: .all).contains { $0.id == mail.summary.id })
        #expect(fixture.viewModel.mailFeatureModel.searchQuery.isEmpty)
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func selectedMailDetailUsesSearchSelectionSummaryWhenPresentationIsMissing() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "detail-fallback-mail", subject: "搜索打开后详情可见")
        fixture.viewModel.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )

        fixture.viewModel.globalSearchFeatureModel.openResult(mail.searchResult)
        fixture.viewModel.mailFeatureModel.presentation = .empty

        #expect(fixture.viewModel.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.selectedMessageForDetail()?.id == mail.summary.id)

        await fixture.viewModel.mailFeatureModel.reload()

        #expect(fixture.viewModel.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.viewModel.mailFeatureModel.selectedMessageForDetail()?.id == mail.summary.id)
    }

    @Test func showAllBrowserHistoryCarriesGlobalSearchQueryIntoHistoryFilter() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        fixture.viewModel.browserFeatureModel.recordHistory(url: "https://example.com/thailand", title: "泰国签证指南", sessionID: sessionID)
        fixture.viewModel.browserFeatureModel.recordHistory(url: "https://example.com/vietnam", title: "越南旅行记录", sessionID: sessionID)
        fixture.viewModel.globalSearchFeatureModel.updateQuery("泰国")

        fixture.viewModel.globalSearchFeatureModel.showAllResults(kind: .browserHistory)

        #expect(fixture.viewModel.browserFeatureModel.historySearchQuery == "泰国")
        #expect(fixture.viewModel.browserFeatureModel.filteredHistoryRecords.map(\.title) == ["泰国签证指南"])
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

        fixture.viewModel.globalSearchFeatureModel.updateQuery("泰国数字游民签证")
        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "泰国数字游民签证")

        #expect(fixture.viewModel.globalSearchFeatureModel.previewState.searchTokens.contains("泰国数字游民签证"))
        #expect(fixture.viewModel.globalSearchFeatureModel.previewState.searchTokens.contains("泰国"))
    }

    @Test func globalSearchDisplayTokensHideLowValueQuestionFillers() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.globalSearchFeatureModel.updateQuery("去雅加达玩一个星期需要多少钱")
        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "去雅加达玩一个星期需要多少钱")

        let tokens = fixture.viewModel.globalSearchFeatureModel.previewState.searchTokens
        #expect(tokens.contains("雅加达"))
        #expect(!tokens.contains("一个"))
        #expect(!tokens.contains("星期"))
        #expect(!tokens.contains("需要"))
        #expect(!tokens.contains("多少"))
    }

    @Test func globalSearchDisplayTokensHideFallbackCJKGrams() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.viewModel.globalSearchFeatureModel.updateQuery("西雅图不相信眼泪")
        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "西雅图不相信眼泪")

        let tokens = fixture.viewModel.globalSearchFeatureModel.previewState.searchTokens
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

        #expect(GlobalSearchFeatureModel.userFacingErrorMessage(for: error) == nil)
        #expect(GlobalSearchFeatureModel.userFacingErrorMessage(for: NSError(domain: "test", code: 1)) != nil)
    }

    @Test func globalSearchSectionStatusMessagesReflectIndexHealth() throws {
        #expect(GlobalSearchFeatureModel.sectionStatusMessage(
            for: .mail,
            health: NativeSourceSearchHealthSnapshot(documentCountBySource: [:])
        ) == "尚未建立索引")
        #expect(GlobalSearchFeatureModel.sectionStatusMessage(
            for: .rss,
            health: NativeSourceSearchHealthSnapshot(documentCountBySource: [.rss: 12], pendingUpdateCount: 2)
        ) == "后台正在更新索引，先显示已索引结果")
        #expect(GlobalSearchFeatureModel.sectionStatusMessage(
            for: .browserHistory,
            health: NativeSourceSearchHealthSnapshot(documentCountBySource: [.browserHistory: 4], staleSourceKinds: [.browserHistory])
        ) == "索引可能过期，先显示上次索引结果")
        #expect(GlobalSearchFeatureModel.sectionStatusMessage(
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
        fixture.viewModel.globalSearchFeatureModel.updateQuery("帮我找泰国签证")

        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "帮我找泰国签证")

        let result = try #require(fixture.viewModel.globalSearchFeatureModel.previewState.chatSessionResults.first { $0.id == session.id })
        #expect(result.snippet.contains("泰国"))
    }

    @Test func globalSearchIncludesChatSessionTitleResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国长期生活计划")
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.globalSearchFeatureModel.updateQuery("泰国")

        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "泰国")

        #expect(fixture.viewModel.globalSearchFeatureModel.previewState.chatSessionResults.map(\.id).contains(session.id))
        #expect(fixture.viewModel.globalSearchFeatureModel.previewState.chatSessionResults.first(where: { $0.id == session.id })?.title == "泰国长期生活计划")
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
        fixture.viewModel.globalSearchFeatureModel.updateQuery("泰国")

        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "泰国")

        let result = try #require(fixture.viewModel.globalSearchFeatureModel.previewState.chatSessionResults.first { $0.id == session.id })
        #expect(result.snippet.contains("泰国"))
        #expect(result.messageCount == 1)
    }

    @Test func openingChatSessionSearchResultSelectsSession() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国行程")
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()

        fixture.viewModel.globalSearchFeatureModel.openChatSession(session.id)

        #expect(fixture.viewModel.selection == .agentChat)
        #expect(fixture.viewModel.selectedChatSessionID == session.id)
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func globalSearchKeyboardSelectionMovesAcrossActionsAndResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国行程")
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.globalSearchFeatureModel.updateQuery("泰国")
        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "泰国")

        #expect(fixture.viewModel.globalSearchFeatureModel.selectedItem == .action(.newChat))
        fixture.viewModel.globalSearchFeatureModel.moveSelectionDown()
        #expect(fixture.viewModel.globalSearchFeatureModel.selectedItem == .action(.webSearch))
        fixture.viewModel.globalSearchFeatureModel.moveSelectionDown()
        #expect(fixture.viewModel.globalSearchFeatureModel.selectedItem == .chatSession(session.id))
        fixture.viewModel.globalSearchFeatureModel.moveSelectionUp()
        #expect(fixture.viewModel.globalSearchFeatureModel.selectedItem == .action(.webSearch))
    }

    @Test func performingSelectedChatSessionSearchItemSelectsSession() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国行程")
        try fixture.repository.saveSession(session)
        fixture.viewModel.reloadChatSessions()
        fixture.viewModel.globalSearchFeatureModel.updateQuery("泰国")
        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "泰国")
        fixture.viewModel.globalSearchFeatureModel.moveSelectionDown()
        fixture.viewModel.globalSearchFeatureModel.moveSelectionDown()

        fixture.viewModel.globalSearchFeatureModel.performSelectedItem()

        #expect(fixture.viewModel.selectedChatSessionID == session.id)
        #expect(!fixture.viewModel.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func globalSearchIncludesMailResultsInFallbackPreview() async throws {
        let viewModel = AppViewModel(entities: [], statements: [], observeLogEntries: [])
        let mails = (0..<5).map { index in
            makeMailFixture(messageID: "fallback-mail-\(index)", subject: "Phoenix mail \(index)")
        }
        viewModel.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mails[0].account],
            mailboxes: [mails[0].mailbox],
            messages: mails.map(\.summary)
        )
        viewModel.globalSearchFeatureModel.updateQuery("Phoenix")

        await viewModel.globalSearchFeatureModel.refreshPreview(for: "Phoenix")

        #expect(viewModel.globalSearchFeatureModel.previewState.mailResults.count == 3)
        #expect(viewModel.globalSearchFeatureModel.previewState.mailResults.allSatisfy { $0.sourceKind == .mail })
        #expect(viewModel.globalSearchFeatureModel.previewState.mailResults.allSatisfy { $0.title.contains("Phoenix mail") })
    }

    @Test func globalSearchIncludesBrowserHistoryResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        fixture.viewModel.browserFeatureModel.recordHistory(url: "https://example.com/swift-history", title: "Swift History", sessionID: sessionID)
        fixture.viewModel.globalSearchFeatureModel.updateQuery("swift-history")

        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "swift-history")

        #expect(fixture.viewModel.globalSearchFeatureModel.previewState.browserHistoryResults.count == 1)
        #expect(fixture.viewModel.globalSearchFeatureModel.previewState.browserHistoryResults.first?.title == "Swift History")
    }

    @Test func globalSearchKeepsPreviewLimitedBrowserHistoryPages() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        for index in 0..<5 {
            fixture.viewModel.browserFeatureModel.recordHistory(url: "https://example.com/paged-history-\(index)", title: "Paged History \(index)", sessionID: sessionID)
        }
        fixture.viewModel.globalSearchFeatureModel.updateQuery("paged-history")

        await fixture.viewModel.globalSearchFeatureModel.refreshPreview(for: "paged-history")

        #expect(fixture.viewModel.globalSearchFeatureModel.previewState.browserHistoryResults.count == 3)
    }

    @Test func openingBrowserHistoryResultFocusesExistingTab() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        let urlString = "https://example.com/open-tab"
        let tabID = UUID()
        fixture.viewModel.browserFeatureModel.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(
            tabs: [
                AppBrowserTabSnapshot(
                    id: tabID,
                    initialURLString: urlString,
                    title: "Open Tab",
                    currentURLString: urlString
                )
            ],
            selectedTabID: nil
        ), for: sessionID)
        let record = BrowserHistoryRecord(url: urlString, title: "Open Tab", sessionID: sessionID, sessionTitle: "Session")

        fixture.viewModel.globalSearchFeatureModel.openBrowserHistoryRecord(record)

        #expect(fixture.viewModel.selection == .agentChat)
        #expect(fixture.viewModel.browserFeatureModel.isVisible)
        #expect(fixture.viewModel.browserFeatureModel.workspaceSessionID == sessionID)
        #expect(fixture.viewModel.browserFeatureModel.workspaceSnapshotsBySessionID[sessionID]?.selectedTabID == tabID)
    }

    @Test func openingBrowserHistoryResultCreatesSessionWhenOriginalSessionIsMissing() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let originalSessionID = try #require(fixture.viewModel.selectedChatSessionID ?? fixture.viewModel.chatSessions.first?.id)
        let urlString = "https://example.com/deleted-session"
        let record = BrowserHistoryRecord(url: urlString, title: "Deleted Session Page", sessionID: "missing-session", sessionTitle: "Deleted")

        fixture.viewModel.globalSearchFeatureModel.openBrowserHistoryRecord(record)

        let newSessionID = try #require(fixture.viewModel.selectedChatSessionID)
        #expect(newSessionID != originalSessionID)
        #expect(fixture.viewModel.selection == .agentChat)
        #expect(fixture.viewModel.browserFeatureModel.isVisible)
        #expect(fixture.viewModel.browserFeatureModel.workspaceSessionID == newSessionID)
        #expect(fixture.viewModel.browserFeatureModel.workspaceSnapshotsBySessionID[newSessionID]?.tabs.contains { $0.currentURLString == urlString || $0.initialURLString == urlString } == true)
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
