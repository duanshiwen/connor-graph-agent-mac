import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Test func chatPresentationCarriesMessageAttachmentReferences() {
    let ref = AgentMessageAttachmentRef(
        id: "attachment-1",
        displayName: "notes.md",
        kind: .markdown,
        byteCount: 42,
        lifecycleStatus: .ready,
        extractionStatus: .extracted,
        manifestRelativePath: "attachments/attachment-1/manifest.json",
        previewText: "Preview"
    )
    let message = AgentMessage(role: .user, content: "Use this", attachments: [ref])

    let presentation = AgentChatMessagePresentation(
        message: message,
        turnNumber: 1,
        isLatestAssistantMessage: false,
        lastContext: nil
    )

    #expect(presentation.attachments.count == 1)
    #expect(presentation.attachments.first?.displayName == "notes.md")
    #expect(presentation.attachments.first?.kind == .markdown)
}
