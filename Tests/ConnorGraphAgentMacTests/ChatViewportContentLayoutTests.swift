import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Chat Viewport Content Layout Tests")
struct ChatViewportContentLayoutTests {
    @Test func genericViewportDefaultsToLazyContentLayout() {
        #expect(ChatViewportConfiguration().contentLayout == .lazy)
    }

    @Test func agentChatUsesEagerRowsBehindBoundedMessageWindow() throws {
        let source = try agentChatViewSource()

        #expect(source.contains("contentLayout: .eager"))
        #expect(source.contains("private static let initialVisibleMessageLimit = 8"))
        #expect(source.contains("private static let messagePageSize = 8"))
    }

    @Test func appearingWithRestoredTranscriptSeedsVisibleWindowFromLoadedMessages() throws {
        let source = try agentChatViewSource()

        #expect(source.contains(
            "visibleMessageLimit = max(Self.initialVisibleMessageLimit, model.run.transcript.count)"
        ))
    }

    @Test func persistedHistoryPageExpandsVisibleWindowAfterPrepend() throws {
        let source = try agentChatViewSource()

        #expect(source.contains("visibleMessageLimit += addedCount"))
    }

    @Test func viewportWaitsForLayoutBeforeResolvingInitialAnchor() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/ChatViewport/CommercialChatViewport.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains("requestPendingInitialAnchorNow"))
    }

    @Test func viewportDefaultsToBottomWhileStateMachineControlsSubsequentScrolling() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/ChatViewport/CommercialChatViewport.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains(".defaultScrollAnchor(.bottom)"))
        #expect(source.contains("controller.replaceDataSetIfNeeded(id: dataSetID, itemCount: items.count, initialAnchor: .bottom)"))
        #expect(source.contains("controller.isPinnedToBottom"))
    }

    private func agentChatViewSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/AgentChatView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
