import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
@testable import ConnorGraphAppSupport

private let validPresentedPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

private func presentImageContext(sessionID: String = "present-image-session") -> AgentToolExecutionContext {
    AgentToolExecutionContext(
        runID: "run-1",
        sessionID: sessionID,
        groupID: "default",
        userPrompt: "Show the image",
        toolCallID: "call-1",
        policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
    )
}

@Suite("Present Image Agent Tool Tests")
struct PresentImageAgentToolTests {
    @Test func importsWorkspaceImageAndReturnsExactMarkdown() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let source = workspace.appendingPathComponent("diagram.png")
        try validPresentedPNG.write(to: source)
        let paths = AppStoragePaths(applicationSupportDirectory: root.appendingPathComponent("app", isDirectory: true))
        try paths.ensureDirectoryHierarchy()
        let tool = PresentImageAgentTool(
            store: AppSessionAttachmentStore(paths: paths),
            localWorkspacePolicy: LocalWorkspacePolicy(workingDirectory: workspace)
        )

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "source": .string("diagram.png"),
                "altText": .string("Architecture diagram")
            ]),
            context: presentImageContext()
        )

        let payload = try decodePayload(result)
        #expect(payload.attachment.kind == .image)
        #expect(payload.markdown == "![Architecture diagram](\(payload.localFileURL.absoluteString))")
        #expect(result.contentText.contains(payload.markdown))
        #expect(FileManager.default.fileExists(atPath: payload.localFileURL.path))
        let manifest = try AppSessionAttachmentStore(paths: paths).loadManifest(
            sessionID: "present-image-session",
            attachmentID: payload.attachment.id
        )
        #expect(manifest.origin == .toolGenerated)
    }

    @Test func downloadsHTTPImageBeforeImportingIt() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root.appendingPathComponent("app", isDirectory: true))
        try paths.ensureDirectoryHierarchy()
        let downloader = AnyPresentImageDownloader { url, _ in
            PresentImageDownload(data: validPresentedPNG, mimeType: "image/png", suggestedFilename: "remote.png", finalURL: url)
        }
        let tool = PresentImageAgentTool(
            store: AppSessionAttachmentStore(paths: paths),
            localWorkspacePolicy: LocalWorkspacePolicy(workingDirectory: workspace),
            downloader: downloader
        )

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "source": .string("https://example.com/image?id=1"),
                "altText": .string("Remote image")
            ]),
            context: presentImageContext()
        )

        let payload = try decodePayload(result)
        #expect(payload.source == "https://example.com/image?id=1")
        #expect(try Data(contentsOf: payload.localFileURL) == validPresentedPNG)
    }

    @Test func rejectsLocalPathsOutsideWorkspace() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.png")
        try validPresentedPNG.write(to: outside)
        let paths = AppStoragePaths(applicationSupportDirectory: root.appendingPathComponent("app", isDirectory: true))
        try paths.ensureDirectoryHierarchy()
        let tool = PresentImageAgentTool(
            store: AppSessionAttachmentStore(paths: paths),
            localWorkspacePolicy: LocalWorkspacePolicy(workingDirectory: workspace)
        )

        await #expect(throws: LocalWorkspacePolicyError.self) {
            _ = try await tool.execute(
                arguments: AgentToolArguments(values: [
                    "source": .string(outside.path),
                    "altText": .string("Outside")
                ]),
                context: presentImageContext()
            )
        }
    }

    private func decodePayload(_ result: AgentToolResult) throws -> PresentImageToolResultPayload {
        let json = try #require(result.contentJSON)
        return try JSONDecoder().decode(PresentImageToolResultPayload.self, from: Data(json.utf8))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("present-image-tool-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
