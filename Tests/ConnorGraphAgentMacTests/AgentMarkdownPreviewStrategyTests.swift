import Foundation
import AppKit
import Testing
import ConnorGraphAppSupport
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

    @Test func longUserMessageCanDisableDeferredPreviewRendering() {
        let strategy = AgentMarkdownPreviewRenderStrategy.strategy(
            lineLimit: nil,
            monospacedFallback: false,
            markdownCharacterCount: 20_000,
            allowsDeferredPreview: false
        )

        #expect(strategy == .compiledDocument)
    }

    @Test func deferredPreviewOnlyCopiesABoundedMarkdownPrefix() {
        let limit = AgentMarkdownDeferredPreviewPolicy.characterLimit
        let markdown = String(repeating: "前", count: limit) + "不应进入折叠预览"

        let preview = AgentMarkdownDeferredPreviewPolicy.source(for: markdown)

        #expect(preview.count == limit)
        #expect(!preview.contains("不应进入折叠预览"))
    }

    @Test func fileAndAttachmentPreviewsOfferFullMarkdownExpansion() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let markdownPreview = try String(
            contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/AgentMarkdownPreviewText.swift"),
            encoding: .utf8
        )
        let workspacePreview = try String(
            contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/WorkspaceFilePreviewOverlay.swift"),
            encoding: .utf8
        )
        let attachmentPreview = try String(
            contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/AgentAttachmentPreviewSheetView.swift"),
            encoding: .utf8
        )
        let messageRows = try String(
            contentsOf: root.appendingPathComponent("Sources/ConnorGraphAgentMac/AgentChatMessageRows.swift"),
            encoding: .utf8
        )

        #expect(markdownPreview.contains("AgentMessageExpansionButton("))
        #expect(markdownPreview.contains("title: \"展开完整内容\""))
        #expect(markdownPreview.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(messageRows.contains("AgentMessageExpansionButton("))
        #expect(markdownPreview.contains("allowsDeferredPreview && !isUserExpanded"))
        #expect(workspacePreview.contains("allowsUserExpansion: true"))
        #expect(workspacePreview.contains("Image(systemName: \"doc.on.doc\")"))
        #expect(!workspacePreview.contains("Label(\"复制全文\""))
        #expect(attachmentPreview.contains("allowsUserExpansion: true"))
    }

    @Test func messageBodyPointSizeIsDisplayedAndClamped() {
        #expect(AgentChatFontPreferences.pointSizeLabel(14) == "14 pt")
        #expect(AgentChatFontPreferences.validatedMessageBodyPointSize(8) == 11)
        #expect(AgentChatFontPreferences.validatedMessageBodyPointSize(30) == 22)
    }

    @Test func workspaceFilePreviewActionsCoverAllFileTypesAndCopyOnlyText() {
        let textRenderers: [WorkspaceFilePreviewRenderer] = [.markdown, .monospacedText, .plainText]
        let nonTextRenderers: [WorkspaceFilePreviewRenderer] = [.pdf, .quickLook, .html, .unsupported]

        for renderer in textRenderers {
            let presentation = WorkspaceFilePreviewActionsPresentation(renderer: renderer)
            #expect(presentation.showsShare)
            #expect(presentation.showsCopyFullText)
        }
        for renderer in nonTextRenderers {
            let presentation = WorkspaceFilePreviewActionsPresentation(renderer: renderer)
            #expect(presentation.showsShare)
            #expect(!presentation.showsCopyFullText)
        }
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
        #expect(messageRows.components(separatedBy: "bodyPointSize: messageBodyPointSize").count >= 3)
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

    @Test func longMessageExpansionKeepsPreviewUntilTheFullDocumentLoads() throws {
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

        #expect(preview.contains("deferred:\\(effectiveAllowsDeferredPreview)"))
        #expect(preview.contains("deferredPreviewView(statusText: \"正在展开完整内容…\", showsProgress: true)"))
        #expect(messageRows.components(separatedBy: "allowsDeferredPreview: !isMessageExpanded").count == 3)
        #expect(messageRows.contains("transaction.disablesAnimations = true"))
        #expect(messageRows.contains("assistantActionsPresentation.showsActions || assistantExpansionPresentation.isAvailable"))
        #expect(messageRows.contains(".opacity(isHoveringMessageBubble ? 1 : 0)"))
        #expect(messageRows.contains(".onHover(perform: updateMessageBubbleHover)"))
        #expect(messageRows.contains("expansionPresentation: assistantExpansionPresentation"))
        #expect(messageRows.contains("private var expansionButton: some View"))
        #expect(messageRows.contains(".foregroundStyle(Color.accentColor)"))
        #expect(!messageRows.contains("allowsDeferredPreview: false"))
        #expect(!messageRows.contains("content.trimmingCharacters"))
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

    @Test @MainActor func bareWebAddressesBecomeClickableLinks() {
        let address = "https://pages.example.test/s/site-1"
        let rendered = AgentMarkdownLinkText.renderedAttributedString(
            AttributedString("Published: \(address)"),
            baseFont: .systemFont(ofSize: 14),
            baseColor: .labelColor,
            strikethrough: false
        )
        let addressRange = (rendered.string as NSString).range(of: address)

        #expect(addressRange.location != NSNotFound)
        #expect((rendered.attribute(.link, at: addressRange.location, effectiveRange: nil) as? URL)?.absoluteString == address)
        #expect(rendered.attribute(.cursor, at: addressRange.location, effectiveRange: nil) as? NSCursor === NSCursor.pointingHand)
    }

    @Test @MainActor func markdownLinkTextViewWrapsInsideNarrowListRows() {
        let textView = AgentMarkdownLinkText.LinkTextView()

        #expect(textView.textContainer?.lineBreakMode == .byWordWrapping)
        #expect(textView.contentHuggingPriority(for: .horizontal) == .defaultLow)
        #expect(textView.contentCompressionResistancePriority(for: .horizontal) == .defaultLow)
    }

    @Test func markdownImageSourcePolicyAllowsOnlyFilesInsideTheSessionRoot() {
        let root = URL(fileURLWithPath: "/tmp/connor/sessions/session-1")
        let inside = root.appendingPathComponent("attachments/image/original/chart.png")
        let outside = URL(fileURLWithPath: "/tmp/private.png")

        #expect(AgentMarkdownImageSourcePolicy.localFileURL(source: inside.absoluteString, allowedRoot: root) == inside)
        #expect(AgentMarkdownImageSourcePolicy.localFileURL(source: outside.absoluteString, allowedRoot: root) == nil)
        #expect(AgentMarkdownImageSourcePolicy.localFileURL(source: "https://example.com/chart.png", allowedRoot: root) == nil)
    }
}
