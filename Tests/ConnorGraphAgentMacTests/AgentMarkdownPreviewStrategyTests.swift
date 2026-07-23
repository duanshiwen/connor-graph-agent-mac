import Foundation
import AppKit
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

    @Test func messageBodyPointSizeIsDisplayedAndClamped() {
        #expect(AgentChatFontPreferences.pointSizeLabel(14) == "14 pt")
        #expect(AgentChatFontPreferences.validatedMessageBodyPointSize(8) == 11)
        #expect(AgentChatFontPreferences.validatedMessageBodyPointSize(30) == 22)
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
        #expect(messageRows.contains("@AppStorage(AgentChatFontPreferences.messageBodyPointSizeKey)"))
        #expect(messageRows.components(separatedBy: "bodyPointSize: messageBodyPointSize").count >= 4)
        #expect(preview.contains("bodyPointSize + semanticSize - systemBodySize"))
    }

    @Test func compiledMarkdownLoadsOutsideTheMainActorAndHonorsCancellation() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let preview = try String(
            contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/AgentMarkdownPreviewText.swift"),
            encoding: .utf8
        )

        #expect(preview.contains("Task.detached(priority: .utility)"))
        #expect(preview.contains("loadTask.cancel()"))
        #expect(preview.contains("guard !Task.isCancelled, document.source == markdown else { return }"))
        #expect(preview.contains("persistentCacheContext.store.loadBlocks"))
    }

    @Test @MainActor func markdownLinksUseTheNativePointingHandCursorAttribute() throws {
        let attributed = try AttributedString(
            markdown: "Before [Connor](https://example.com) after",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )

        let rendered = AgentMarkdownLinkText.renderedAttributedString(
            attributed,
            baseFont: .systemFont(ofSize: 14),
            baseColor: .labelColor,
            strikethrough: false
        )
        let fullRange = NSRange(location: 0, length: rendered.length)
        var linkRanges = 0

        rendered.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            linkRanges += 1
            #expect(rendered.attribute(.cursor, at: range.location, effectiveRange: nil) as? NSCursor === NSCursor.pointingHand)
        }

        #expect(linkRanges == 1)
    }
}
