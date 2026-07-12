import CoreGraphics
import Testing
@testable import ConnorGraphAgentMac

@Suite("Agent Inline Attachment View Tests")
struct AgentInlineAttachmentViewTests {
    @Test func defaultImageLayoutIsBoundedForChatViewport() {
        let layout = AgentInlineAttachmentLayout()
        #expect(layout.maxWidth == 420)
        #expect(layout.maxHeight == 320)
        #expect(layout.minimumPlaceholderHeight == 120)
    }

    @Test func imageLayoutSupportsSmallerBoundedPresentation() {
        let layout = AgentInlineAttachmentLayout(maxWidth: 240, maxHeight: 180, minimumPlaceholderHeight: 96)
        #expect(layout.maxWidth == 240)
        #expect(layout.maxHeight == 180)
        #expect(layout.minimumPlaceholderHeight == 96)
    }
}
