import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("App Session Attachment Store iWork Tests")
struct AppSessionAttachmentStoreIWorkTests {
    @Test func importsPagesPackageAsDocumentAttachmentAndQueuesExtraction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let packageURL = root.appendingPathComponent("Report.pages", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL.appendingPathComponent("Data", isDirectory: true), withIntermediateDirectories: true)
        try Data("index".utf8).write(to: packageURL.appendingPathComponent("index.zip"))
        try Data("{\"title\":\"Report\"}".utf8).write(to: packageURL.appendingPathComponent("Data/metadata.json"))

        let store = AppSessionAttachmentStore(paths: paths)
        let manifest = try store.importFile(at: packageURL, sessionID: "s")

        #expect(manifest.kind == .document)
        #expect(manifest.fileExtension == "pages")
        #expect(manifest.extractionStatus == .pending)
        #expect(manifest.storedRelativePath.hasSuffix("/original/Report.pages"))
        let storedURL = paths.sessionArtifactDirectories(sessionID: "s").root.appendingPathComponent(manifest.storedRelativePath)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: storedURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(manifest.byteCount == Int64(Data("index".utf8).count + Data("{\"title\":\"Report\"}".utf8).count))
        #expect(!manifest.sha256.isEmpty)

        let jobs = try AttachmentExtractionJobStore(paths: paths).latestJobs(sessionID: "s")
        #expect(jobs.count == 1)
        #expect(jobs.first?.attachmentID == manifest.id)
        #expect(jobs.first?.requestedCapabilities == ["document-to-markdown"])
    }
}
