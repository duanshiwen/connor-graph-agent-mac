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

        fixture.runtime.chatFeatureModel.sessions.searchQuery = "existing session filter"
        fixture.runtime.globalSearchFeatureModel.updateQuery(" quarterly planning ")

        #expect(fixture.runtime.globalSearchFeatureModel.query == " quarterly planning ")
        #expect(fixture.runtime.chatFeatureModel.sessions.searchQuery == "existing session filter")
        #expect(fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.runtime.globalSearchFeatureModel.previewState.query == "quarterly planning")
        #expect(!fixture.runtime.globalSearchFeatureModel.previewState.isLoading)

        fixture.runtime.globalSearchFeatureModel.clear()

        #expect(fixture.runtime.globalSearchFeatureModel.query.isEmpty)
        #expect(fixture.runtime.chatFeatureModel.sessions.searchQuery == "existing session filter")
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.runtime.globalSearchFeatureModel.previewState == .empty)
    }

    @Test func focusRestoresOverlayForExistingQueryAndBlurDismissesIt() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.globalSearchFeatureModel.updateQuery("invoice")
        fixture.runtime.globalSearchFeatureModel.dismissOverlay()

        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)

        fixture.runtime.globalSearchFeatureModel.activateField()

        #expect(fixture.runtime.globalSearchFeatureModel.isFieldFocused)
        #expect(fixture.runtime.globalSearchFeatureModel.isOverlayPresented)

        fixture.runtime.globalSearchFeatureModel.deactivateField()

        #expect(!fixture.runtime.globalSearchFeatureModel.isFieldFocused)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.runtime.globalSearchFeatureModel.query == "invoice")
    }

    @Test func focusEmptyGlobalSearchKeepsRecordedHistoryWithoutShowingOverlay() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.globalSearchFeatureModel.recordHistoryForTesting(query: "SwiftUI 搜索")
        fixture.runtime.globalSearchFeatureModel.query = ""

        fixture.runtime.globalSearchFeatureModel.activateField()

        #expect(fixture.runtime.globalSearchFeatureModel.isFieldFocused)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.runtime.globalSearchFeatureModel.selectableItems == [.recentSearch("swiftui 搜索")])
    }

    @Test func emptyQueryWithoutHistoryDoesNotShowOverlay() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.globalSearchFeatureModel.activateField()

        #expect(fixture.runtime.globalSearchFeatureModel.isFieldFocused)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.runtime.globalSearchFeatureModel.selectableItems.isEmpty)
    }

    @Test func selectingRecentSearchFillsQueryAndRefreshesPreview() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.globalSearchFeatureModel.recordHistoryForTesting(query: "Mail sync")
        let entry = try #require(fixture.runtime.globalSearchFeatureModel.historyEntries.first)

        fixture.runtime.globalSearchFeatureModel.selectHistoryEntry(entry)

        #expect(fixture.runtime.globalSearchFeatureModel.query == "Mail sync")
        #expect(fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.runtime.globalSearchFeatureModel.previewState.query == "Mail sync")
        #expect(fixture.runtime.globalSearchFeatureModel.historyEntries.first?.normalizedQuery == "mail sync")
        #expect(fixture.runtime.globalSearchFeatureModel.historyEntries.first?.useCount == 2)
    }

    @Test func globalSearchActionsRecordDeduplicatedHistory() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.appSettingsModel.defaultSearchEngine = .google
        fixture.runtime.globalSearchFeatureModel.onDestination = nil
        fixture.runtime.globalSearchFeatureModel.updateQuery("  SwiftUI   Search  ")
        fixture.runtime.globalSearchFeatureModel.performWebSearch()

        fixture.runtime.globalSearchFeatureModel.updateQuery("swiftui search")
        fixture.runtime.globalSearchFeatureModel.performWebSearch()

        #expect(fixture.runtime.globalSearchFeatureModel.historyEntries.count == 1)
        #expect(fixture.runtime.globalSearchFeatureModel.historyEntries[0].query == "swiftui search")
        #expect(fixture.runtime.globalSearchFeatureModel.historyEntries[0].normalizedQuery == "swiftui search")
        #expect(fixture.runtime.globalSearchFeatureModel.historyEntries[0].useCount == 2)
    }

    @Test func clearGlobalSearchHistoryClearsEntriesAndDismissesZeroStateOverlay() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.globalSearchFeatureModel.recordHistoryForTesting(query: "SwiftUI 搜索")
        fixture.runtime.globalSearchFeatureModel.activateField()
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)

        fixture.runtime.globalSearchFeatureModel.clearHistory()

        #expect(fixture.runtime.globalSearchFeatureModel.historyEntries.isEmpty)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
        #expect(fixture.runtime.globalSearchFeatureModel.isFieldFocused)
    }

    @Test func sendingGlobalSearchQueryCreatesReadySessionAndSubmitsPrompt() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.globalSearchFeatureModel.updateQuery("解释 actor isolation")
        fixture.runtime.globalSearchFeatureModel.performNewChat()

        for _ in 0..<100 {
            if fixture.runtime.chatFeatureModel.run.transcript.contains(where: { $0.content == "解释 actor isolation" }) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(fixture.runtime.selection == .agentChat)
        #expect(fixture.runtime.chatFeatureModel.sessions.selectedSessionID != nil)
        #expect(fixture.runtime.chatFeatureModel.run.transcript.contains { $0.content == "解释 actor isolation" })
        #expect(fixture.runtime.chatFeatureModel.composer.input.isEmpty)
    }

    @Test func defaultSearchURLUsesSelectedSearchEngine() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.appSettingsModel.defaultSearchEngine = .google

        let url = try #require(fixture.runtime.appSettingsModel.defaultSearchEngine.searchURL(for: "connor search"))

        #expect(url.host == "www.google.com")
        #expect(url.path == "/search")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value == "connor search")
    }

    @Test func globalSearchWebSearchCreatesDedicatedSessionWithSelectedDefaultSearchEngine() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let previousSessionID = fixture.runtime.chatFeatureModel.sessions.selectedSessionID
        fixture.runtime.appSettingsModel.defaultSearchEngine = .baidu
        fixture.runtime.globalSearchFeatureModel.updateQuery("康纳 搜索")
        fixture.runtime.globalSearchFeatureModel.performWebSearch()

        let searchSessionID = try #require(fixture.runtime.chatFeatureModel.sessions.selectedSessionID)
        #expect(searchSessionID != previousSessionID)
        #expect(fixture.runtime.chatFeatureModel.sessions.sessions.first(where: { $0.id == searchSessionID })?.title == "用户搜索：康纳 搜索")
        await fixture.runtime.waitForNewSessionPreparation(sessionID: searchSessionID)
        for _ in 0..<20 where fixture.runtime.browserFeatureModel.workspaceSessionID != searchSessionID {
            await Task.yield()
        }

        let tab = try #require(fixture.runtime.browserFeatureModel.workspaceSnapshotsBySessionID[searchSessionID]?.tabs.first)
        let url = try #require(URL(string: tab.currentURLString.isEmpty ? tab.initialURLString : tab.currentURLString))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.host == "www.baidu.com")
        #expect(url.path == "/s")
        #expect(components.queryItems?.first(where: { $0.name == "wd" })?.value == "康纳 搜索")
        #expect(fixture.runtime.browserFeatureModel.workspaceSessionID == searchSessionID)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func showAllGlobalSearchResultsNavigatesToSourceLists() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.globalSearchFeatureModel.updateQuery("invoice")
        fixture.runtime.globalSearchFeatureModel.showAllResults(kind: .mail)

        #expect(fixture.runtime.selection == .mail)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)

        fixture.runtime.globalSearchFeatureModel.updateQuery("standup")
        fixture.runtime.globalSearchFeatureModel.showAllResults(kind: .calendar)

        #expect(fixture.runtime.selection == .calendar)

        fixture.runtime.globalSearchFeatureModel.updateQuery("swift")
        fixture.runtime.globalSearchFeatureModel.showAllResults(kind: .rss)

        #expect(fixture.runtime.selection == .rss)

        fixture.runtime.globalSearchFeatureModel.updateQuery("docs")
        fixture.runtime.globalSearchFeatureModel.showAllResults(kind: .browserHistory)

        #expect(fixture.runtime.selection == .agentChat)
        #expect(fixture.runtime.browserFeatureModel.isVisible)
        #expect(fixture.runtime.browserFeatureModel.isHistoryPanelVisible)
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
        fixture.runtime.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [account],
            mailboxes: [mailbox],
            messages: [other, matching]
        )
        fixture.runtime.globalSearchFeatureModel.updateQuery("外国")

        fixture.runtime.globalSearchFeatureModel.showAllResults(kind: .mail)

        #expect(fixture.runtime.selection == .mail)
        #expect(fixture.runtime.mailFeatureModel.searchQuery == "外国")
        #expect(fixture.runtime.mailFeatureModel.listMessages(direction: .all).map(\.id.rawValue) == ["matching-mail"])
    }

    @Test func openingMailSearchResultSelectsMessageContextAndClearsMailFilter() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "global-mail-target", subject: "全国二线中高端岗位")
        let other = makeMailFixture(messageID: "global-mail-other", subject: "Apple Store 订单")
        fixture.runtime.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [other.summary, mail.summary]
        )
        fixture.runtime.mailFeatureModel.searchQuery = "旧筛选词"
        fixture.runtime.globalSearchFeatureModel.isOverlayPresented = true

        fixture.runtime.globalSearchFeatureModel.openResult(mail.searchResult)

        #expect(fixture.runtime.selection == .mail)
        #expect(fixture.runtime.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.runtime.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
        #expect(fixture.runtime.mailFeatureModel.listMessages(direction: .all).contains { $0.id == mail.summary.id })
        #expect(fixture.runtime.mailFeatureModel.searchQuery.isEmpty)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func openingMailSearchResultAcceptsPrefixedExternalID() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "prefixed-mail-target", subject: "带前缀的邮件结果")
        fixture.runtime.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )
        var result = mail.searchResult
        result.externalID = "mail:\(mail.summary.id.rawValue)"

        fixture.runtime.globalSearchFeatureModel.openResult(result)

        #expect(fixture.runtime.selection == .mail)
        #expect(fixture.runtime.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.runtime.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
    }

    @Test func openingMailSearchResultAcceptsLegacySluggedExternalID() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "yakii_d@icloud.com-INBOX-100", subject: "旧索引邮件结果")
        fixture.runtime.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )
        var result = mail.searchResult
        result.id = "mail:mail-yakii-d-icloud-com-INBOX-100"
        result.externalID = "mail-yakii-d-icloud-com-INBOX-100"

        fixture.runtime.globalSearchFeatureModel.openResult(result)

        #expect(fixture.runtime.selection == .mail)
        #expect(fixture.runtime.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.runtime.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
    }

    @Test func performingSelectedMailSearchItemSelectsMessageContext() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "keyboard-mail-target", subject: "键盘打开邮件")
        fixture.runtime.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )
        fixture.runtime.globalSearchFeatureModel.installPreviewStateForTesting(GlobalSearchPreviewState(
            query: "键盘",
            mailResults: [mail.searchResult],
            searchTokens: ["键盘"]
        ))
        fixture.runtime.globalSearchFeatureModel.selectedItem = .nativeResult(mail.searchResult.id)
        fixture.runtime.globalSearchFeatureModel.isOverlayPresented = true

        fixture.runtime.globalSearchFeatureModel.performSelectedItem()

        #expect(fixture.runtime.selection == .mail)
        #expect(fixture.runtime.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.runtime.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func openingMailSearchResultShowsLocatingStateWhileLoadingFromStore() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "locating-mail-target", subject: "正在定位的搜索邮件")
        fixture.runtime.mailFeatureModel.presentation = .empty
        fixture.runtime.globalSearchFeatureModel.isOverlayPresented = true

        fixture.runtime.globalSearchFeatureModel.openResult(mail.searchResult)

        #expect(fixture.runtime.selection == .mail)
        #expect(fixture.runtime.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.navigationTargetID == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.navigationMessage == "正在打开搜索结果中的邮件…")
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func openingMailSearchResultLoadsMessageFromStoreWhenPresentationIsStale() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "stale-presentation-mail", subject: "缓存中存在但展示未刷新")
        let store = try #require(fixture.runtime.mailFeatureModel.sharedStoreForTests)
        try await store.saveAccount(mail.account)
        try await store.saveMailbox(mail.mailbox)
        try await store.saveMessage(mail.detail)
        await fixture.runtime.mailFeatureModel.reload()
        fixture.runtime.mailFeatureModel.presentation = .empty
        fixture.runtime.mailFeatureModel.searchQuery = "旧筛选词"
        fixture.runtime.globalSearchFeatureModel.isOverlayPresented = true

        fixture.runtime.globalSearchFeatureModel.openResult(mail.searchResult)
        for _ in 0..<20 {
            if fixture.runtime.mailFeatureModel.presentation.message(id: mail.summary.id) != nil {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(fixture.runtime.selection == .mail)
        #expect(fixture.runtime.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.selectedAccountID == mail.summary.accountID)
        #expect(fixture.runtime.mailFeatureModel.selectedMailboxID == mail.summary.mailboxID)
        #expect(fixture.runtime.mailFeatureModel.selectedMessageForDetail()?.id == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.presentation.message(id: mail.summary.id) != nil)
        #expect(fixture.runtime.mailFeatureModel.listMessages(direction: .all).contains { $0.id == mail.summary.id })
        #expect(fixture.runtime.mailFeatureModel.searchQuery.isEmpty)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func selectedMailDetailUsesSearchSelectionSummaryWhenPresentationIsMissing() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let mail = makeMailFixture(messageID: "detail-fallback-mail", subject: "搜索打开后详情可见")
        fixture.runtime.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mail.account],
            mailboxes: [mail.mailbox],
            messages: [mail.summary]
        )

        fixture.runtime.globalSearchFeatureModel.openResult(mail.searchResult)
        fixture.runtime.mailFeatureModel.presentation = .empty

        #expect(fixture.runtime.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.selectedMessageForDetail()?.id == mail.summary.id)

        await fixture.runtime.mailFeatureModel.reload()

        #expect(fixture.runtime.mailFeatureModel.selectedMessageID == mail.summary.id)
        #expect(fixture.runtime.mailFeatureModel.selectedMessageForDetail()?.id == mail.summary.id)
    }

    @Test func showAllBrowserHistoryCarriesGlobalSearchQueryIntoHistoryFilter() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.runtime.chatFeatureModel.sessions.selectedSessionID ?? fixture.runtime.chatFeatureModel.sessions.sessions.first?.id)
        fixture.runtime.browserFeatureModel.recordHistory(url: "https://example.com/thailand", title: "泰国签证指南", sessionID: sessionID)
        fixture.runtime.browserFeatureModel.recordHistory(url: "https://example.com/vietnam", title: "越南旅行记录", sessionID: sessionID)
        fixture.runtime.globalSearchFeatureModel.updateQuery("泰国")

        fixture.runtime.globalSearchFeatureModel.showAllResults(kind: .browserHistory)

        #expect(fixture.runtime.browserFeatureModel.historySearchQuery == "泰国")
        #expect(fixture.runtime.browserFeatureModel.filteredHistoryRecords.map(\.title) == ["泰国签证指南"])
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

        fixture.runtime.globalSearchFeatureModel.updateQuery("泰国数字游民签证")
        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "泰国数字游民签证")

        #expect(fixture.runtime.globalSearchFeatureModel.previewState.searchTokens.contains("泰国数字游民签证"))
        #expect(fixture.runtime.globalSearchFeatureModel.previewState.searchTokens.contains("泰国"))
    }

    @Test func globalSearchDisplayTokensHideLowValueQuestionFillers() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.globalSearchFeatureModel.updateQuery("去雅加达玩一个星期需要多少钱")
        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "去雅加达玩一个星期需要多少钱")

        let tokens = fixture.runtime.globalSearchFeatureModel.previewState.searchTokens
        #expect(tokens.contains("雅加达"))
        #expect(!tokens.contains("一个"))
        #expect(!tokens.contains("星期"))
        #expect(!tokens.contains("需要"))
        #expect(!tokens.contains("多少"))
    }

    @Test func globalSearchDisplayTokensHideFallbackCJKGrams() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        fixture.runtime.globalSearchFeatureModel.updateQuery("西雅图不相信眼泪")
        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "西雅图不相信眼泪")

        let tokens = fixture.runtime.globalSearchFeatureModel.previewState.searchTokens
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
        fixture.runtime.reloadChatSessions()
        fixture.runtime.globalSearchFeatureModel.updateQuery("帮我找泰国签证")

        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "帮我找泰国签证")

        let result = try #require(fixture.runtime.globalSearchFeatureModel.previewState.chatSessionResults.first { $0.id == session.id })
        #expect(result.snippet.contains("泰国"))
    }

    @Test func globalSearchIncludesChatSessionTitleResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国长期生活计划")
        try fixture.repository.saveSession(session)
        fixture.runtime.reloadChatSessions()
        fixture.runtime.globalSearchFeatureModel.updateQuery("泰国")

        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "泰国")

        #expect(fixture.runtime.globalSearchFeatureModel.previewState.chatSessionResults.map(\.id).contains(session.id))
        #expect(fixture.runtime.globalSearchFeatureModel.previewState.chatSessionResults.first(where: { $0.id == session.id })?.title == "泰国长期生活计划")
    }

    @Test func globalSearchIncludesChatSessionMessageBodyResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(
            title: "海外生活研究",
            messages: [AgentMessage(role: .user, content: "请帮我整理泰国数字游民签证的资料")]
        )
        try fixture.repository.saveSession(session)
        fixture.runtime.reloadChatSessions()
        fixture.runtime.globalSearchFeatureModel.updateQuery("泰国")

        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "泰国")

        let result = try #require(fixture.runtime.globalSearchFeatureModel.previewState.chatSessionResults.first { $0.id == session.id })
        #expect(result.snippet.contains("泰国"))
        #expect(result.messageCount == 1)
    }

    @Test func openingChatSessionSearchResultSelectsSession() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国行程")
        try fixture.repository.saveSession(session)
        fixture.runtime.reloadChatSessions()

        fixture.runtime.globalSearchFeatureModel.openChatSession(session.id)

        #expect(fixture.runtime.selection == .agentChat)
        #expect(fixture.runtime.chatFeatureModel.sessions.selectedSessionID == session.id)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func globalSearchKeyboardSelectionMovesAcrossActionsAndResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国行程")
        try fixture.repository.saveSession(session)
        fixture.runtime.reloadChatSessions()
        fixture.runtime.globalSearchFeatureModel.updateQuery("泰国")
        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "泰国")

        #expect(fixture.runtime.globalSearchFeatureModel.selectedItem == .action(.newChat))
        fixture.runtime.globalSearchFeatureModel.moveSelectionDown()
        #expect(fixture.runtime.globalSearchFeatureModel.selectedItem == .action(.webSearch))
        fixture.runtime.globalSearchFeatureModel.moveSelectionDown()
        #expect(fixture.runtime.globalSearchFeatureModel.selectedItem == .chatSession(session.id))
        fixture.runtime.globalSearchFeatureModel.moveSelectionUp()
        #expect(fixture.runtime.globalSearchFeatureModel.selectedItem == .action(.webSearch))
    }

    @Test func performingSelectedChatSessionSearchItemSelectsSession() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let session = AgentSession(title: "泰国行程")
        try fixture.repository.saveSession(session)
        fixture.runtime.reloadChatSessions()
        fixture.runtime.globalSearchFeatureModel.updateQuery("泰国")
        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "泰国")
        fixture.runtime.globalSearchFeatureModel.moveSelectionDown()
        fixture.runtime.globalSearchFeatureModel.moveSelectionDown()

        fixture.runtime.globalSearchFeatureModel.performSelectedItem()

        #expect(fixture.runtime.chatFeatureModel.sessions.selectedSessionID == session.id)
        #expect(!fixture.runtime.globalSearchFeatureModel.isOverlayPresented)
    }

    @Test func globalSearchIncludesMailResultsInFallbackPreview() async throws {
        let runtime = AppRuntimeLifecycle(entities: [], statements: [], observeLogEntries: [])
        let mails = (0..<5).map { index in
            makeMailFixture(messageID: "fallback-mail-\(index)", subject: "Phoenix mail \(index)")
        }
        runtime.mailFeatureModel.presentation = NativeMailBrowserPresentation(
            accounts: [mails[0].account],
            mailboxes: [mails[0].mailbox],
            messages: mails.map(\.summary)
        )
        runtime.globalSearchFeatureModel.updateQuery("Phoenix")

        await runtime.globalSearchFeatureModel.refreshPreview(for: "Phoenix")

        #expect(runtime.globalSearchFeatureModel.previewState.mailResults.count == 3)
        #expect(runtime.globalSearchFeatureModel.previewState.mailResults.allSatisfy { $0.sourceKind == .mail })
        #expect(runtime.globalSearchFeatureModel.previewState.mailResults.allSatisfy { $0.title.contains("Phoenix mail") })
    }

    @Test func globalSearchIncludesBrowserHistoryResults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.runtime.chatFeatureModel.sessions.selectedSessionID ?? fixture.runtime.chatFeatureModel.sessions.sessions.first?.id)
        fixture.runtime.browserFeatureModel.recordHistory(url: "https://example.com/swift-history", title: "Swift History", sessionID: sessionID)
        fixture.runtime.globalSearchFeatureModel.updateQuery("swift-history")

        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "swift-history")

        #expect(fixture.runtime.globalSearchFeatureModel.previewState.browserHistoryResults.count == 1)
        #expect(fixture.runtime.globalSearchFeatureModel.previewState.browserHistoryResults.first?.title == "Swift History")
    }

    @Test func globalSearchKeepsPreviewLimitedBrowserHistoryPages() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.runtime.chatFeatureModel.sessions.selectedSessionID ?? fixture.runtime.chatFeatureModel.sessions.sessions.first?.id)
        for index in 0..<5 {
            fixture.runtime.browserFeatureModel.recordHistory(url: "https://example.com/paged-history-\(index)", title: "Paged History \(index)", sessionID: sessionID)
        }
        fixture.runtime.globalSearchFeatureModel.updateQuery("paged-history")

        await fixture.runtime.globalSearchFeatureModel.refreshPreview(for: "paged-history")

        #expect(fixture.runtime.globalSearchFeatureModel.previewState.browserHistoryResults.count == 3)
    }

    @Test func openingBrowserHistoryResultFocusesExistingTab() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let sessionID = try #require(fixture.runtime.chatFeatureModel.sessions.selectedSessionID ?? fixture.runtime.chatFeatureModel.sessions.sessions.first?.id)
        let urlString = "https://example.com/open-tab"
        let tabID = UUID()
        fixture.runtime.browserFeatureModel.installLoadedWorkspaceSnapshot(AppBrowserStateSnapshot(
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

        fixture.runtime.globalSearchFeatureModel.openBrowserHistoryRecord(record)

        #expect(fixture.runtime.selection == .agentChat)
        #expect(fixture.runtime.browserFeatureModel.isVisible)
        #expect(fixture.runtime.browserFeatureModel.workspaceSessionID == sessionID)
        #expect(fixture.runtime.browserFeatureModel.workspaceSnapshotsBySessionID[sessionID]?.selectedTabID == tabID)
    }

    @Test func openingBrowserHistoryResultCreatesSessionWhenOriginalSessionIsMissing() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let originalSessionID = try #require(fixture.runtime.chatFeatureModel.sessions.selectedSessionID ?? fixture.runtime.chatFeatureModel.sessions.sessions.first?.id)
        let urlString = "https://example.com/deleted-session"
        let record = BrowserHistoryRecord(url: urlString, title: "Deleted Session Page", sessionID: "missing-session", sessionTitle: "Deleted")

        fixture.runtime.globalSearchFeatureModel.openBrowserHistoryRecord(record)

        let newSessionID = try #require(fixture.runtime.chatFeatureModel.sessions.selectedSessionID)
        #expect(newSessionID != originalSessionID)
        #expect(fixture.runtime.selection == .agentChat)
        #expect(fixture.runtime.browserFeatureModel.isVisible)
        #expect(fixture.runtime.browserFeatureModel.workspaceSessionID == newSessionID)
        #expect(fixture.runtime.browserFeatureModel.workspaceSnapshotsBySessionID[newSessionID]?.tabs.contains { $0.currentURLString == urlString || $0.initialURLString == urlString } == true)
    }

    private func makeFixture() throws -> Fixture {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-app-global-search-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        let graphRepository = try AppGraphRepository.bootstrap(paths: paths)
        let runtime = AppRuntimeLifecycle(
            entities: [],
            statements: [],
            observeLogEntries: [],
            repository: graphRepository,
            databasePath: paths.databaseURL.path,
            storagePaths: paths
        )
        let repository = AppChatSessionRepository(store: graphRepository.store, storagePaths: paths)
        return Fixture(root: root, paths: paths, runtime: runtime, repository: repository)
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
        var runtime: AppRuntimeLifecycle
        var repository: AppChatSessionRepository

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
