import Foundation
import Testing

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
}
