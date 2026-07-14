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

    @Test func webSearchUsesProviderAndEmitsURL() throws {
        let model = makeModel()
        model.defaultSearchURLProvider = { URL(string: "https://example.com/search?q=\($0)") }
        var openedURL: URL?
        model.onDestination = {
            if case let .webSearch(url) = $0 { openedURL = url }
        }
        model.updateQuery("connor")

        model.performWebSearch()

        #expect(openedURL?.host == "example.com")
        #expect(model.historyEntries.first?.normalizedQuery == "connor")
        model.shutdown()
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

        #expect(model.previewState.chatSessionResults.map(\.id) == ["session-1"])
        #expect(model.previewState.calendarResults.map(\.title) == ["Swift meetup"])
        #expect(model.previewState.loadingSections.isEmpty)
        model.shutdown()
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
