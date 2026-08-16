import Foundation
import Testing
@testable import ConnorGraphAgentMac
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor
@Suite("GlobalSearchFeatureModel Tests")
struct GlobalSearchFeatureModelTests {
    @Test func queryStateAndKeyboardSelectionHaveSingleOwner() async {
        let model = makeModel()
        model.updateQuery("swift")

        #expect(model.query == "swift")
        #expect(model.isOverlayPresented)
        #expect(model.selectedItem == .action(.newChat))

        model.moveSelectionDown()
        #expect(model.selectedItem == .action(.webSearch))
        model.shutdown()
    }

    @Test func newChatEmitsTypedDestinationAndRecordsHistory() throws {
        let model = makeModel()
        var prompt: String?
        model.onDestination = {
            if case let .newChat(value) = $0 { prompt = value }
        }
        model.updateQuery("  explain actors  ")

        model.performNewChat()

        #expect(prompt == "explain actors")
        #expect(model.query.isEmpty)
        #expect(!model.isOverlayPresented)
        #expect(model.historyEntries.first?.query == "explain actors")
        model.shutdown()
    }

    @Test func emptyFocusedQueryDoesNotShowRecordedHistoryOverlay() {
        let model = makeModel()
        model.recordHistoryForTesting(query: "recorded query")

        model.activateField()

        #expect(model.historyEntries.first?.query == "recorded query")
        #expect(model.isFieldFocused)
        #expect(!model.isOverlayPresented)
        model.shutdown()
    }

    @Test func webSearchUsesProviderAndEmitsURL() throws {
        let model = makeModel()
        model.defaultSearchURLProvider = { URL(string: "https://example.com/search?q=\($0)") }
        var openedURL: URL?
        var openedQuery: String?
        model.onDestination = {
            if case let .webSearch(query, url) = $0 {
                openedQuery = query
                openedURL = url
            }
        }
        model.updateQuery("connor")

        model.performWebSearch()

        #expect(openedURL?.host == "example.com")
        #expect(openedQuery == "connor")
        #expect(model.historyEntries.first?.normalizedQuery == "connor")
        model.shutdown()
    }

    @Test func browserSearchSessionTitlePreservesNormalizedQuery() {
        #expect(BrowserSearchSessionTitleFormatter.title(for: "  Surface   Laptop  ") == "用户搜索：Surface Laptop")
        #expect(BrowserSearchSessionTitleFormatter.title(for: "   ") == "用户搜索")
    }

    @Test func fallbackPreviewAggregatesSessionsAndNativeSources() async {
        let model = makeModel()
        model.sessionsProvider = {
            [AgentSession(id: "session-1", title: "Swift concurrency", messages: [AgentMessage(role: .user, content: "actor isolation")])]
        }
        model.fallbackNativeSearchProvider = { kind, query, _ in
            guard kind == .calendar, query == "Swift" else { return [] }
            return [Self.nativeResult(kind: .calendar, id: "event-1", title: "Swift meetup")]
        }
        model.updateQuery("Swift")

        await model.refreshPreview(for: "Swift")

        #expect(model.previewState.sessionResults.map(\.id) == ["session-1"])
        #expect(model.previewState.calendarResults.map(\.title) == ["Swift meetup"])
        #expect(model.previewState.loadingSections.isEmpty)
        model.shutdown()
    }

    @Test func chatResultsAppearWhileNativeSourcesAreStillSearching() async {
        let model = GlobalSearchFeatureModel(
            nativeSourceSearchBackend: SlowNativeSourceSearchBackend(),
            sessionSearchIndexService: nil,
            historyRepository: nil
        )
        model.sessionsProvider = {
            [AgentSession(id: "session-1", title: "Swift concurrency", messages: [])]
        }
        model.updateQuery("Swift")

        let refreshTask = Task { await model.refreshPreview(for: "Swift") }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(model.previewState.sessionResults.map(\.id) == ["session-1"])
        #expect(model.previewState.isSectionLoading(.mail))

        model.shutdown()
        refreshTask.cancel()
        await refreshTask.value
    }

    @Test func shutdownPreventsPendingDebounceFromApplying() async {
        let model = makeModel()
        model.fallbackNativeSearchProvider = { kind, _, _ in
            [Self.nativeResult(kind: kind, id: kind.rawValue, title: "late")]
        }
        model.updateQuery("late")
        model.shutdown()
        try? await Task.sleep(for: .milliseconds(240))

        #expect(model.previewState.calendarResults.isEmpty)
        #expect(model.previewState.rssResults.isEmpty)
    }

    @Test func marketplaceResultsJoinUnifiedSearchAndOpenDetail() async {
        let model = makeModel()
        model.knowledgeMarketplaceSearchProvider = { query in
            guard query == "Swift" else { return [] }
            return [CloudMarketplaceKnowledgeBase(
                id: "kb-swift",
                name: "Swift 知识库",
                subscribed: true,
                ownerName: "Connor",
                publicationStatus: "published"
            )]
        }
        var openedID: String?
        model.onDestination = {
            if case let .knowledgeBase(id) = $0 { openedID = id }
        }
        model.updateQuery("Swift")

        await model.refreshPreview(for: "Swift")

        #expect(model.previewState.knowledgeBaseResults.map(\.id) == ["kb-swift"])
        #expect(model.selectableItems.contains(.knowledgeBase("kb-swift")))
        model.openKnowledgeBase("kb-swift")
        #expect(openedID == "kb-swift")
        model.shutdown()
    }

    @Test func peerAndGroupConversationsJoinUnifiedSessionsAndOpenConversation() async throws {
        let model = makeModel()
        model.imConversationsProvider = {
            [
                ImConversation(
                    id: "peer:7",
                    kind: .peer,
                    peerUserId: 7,
                    title: "项目联系人",
                    participantName: "李明",
                    lastMessagePreview: "项目方案已经发你了",
                    lastMessageAt: 1_754_200_000_000
                ),
                ImConversation(
                    id: "group:delivery",
                    kind: .group,
                    groupId: "delivery",
                    title: "项目交付群",
                    participantName: "项目交付群",
                    lastMessagePreview: "下午同步交付进度",
                    lastMessageAt: 1_754_300_000_000
                )
            ]
        }
        var openedConversationID: String?
        model.onDestination = {
            if case let .imConversation(id) = $0 { openedConversationID = id }
        }
        model.updateQuery("项目")

        await model.refreshPreview(for: "项目")

        // 单聊/群聊统一归入“会话”，并带类型标注
        #expect(Set(model.previewState.sessionResults.map(\.kind)) == Set([.peer, .group]))
        let peer = try #require(model.previewState.sessionResults.first { $0.id == "peer:7" })
        let group = try #require(model.previewState.sessionResults.first { $0.id == "group:delivery" })
        #expect(peer.kind.kindLabel == "单聊")
        #expect(group.kind.kindLabel == "群聊")

        func isSession(_ item: GlobalSearchSelectableItem, id: String) -> Bool {
            if case .session(let result) = item { return result.id == id }
            return false
        }
        #expect(model.selectableItems.contains { isSession($0, id: "peer:7") })
        #expect(model.selectableItems.contains { isSession($0, id: "group:delivery") })

        model.openSession(group)
        #expect(openedConversationID == "group:delivery")
        #expect(!model.isOverlayPresented)
        model.shutdown()
    }

    @Test func unifiedSessionsLabelAIChatAndNotesWithKinds() async throws {
        let model = makeModel()
        model.sessionsProvider = {
            [
                AgentSession(id: "agent-1", title: "Swift 并发", messages: [AgentMessage(role: .user, content: "并发进度整理 actor isolation")], updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
                AgentSession(
                    id: "note-1",
                    title: "会议纪要",
                    messages: [AgentMessage(role: .user, content: "项目进度记录")],
                    updatedAt: Date(timeIntervalSince1970: 1_700_100_000),
                    governance: AgentSessionGovernanceMetadata(kind: .note)
                )
            ]
        }
        model.imConversationsProvider = {
            [
                ImConversation(
                    id: "peer:9",
                    kind: .peer,
                    peerUserId: 9,
                    title: "联系人",
                    participantName: "王五",
                    lastMessagePreview: "进度同步",
                    lastMessageAt: 1_754_400_000_000
                )
            ]
        }
        model.updateQuery("进度")

        await model.refreshPreview(for: "进度")

        // AI 对话、笔记、单聊统一出现在“会话”里，各自带类型标注
        let agent = try #require(model.previewState.sessionResults.first { $0.id == "agent-1" })
        let note = try #require(model.previewState.sessionResults.first { $0.id == "note-1" })
        let peer = try #require(model.previewState.sessionResults.first { $0.id == "peer:9" })
        #expect(agent.kind == .agentChat)
        #expect(agent.kind.kindLabel == "AI")
        #expect(note.kind == .note)
        #expect(note.kind.kindLabel == "笔记")
        #expect(peer.kind == .peer)
        #expect(peer.kind.kindLabel == "单聊")
        model.shutdown()
    }

    private func makeModel() -> GlobalSearchFeatureModel {
        GlobalSearchFeatureModel(nativeSourceSearchBackend: nil, sessionSearchIndexService: nil, historyRepository: nil)
    }

    private static func nativeResult(kind: NativeSearchSourceKind, id: String, title: String) -> NativeSearchResult {
        NativeSearchResult(
            id: "\(kind.rawValue):\(id)",
            sourceKind: kind,
            externalID: id,
            sourceInstanceID: "source",
            title: title,
            snippet: title,
            score: 1,
            lexicalScore: 1,
            freshnessScore: 0,
            fieldScore: 0,
            temporal: NativeSearchTemporalMetadata(indexedAt: Date()),
            resultTimeLabel: ""
        )
    }
}

private actor SlowNativeSourceSearchBackend: NativeSourceSearchBackend {
    func upsert(_ documents: [NativeSearchDocument]) async throws {}
    func delete(documentIDs: [String]) async throws {}
    func deleteBySource(kind: NativeSearchSourceKind, sourceInstanceID: String?) async throws {}
    func rebuildSource(kind: NativeSearchSourceKind, sourceInstanceID: String?, documents: [NativeSearchDocument]) async throws {}

    func search(_ query: NativeSearchQuery) async throws -> [NativeSearchResult] {
        try await Task.sleep(for: .milliseconds(400))
        return []
    }

    func health() async -> NativeSourceSearchHealthSnapshot {
        NativeSourceSearchHealthSnapshot()
    }
}
