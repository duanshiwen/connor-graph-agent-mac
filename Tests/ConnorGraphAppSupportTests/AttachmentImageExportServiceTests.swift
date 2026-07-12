import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Attachment Image Export Service Tests")
struct AttachmentImageExportServiceTests {
    @Test func exportsPersistedImageWithoutMutatingSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("generated.png")
        let destination = root.appendingPathComponent("downloaded.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        try bytes.write(to: source)
        let model = makeModel(kind: .image, displayName: "generated.png", sourceURL: source)

        try AttachmentImageExportService().export(model: model, to: destination)

        #expect(try Data(contentsOf: destination) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test func exportAvailabilityRequiresExistingImageFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("generated.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
        let service = AttachmentImageExportService()

        #expect(service.canExport(makeModel(kind: .image, displayName: "generated.png", sourceURL: source)))
        #expect(!service.canExport(makeModel(kind: .text, displayName: "generated.png", sourceURL: source)))
        #expect(!service.canExport(makeModel(kind: .image, displayName: "missing.png", sourceURL: root.appendingPathComponent("missing.png"))))
    }

    @Test func buildsSanitizedFilenameAndPreservesSourceExtension() throws {
        let source = URL(fileURLWithPath: "/tmp/generated.webp")
        let model = makeModel(kind: .image, displayName: "../公众号/头像", sourceURL: source)

        let filename = AttachmentImageExportService().defaultFilename(for: model)

        #expect(filename == "__公众号_头像.webp")
    }

    @Test func rejectsNonImageAttachment() throws {
        let source = URL(fileURLWithPath: "/tmp/document.txt")
        let destination = URL(fileURLWithPath: "/tmp/document-copy.txt")
        let model = makeModel(kind: .text, displayName: "document.txt", sourceURL: source)

        #expect(throws: AttachmentImageExportError.notImage) {
            try AttachmentImageExportService().export(model: model, to: destination)
        }
    }

    @Test func rejectsExistingDestinationWithoutOverwriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("generated.png")
        let destination = root.appendingPathComponent("existing.png")
        try Data("source".utf8).write(to: source)
        try Data("existing".utf8).write(to: destination)
        let model = makeModel(kind: .image, displayName: "generated.png", sourceURL: source)

        #expect(throws: AttachmentImageExportError.destinationAlreadyExists) {
            try AttachmentImageExportService().export(model: model, to: destination)
        }
        #expect(try Data(contentsOf: destination) == Data("existing".utf8))
    }

    @Test func exportLeavesAttachmentManifestAndOriginalUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        defer { try? FileManager.default.removeItem(at: root) }
        let importedSource = root.appendingPathComponent("generated.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        try bytes.write(to: importedSource)
        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.importFile(at: importedSource, sessionID: "session")
        let model = AttachmentPreviewLoader(store: store).load(sessionID: "session", attachment: manifest.messageRef)
        let manifestURL = paths.sessionArtifactDirectories(sessionID: "session").attachments
            .appendingPathComponent(manifest.id, isDirectory: true)
            .appendingPathComponent("manifest.json")
        let manifestBefore = try Data(contentsOf: manifestURL)
        let destination = root.appendingPathComponent("download.png")

        try AttachmentImageExportService().export(model: model, to: destination)

        #expect(try Data(contentsOf: manifestURL) == manifestBefore)
        #expect(try Data(contentsOf: model.sourceFileURL!) == bytes)
        #expect(try Data(contentsOf: destination) == bytes)
    }

    @Test func rejectsMissingImageSource() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        let model = makeModel(kind: .image, displayName: "missing.png", sourceURL: source)

        #expect(throws: AttachmentImageExportError.sourceUnavailable) {
            try AttachmentImageExportService().export(model: model, to: destination)
        }
    }

    private func makeModel(kind: AgentAttachmentKind, displayName: String, sourceURL: URL?) -> AttachmentPreviewModel {
        AttachmentPreviewModel(
            attachment: AgentMessageAttachmentRef(
                id: "attachment",
                displayName: displayName,
                kind: kind,
                byteCount: 4,
                lifecycleStatus: .ready,
                extractionStatus: .extracted,
                manifestRelativePath: "attachments/attachment/manifest.json"
            ),
            title: displayName,
            subtitle: "preview",
            body: "",
            bodyMode: kind == .image ? .image : .plain,
            sourceRelativePath: sourceURL?.lastPathComponent,
            sourceFileURL: sourceURL
        )
    }
}
