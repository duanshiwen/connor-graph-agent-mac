import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("App Session Attachment Store Import Policy Tests")
struct AppSessionAttachmentStoreImportPolicyTests {
    @Test func importsAcceptedTextFileIntoCurrentAndRunDerivatives() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("notes.md")
        try "# Notes".write(to: source, atomically: true, encoding: .utf8)

        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: "s", now: Date(timeIntervalSince1970: 1))

        #expect(manifest.kind == .markdown)
        #expect(manifest.extractedTextRelativePath == "attachments/\(manifest.id)/derivatives/current/extracted.md")
        #expect(manifest.derivativeRefs.contains { $0.relativePath.contains("/derivatives/runs/") })
        let currentURL = paths.sessionArtifactDirectories(sessionID: "s").root.appendingPathComponent(manifest.extractedTextRelativePath!)
        #expect(FileManager.default.fileExists(atPath: currentURL.path))
    }

    @Test func rejectsUnsupportedHTMLWithoutCreatingAttachmentLedger() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("page.html")
        try "<html></html>".write(to: source, atomically: true, encoding: .utf8)

        do {
            _ = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: "s")
            Issue.record("Expected HTML import to be rejected")
        } catch let error as AppSessionAttachmentImportError {
            #expect(error == .rejected(filename: "page.html", reason: .unsupportedHTML))
        }

        let ledgerURL = paths.sessionArtifactDirectories(sessionID: "s").attachments.appendingPathComponent("attachment-manifest.jsonl")
        #expect(!FileManager.default.fileExists(atPath: ledgerURL.path))
    }

    @Test func rejectsOfficeArchiveImagePDFAndMedia() throws {
        let policy = AttachmentImportPolicy()
        let files = ["report.docx", "archive.zip", "photo.png", "paper.pdf", "meeting.mp3", "movie.mp4"]
        for file in files {
            let result = policy.validate(url: URL(fileURLWithPath: "/tmp/\(file)"))
            if case .accepted = result {
                Issue.record("Expected \(file) to be rejected")
            }
        }
    }
}
