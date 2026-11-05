import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ConnorGraphAgentMac

@Suite("Markdown native text layout")
struct AgentMarkdownListTextLayoutTests {
    @Test @MainActor func userBubbleWithLinkKeepsItsBodyVisible() throws {
        let attributed = try AttributedString(
            markdown: "请帮我看看[这个页面](https://example.com)，然后总结一下。",
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        let body = AgentMarkdownLinkText(
            attributed: attributed, baseFont: .systemFont(ofSize: 17),
            baseColor: .labelColor, strikethrough: false
        )
        // Match the trailing user bubble: a spacer, capped width and padded body.
        let host = NSHostingView(rootView:
            HStack(alignment: .top) {
                Spacer(minLength: AgentChatLayout.messageSideInset)
                VStack(alignment: .trailing) {
                    VStack(alignment: .leading) {
                        body.fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AgentChatLayout.messageBubbleHorizontalPadding)
                    .padding(.vertical, AgentChatLayout.messageBubbleVerticalPadding)
                    .frame(maxWidth: AgentChatLayout.userMessageMaxWidth, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        )
        func textViews(in view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
        }

        for width: CGFloat in [640, 280] {
            host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
            host.layoutSubtreeIfNeeded()
            let text = try #require(textViews(in: host).first)
            let container = try #require(text.textContainer)
            let layout = try #require(text.layoutManager)
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            #expect(text.string == String(attributed.characters))
            #expect(text.bounds.width > 0 && text.bounds.width < width)
            #expect(text.bounds.height >= ceil(used.height))
            #expect(container.containerSize.height >= used.height)
            #expect(used.height > 0)
        }
    }

    @Test @MainActor func linkedListBodyLaysOutEveryCharacter() throws {
        let view = AgentMarkdownLinkText.LinkTextView()
        let container = try #require(view.textContainer)
        let layout = try #require(view.layoutManager)

        for repetitions in [1, 8] {
            let attributed = try AttributedString(
                markdown: String(repeating: "条目 **内容**与[链接](https://example.com)，需要完整换行显示。", count: repetitions),
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            view.textStorage?.setAttributedString(AgentMarkdownLinkText.renderedAttributedString(
                attributed, baseFont: .systemFont(ofSize: 17), baseColor: .labelColor, strikethrough: false
            ))

            for width: CGFloat in [220, 600, 180] {
                let size = view.measuredSize(for: width)
                view.setFrameSize(size)
                layout.ensureLayout(for: container)

                let glyphs = layout.glyphRange(for: container)
                let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                #expect(characters == NSRange(location: 0, length: view.attributedString().length))
                #expect(layout.usedRect(for: container).height > 0)
                #expect(ceil(layout.usedRect(for: container).height) == size.height)
                #expect(container.containerSize.width == width)
                #expect(container.containerSize.height >= size.height)
                #expect(!view.isVerticallyResizable)
            }
        }
    }
}
