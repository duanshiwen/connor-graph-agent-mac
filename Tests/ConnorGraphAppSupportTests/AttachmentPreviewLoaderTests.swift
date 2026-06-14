import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Attachment Preview Loader Tests")
struct AttachmentPreviewLoaderTests {
    @Test func loadsMarkdownPreviewFromCurrentExtractedDerivative() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("notes.md")
        try "# Notes\n\nPreview me.".write(to: source, atomically: true, encoding: .utf8)
        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.importFile(at: source, sessionID: "s")

        let model = AttachmentPreviewLoader(store: store).load(sessionID: "s", attachment: manifest.messageRef)

        #expect(model.errorMessage == nil)
        #expect(model.body.contains("# Notes"))
        #expect(model.bodyMode == .markdown)
        #expect(model.sourceRelativePath?.contains("derivatives/current/extracted.md") == true)
        #expect(model.manifest?.id == manifest.id)
    }

    @Test func loadsStructuredTextAsMonospacedPreview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("data.json")
        try "{\"hello\": \"world\"}".write(to: source, atomically: true, encoding: .utf8)
        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.importFile(at: source, sessionID: "s")

        let model = AttachmentPreviewLoader(store: store).load(sessionID: "s", attachment: manifest.messageRef)

        #expect(model.errorMessage == nil)
        #expect(model.body.contains("hello"))
        #expect(model.bodyMode == .monospaced)
    }

    @Test func missingManifestReturnsGracefulErrorModel() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let store = AppSessionAttachmentStore(paths: paths)
        let attachment = AgentMessageAttachmentRef(
            id: "missing",
            displayName: "missing.md",
            kind: .markdown,
            byteCount: 42,
            lifecycleStatus: .ready,
            extractionStatus: .extracted,
            manifestRelativePath: "attachments/missing/manifest.json",
            previewText: nil
        )

        let model = AttachmentPreviewLoader(store: store).load(sessionID: "s", attachment: attachment)

        #expect(model.errorMessage != nil)
        #expect(!model.body.isEmpty)
        #expect(model.title == "missing.md")
    }
}
