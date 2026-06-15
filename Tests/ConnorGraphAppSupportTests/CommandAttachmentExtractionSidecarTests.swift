import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Command Attachment Extraction Sidecar Tests")
struct CommandAttachmentExtractionSidecarTests {
    @Test func missingExecutableReturnsUnsupportedReport() async throws {
        let sidecar = CommandAttachmentExtractionSidecar(
            id: "missing",
            displayName: "Missing",
            engine: .markItDown,
            executableName: "definitely-not-a-real-connor-extractor",
            arguments: { _ in [] }
        )
        let result = try await sidecar.extract(request())
        #expect(result.report.status == .unsupported)
        #expect(result.report.warnings.first?.contains("not found") == true)
    }

    @Test func nonZeroExitIsCapturedAsFailedReport() async throws {
        let sidecar = shellSidecar(arguments: { _ in ["-c", "echo bad >&2; exit 7"] })
        let result = try await sidecar.extract(request())
        #expect(result.report.status == .failed)
        #expect(result.report.errors.joined().contains("bad") == true)
    }

    @Test func outputIsCappedAndWarned() async throws {
        let sidecar = shellSidecar(maxOutputBytes: 5, arguments: { _ in ["-c", "printf 123456789"] })
        let result = try await sidecar.extract(request())
        #expect(result.report.status == .extracted)
        #expect(result.extractedMarkdown == "12345")
        #expect(result.report.warnings.contains { $0.contains("truncated") })
    }

    @Test func timeoutIsCapturedAsFailedReport() async throws {
        let sidecar = shellSidecar(timeoutSeconds: 0.05, arguments: { _ in ["-c", "sleep 1; echo done"] })
        let result = try await sidecar.extract(request())
        #expect(result.report.status == .failed)
        #expect(result.report.errors.contains { $0.contains("timed out") })
    }

    @Test func argumentsPreservePathsWithSpaces() async throws {
        let sidecar = shellSidecar(arguments: { request in ["-c", "printf '%s' \"$1\"", "--", request.originalFileURL.path] })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("space root \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("file with spaces.docx")
        try Data("doc".utf8).write(to: file)
        let result = try await sidecar.extract(request(originalFileURL: file))
        #expect(result.report.status == .extracted)
        #expect(result.extractedMarkdown == file.path)
    }

    private func shellSidecar(
        timeoutSeconds: TimeInterval = 5,
        maxOutputBytes: Int = 1_000_000,
        arguments: @escaping @Sendable (AttachmentExtractionRequest) -> [String]
    ) -> CommandAttachmentExtractionSidecar {
        CommandAttachmentExtractionSidecar(
            id: "shell",
            displayName: "Shell",
            engine: .markItDown,
            executableName: "sh",
            timeoutSeconds: timeoutSeconds,
            maxOutputBytes: maxOutputBytes,
            arguments: arguments
        )
    }

    private func request(originalFileURL: URL? = nil) -> AttachmentExtractionRequest {
        let root = FileManager.default.temporaryDirectory
        let original = originalFileURL ?? root.appendingPathComponent("file.pdf")
        let manifest = AgentAttachmentManifest(
            id: "attachment",
            displayName: original.lastPathComponent,
            originalFilename: original.lastPathComponent,
            normalizedFilename: original.lastPathComponent,
            kind: .document,
            byteCount: 3,
            sha256: "sha",
            lifecycleStatus: .ready,
            extractionStatus: .pending,
            storedRelativePath: "attachments/attachment/original/\(original.lastPathComponent)",
            manifestRelativePath: "attachments/attachment/manifest.json",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        return AttachmentExtractionRequest(sessionID: "session", manifest: manifest, originalFileURL: original, derivativesDirectoryURL: root)
    }
}
