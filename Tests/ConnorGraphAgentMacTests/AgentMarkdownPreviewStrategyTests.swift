import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Agent Markdown Preview Strategy Tests")
struct AgentMarkdownPreviewStrategyTests {
    @Test func lineLimitedPreviewUsesInlineOnlyRendering() {
        let strategy = AgentMarkdownPreviewRenderStrategy.strategy(lineLimit: 2, monospacedFallback: false, markdownCharacterCount: 10_000)

        #expect(strategy == .inlineOnly)
    }

    @Test func monospacedFallbackUsesPlainTextRendering() {
        let strategy = AgentMarkdownPreviewRenderStrategy.strategy(lineLimit: nil, monospacedFallback: true, markdownCharacterCount: 10_000)

        #expect(strategy == .plainText)
    }

    @Test func longMarkdownUsesDeferredPreviewRendering() {
        let strategy = AgentMarkdownPreviewRenderStrategy.strategy(lineLimit: nil, monospacedFallback: false, markdownCharacterCount: 20_000)

        #expect(strategy == .deferredPreview)
    }

    @Test func compiledMarkdownUsesIntrinsicVerticalHeight() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let preview = try String(
            contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/AgentMarkdownPreviewText.swift"),
            encoding: .utf8
        )
        let messageRows = try String(
            contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/AgentChatMessageRows.swift"),
            encoding: .utf8
        )

        #expect(preview.components(separatedBy: ".fixedSize(horizontal: false, vertical: true)").count >= 9)
        #expect(messageRows.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(messageRows.contains("font: AgentChatTypography.messageBody"))
    }
}
