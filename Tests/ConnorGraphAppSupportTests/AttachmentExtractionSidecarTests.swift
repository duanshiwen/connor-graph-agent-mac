import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Attachment Extraction Sidecar Tests")
struct AttachmentExtractionSidecarTests {
    @Test func fakeSidecarExtractsMarkdownWithRequestedCapabilities() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let original = temp.appendingPathComponent("scan.pdf")
        try Data("pdf".utf8).write(to: original)
        let manifest = manifest(kind: .pdf)
        let request = AttachmentExtractionRequest(
            sessionID: "session",
            manifest: manifest,
            originalFileURL: original,
            derivativesDirectoryURL: temp,
            requestedCapabilities: ["ocr", "vlm"]
        )
        let sidecar = FakeAttachmentExtractionSidecar(markdown: "# Extracted")

        let result = try await sidecar.extract(request)

        #expect(result.report.engine == .docling)
        #expect(result.report.capabilitiesUsed == ["ocr", "vlm"])
        #expect(result.extractedMarkdown == "# Extracted")
    }

    @Test func orchestratorUsesBuiltinTextBeforeSidecars() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let original = temp.appendingPathComponent("notes.txt")
        try "hello world".write(to: original, atomically: true, encoding: .utf8)
        let request = AttachmentExtractionRequest(
            sessionID: "session",
            manifest: manifest(kind: .text),
            originalFileURL: original,
            derivativesDirectoryURL: temp
        )
        let orchestrator = AttachmentExtractionOrchestrator(sidecars: [FakeAttachmentExtractionSidecar(markdown: "sidecar")])

        let result = try await orchestrator.extract(request)

        #expect(result.report.engine == .builtinText)
        #expect(result.report.status == .extracted)
        #expect(result.extractedMarkdown == "hello world")
    }

    @Test func orchestratorReturnsUnsupportedWhenNoSidecarAvailable() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let original = temp.appendingPathComponent("video.mp4")
        try Data([1, 2, 3]).write(to: original)
        let request = AttachmentExtractionRequest(
            sessionID: "session",
            manifest: manifest(kind: .video),
            originalFileURL: original,
            derivativesDirectoryURL: temp
        )
        let orchestrator = AttachmentExtractionOrchestrator(sidecars: [])

        let result = try await orchestrator.extract(request)

        #expect(result.report.engine == .unavailable)
        #expect(result.report.status == .unsupported)
        #expect(result.report.warnings.first?.contains("No available extractor") == true)
    }

    private func manifest(kind: AgentAttachmentKind) -> AgentAttachmentManifest {
        AgentAttachmentManifest(
            id: "attachment",
            displayName: "file",
            originalFilename: "file",
            normalizedFilename: "file",
            kind: kind,
            byteCount: 3,
            sha256: "sha",
            lifecycleStatus: .ready,
            extractionStatus: .pending,
            storedRelativePath: "attachments/attachment/original/file",
            manifestRelativePath: "attachments/attachment/manifest.json",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
