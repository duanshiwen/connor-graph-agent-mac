import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Agent chat empty state view tests")
struct AgentChatEmptyStateViewTests {
    @Test("empty state uses Connor logo asset")
    func emptyStateUsesConnorLogoAsset() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/AgentChatActivityViews.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("Image(\"ConnorAvatar\")"))
        #expect(source.contains(".accessibilityHidden(true)"))
        #expect(!source.contains("Image(systemName: \"sparkles.rectangle.stack\")"))
    }

    @Test("loading view is static and cheap (no 30fps shimmer)")
    func loadingViewIsStaticAndCheap() {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/AgentChatActivityViews.swift")
        let source = try? String(contentsOf: sourceURL, encoding: .utf8)
        // 不再使用 30fps TimelineView 流光，改用静态头像 + 系统 ProgressView。
        #expect(source?.contains("TimelineView(.animation(minimumInterval: 1.0 / 30.0))") == false)
        #expect(source?.contains("Image(\"ConnorAvatar\")") == true)
        #expect(source?.contains("ProgressView()") == true)
    }
}
