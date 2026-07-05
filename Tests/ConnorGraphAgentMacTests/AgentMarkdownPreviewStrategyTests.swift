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
}
