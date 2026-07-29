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

    @Test("loading light effect loops without a spinner")
    func loadingLightEffectLoopsWithoutSpinner() {
        let first = AgentChatLoadingLightEffect.progress(elapsed: 0.5)
        let repeated = AgentChatLoadingLightEffect.progress(
            elapsed: AgentChatLoadingLightEffect.cycleDuration + 0.5
        )

        #expect((0..<1).contains(first))
        #expect(abs(first - repeated) < 0.000_001)

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ConnorGraphAgentMac/AgentChatActivityViews.swift")
        let source = try? String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source?.contains("private func loadingIcon") == true)
        #expect(source?.contains("Text(\"Loading\")") == false)
    }
}
