import Foundation
import Testing
import ConnorGraphAppSupport
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
}
