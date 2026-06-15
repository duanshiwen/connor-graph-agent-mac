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

    @Test func loadsImagePreviewFromStoredOriginalFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.importFile(at: source, sessionID: "s")

        let model = AttachmentPreviewLoader(store: store).load(sessionID: "s", attachment: manifest.messageRef)

        #expect(model.errorMessage == nil)
        #expect(model.bodyMode == .image)
        #expect(model.sourceRelativePath == manifest.storedRelativePath)
        #expect(model.sourceFileURL?.lastPathComponent == "photo.png")
    }

    @Test func pendingDocumentPreviewExplainsExtractionStatus() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("report.docx")
        try Data("doc".utf8).write(to: source)
        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.importFile(at: source, sessionID: "s")

        let model = AttachmentPreviewLoader(store: store).load(sessionID: "s", attachment: manifest.messageRef)

        #expect(model.manifest?.kind == .document)
        #expect(model.manifest?.extractionStatus == .pending)
        #expect(model.errorMessage?.contains("等待文字解析") == true)
        #expect(model.body.contains("等待文字解析"))
        #expect(model.bodyMode == .markdown)
    }

    @Test func failedDocumentPreviewIncludesExtractorError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        var manifest = seedManifest(paths: paths, sessionID: "s", attachmentID: "a", filename: "report.pdf", kind: .pdf)
        manifest.extractionStatus = .failed
        manifest.extractionReports = [AgentAttachmentExtractionReport(attachmentID: "a", engine: .builtinPDFText, status: .failed, errors: ["password protected"])]
        try AttachmentManifestUpdater(paths: paths).write(manifest, sessionID: "s")

        let model = AttachmentPreviewLoader(store: AppSessionAttachmentStore(paths: paths)).load(sessionID: "s", attachment: manifest.messageRef)

        #expect(model.errorMessage?.contains("password protected") == true)
        #expect(model.body.contains("password protected"))
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

    private func seedManifest(paths: AppStoragePaths, sessionID: String, attachmentID: String, filename: String, kind: AgentAttachmentKind) -> AgentAttachmentManifest {
        let directories = try! paths.ensureSessionArtifactDirectories(sessionID: sessionID)
        let attachmentDirectory = directories.attachments.appendingPathComponent(attachmentID, isDirectory: true)
        let originalDirectory = attachmentDirectory.appendingPathComponent("original", isDirectory: true)
        try! FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
        try! Data("original".utf8).write(to: originalDirectory.appendingPathComponent(filename))
        let manifest = AgentAttachmentManifest(
            id: attachmentID,
            displayName: filename,
            originalFilename: filename,
            normalizedFilename: filename,
            kind: kind,
            byteCount: 8,
            sha256: "sha",
            lifecycleStatus: .ready,
            extractionStatus: .pending,
            storedRelativePath: "attachments/\(attachmentID)/original/\(filename)",
            manifestRelativePath: "attachments/\(attachmentID)/manifest.json",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try! AttachmentManifestUpdater(paths: paths).write(manifest, sessionID: sessionID)
        return manifest
    }
}
