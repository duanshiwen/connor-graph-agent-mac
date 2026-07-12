import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Generated Media Ingestion Service Tests")
struct GeneratedMediaIngestionServiceTests {
    @Test func generatedPNGBecomesPersistentAttachmentAndCleansTemporaryFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let temporary = root.appendingPathComponent("provider-result.png")
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try png.write(to: temporary)
        let metadata = AgentAttachmentGenerationMetadata(providerID: "openai-responses", modelID: "gpt-5", responseID: "resp-1")
        let artifact = AgentGeneratedMediaArtifact(temporaryFileURL: temporary, mimeType: "image/png", byteCount: Int64(png.count), generationMetadata: metadata)

        let service = GeneratedMediaIngestionService(store: AppSessionAttachmentStore(paths: paths))
        let manifest = try service.ingest(artifact: artifact, sessionID: "s", now: Date(timeIntervalSince1970: 1))
        let reloaded = try AppSessionAttachmentStore(paths: paths).loadManifest(sessionID: "s", attachmentID: manifest.id)

        #expect(reloaded.kind == .image)
        #expect(reloaded.origin == .modelGenerated)
        #expect(reloaded.generationMetadata == metadata)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        let stored = paths.sessionArtifactDirectories(sessionID: "s").root.appendingPathComponent(reloaded.storedRelativePath)
        #expect(try Data(contentsOf: stored) == png)
    }

    @Test func byteCountMismatchFailsBeforeCreatingAttachment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let temporary = root.appendingPathComponent("provider-result.png")
        try Data([1, 2, 3]).write(to: temporary)
        let artifact = AgentGeneratedMediaArtifact(
            temporaryFileURL: temporary,
            mimeType: "image/png",
            byteCount: 99,
            generationMetadata: AgentAttachmentGenerationMetadata(providerID: "openai", modelID: "gpt-5")
        )
        let service = GeneratedMediaIngestionService(store: AppSessionAttachmentStore(paths: paths))
        #expect(throws: GeneratedMediaIngestionError.byteCountMismatch) {
            try service.ingest(artifact: artifact, sessionID: "s")
        }
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }
}
