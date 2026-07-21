import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Chat Viewport Content Layout Tests")
struct ChatViewportContentLayoutTests {
    @Test func genericViewportDefaultsToLazyContentLayout() {
        #expect(ChatViewportConfiguration().contentLayout == .lazy)
    }

    @Test func agentChatUsesEagerContentLayoutBehindBoundedMessageWindow() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/AgentChatView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("contentLayout: .eager"))
        #expect(source.contains("private static let initialVisibleMessageLimit = 8"))
        #expect(source.contains("private static let messagePageSize = 8"))
    }
}
