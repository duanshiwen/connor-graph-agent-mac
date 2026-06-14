import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("App Session Attachment Derivatives Tests")
struct AppSessionAttachmentDerivativesTests {
    @Test func importTextAttachmentWritesDerivativeRefsAndExtractionReport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let source = root.appendingPathComponent("source.md")
        try "# Hello".write(to: source, atomically: true, encoding: .utf8)

        let manifest = try AppSessionAttachmentStore(paths: paths).importFile(at: source, sessionID: "s", now: Date(timeIntervalSince1970: 1))
        let loaded = try AppSessionAttachmentStore(paths: paths).loadManifest(sessionID: "s", attachmentID: manifest.id)

        #expect(loaded.derivativeRefs.first?.kind == .extractedMarkdown)
        #expect(loaded.extractionReports.first?.engine == .builtinText)
        #expect(loaded.extractionReports.first?.derivativeRefs.first?.relativePath == loaded.extractedTextRelativePath)
    }
}
