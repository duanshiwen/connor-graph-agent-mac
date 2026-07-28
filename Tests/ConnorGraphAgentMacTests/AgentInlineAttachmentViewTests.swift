import CoreGraphics
import Foundation
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

    @MainActor
    @Test func attachmentSharingRequiresAnExistingLocalFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("share".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(AgentAttachmentSharingService.canShare(fileURL: fileURL))
        #expect(!AgentAttachmentSharingService.canShare(fileURL: URL(string: "https://example.com/file")!))
        #expect(!AgentAttachmentSharingService.canShare(fileURL: fileURL.appendingPathExtension("missing")))
    }
}
