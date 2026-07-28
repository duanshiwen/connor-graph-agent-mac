import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@Suite("Agent Attachment Context Plan Builder Tests")
struct AgentAttachmentContextPlanBuilderTests {
    @Test func buildsInlineContextForExtractedTextAttachment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-context-builder-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let sessionID = "session"
        let source = root.appendingPathComponent("note.md")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Hello\n\nBody".write(to: source, atomically: true, encoding: .utf8)
        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: sessionID)
        let builder = AgentAttachmentContextPlanBuilder(storagePaths: paths)

        let plan = builder.build(sessionID: sessionID, attachments: [manifest.messageRef])

        #expect(plan.inlineBlocks.count == 1)
        #expect(plan.inlineBlocks.first?.content.contains("Hello") == true)
        #expect(plan.imageBlocks.isEmpty)
    }

    @Test func rebuildsHistoricalImageFromStoredBytesAndDeduplicatesConversationAttachments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-history-builder-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let sessionID = "session"
        let source = root.appendingPathComponent("history.png")
        let originalBytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01, 0x02, 0x03])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try originalBytes.write(to: source)
        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: sessionID)
        let messages = [
            AgentMessage(role: .assistant, content: "Generated image", attachments: [manifest.messageRef])
        ]

        let attachments = AgentAttachmentContextPlanBuilder.conversationAttachments(
            messages: messages,
            currentAttachments: [manifest.messageRef]
        )
        let plan = AgentAttachmentContextPlanBuilder(storagePaths: paths).build(
            sessionID: sessionID,
            attachments: attachments
        )
        let imageBlock = try #require(plan.imageBlocks.first)
        let encodedPayload = try #require(imageBlock.dataURL.split(separator: ",", maxSplits: 1).last)
        let rebuiltBytes = try #require(Data(base64Encoded: String(encodedPayload)))

        #expect(attachments == [manifest.messageRef])
        #expect(plan.imageBlocks.count == 1)
        #expect(rebuiltBytes == originalBytes)
    }
}
