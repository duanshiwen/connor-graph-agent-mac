import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Media Transcription Attachment Writer Tests")
struct MediaTranscriptionAttachmentWriterTests {
    @Test func writerStoresTranscriptAsAttachmentDerivativesAndLedgerEntry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        let writer = MediaTranscriptionAttachmentWriter(paths: paths)
        let job = BrowserMediaTranscriptionJob(
            id: "job-1",
            ownerSessionID: "session-1",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video", pageTitle: "Video")
        )

        let result = try writer.write(
            job: job,
            payload: MediaTranscriptionAttachmentPayload(
                transcriptMarkdown: "# Transcript\n\nHello world",
                transcriptText: "Hello world",
                segmentsJSONL: "{\"text\":\"Hello world\"}\n",
                diagnosticsJSON: "{\"ok\":true}",
                displayName: "video-transcript.md"
            ),
            now: Date(timeIntervalSince1970: 0)
        )

        let attachmentRoot = paths.sessionArtifactDirectories(sessionID: "session-1").attachments.appendingPathComponent(result.attachmentID, isDirectory: true)
        #expect(result.manifest.kind == .markdown)
        #expect(result.manifest.extractedTextRelativePath == "attachments/\(result.attachmentID)/derivatives/current/transcript.md")
        #expect(result.derivativeRefs.contains { $0.kind == .mediaTranscript && $0.relativePath.hasSuffix("transcript.md") })
        #expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent("derivatives/current/segments.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: paths.sessionArtifactDirectories(sessionID: "session-1").attachments.appendingPathComponent("attachment-manifest.jsonl").path))
    }

    @Test func promptBuilderReferencesAttachmentWithoutInliningTranscript() {
        let job = BrowserMediaTranscriptionJob(
            id: "job-1",
            ownerSessionID: "session-1",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video", pageTitle: "Video")
        )
        let prompt = MediaTranscriptionPromptBuilder().analysisPrompt(job: job, attachmentID: "attachment-1")

        #expect(prompt.contains("附件 ID：attachment-1"))
        #expect(prompt.contains("请不要臆测附件之外的信息"))
        #expect(!prompt.contains("# Transcript"))
    }

    @Test func promptBuilderHonorsTranscribeOnlyMode() {
        let job = BrowserMediaTranscriptionJob(
            id: "job-1",
            ownerSessionID: "session-1",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video", pageTitle: "Video"),
            request: MediaTranscriptionRequest(shouldGenerateChapters: false, outputPurpose: .discussion)
        )
        let builder = MediaTranscriptionPromptBuilder()

        let completion = builder.completionMessage(job: job, attachmentID: "attachment-1")
        let prompt = builder.analysisPrompt(job: job, attachmentID: "attachment-1")

        #expect(completion.contains("只转写"))
        #expect(prompt.contains("不要求自动提炼"))
        #expect(prompt.contains("不要主动总结全文"))
    }

    @Test func promptBuilderAddsChapterTaskWhenRequested() {
        let job = BrowserMediaTranscriptionJob(
            id: "job-1",
            ownerSessionID: "session-1",
            source: BrowserMediaSourceSnapshot(pageURLString: "https://example.com/video", pageTitle: "Video"),
            request: MediaTranscriptionRequest(shouldGenerateChapters: true, outputPurpose: .summary)
        )

        let prompt = MediaTranscriptionPromptBuilder().analysisPrompt(job: job, attachmentID: "attachment-1")

        #expect(prompt.contains("生成章节、主题段落或时间线"))
        #expect(prompt.contains("不要编造时间点"))
    }
}
