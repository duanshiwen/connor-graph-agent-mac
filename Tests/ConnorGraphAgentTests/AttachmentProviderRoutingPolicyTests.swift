import Foundation
import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAgent

@Suite("Attachment Provider Routing Policy Tests")
struct AttachmentProviderRoutingPolicyTests {
    @Test func routingUsesLocalContextWhenRemoteUploadDisabled() {
        let decision = AttachmentProviderRoutingPolicy().decide(manifest: manifest(kind: .pdf, bytes: 100), preferredProvider: .openAI, allowRemoteUpload: false)
        #expect(decision.mode == .inlineLocal)
        #expect(decision.provider == nil)
    }

    @Test func routingSelectsGeminiForLargeVideo() {
        let decision = AttachmentProviderRoutingPolicy().decide(manifest: manifest(kind: .video, bytes: 100_000_000), preferredProvider: nil, allowRemoteUpload: true)
        #expect(decision.mode == .providerNative)
        #expect(decision.provider == .gemini)
    }

    @Test func claudeCapabilityMarksFilesAPINonZDR() {
        let adapter = ClaudeAttachmentFileAdapter()
        let ref = adapter.makeUploadedRef(attachmentID: "a", remoteID: "file_123", remoteURI: nil, now: Date(timeIntervalSince1970: 1))
        #expect(ref.zdrEligible == false)
        #expect(ref.retentionSummary.contains("not ZDR eligible"))
        #expect(adapter.buildPromptReference(remoteRef: ref, manifest: manifest(kind: .pdf, bytes: 100))["contentBlockType"] == "document")
    }

    @Test func requestBuildersPreserveProviderSpecificBoundaries() {
        let m = manifest(kind: .pdf, bytes: 100)
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        let openAI = OpenAIAttachmentFileAdapter().buildUploadDescription(AttachmentProviderUploadRequest(manifest: m, fileURL: url))
        let claude = ClaudeAttachmentFileAdapter().buildUploadDescription(AttachmentProviderUploadRequest(manifest: m, fileURL: url))
        let gemini = GeminiAttachmentFileAdapter().buildUploadDescription(AttachmentProviderUploadRequest(manifest: m, fileURL: url))

        #expect(openAI["purpose"] == "user_data")
        #expect(claude["beta"] == "files-api-2025-04-14")
        #expect(gemini["protocol"] == "resumable")
    }

    private func manifest(kind: AgentAttachmentKind, bytes: Int64) -> AgentAttachmentManifest {
        AgentAttachmentManifest(
            id: "a",
            displayName: "file",
            originalFilename: "file",
            normalizedFilename: "file",
            kind: kind,
            mimeType: kind == .pdf ? "application/pdf" : nil,
            byteCount: bytes,
            sha256: "sha",
            lifecycleStatus: .ready,
            extractionStatus: .pending,
            storedRelativePath: "attachments/a/original/file",
            manifestRelativePath: "attachments/a/manifest.json",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
