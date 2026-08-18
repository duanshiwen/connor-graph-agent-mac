import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Note import image reference rewriting")
struct NoteImportImageReferenceRewritingTests {
    private func result(
        displayName: String = "photo.png",
        metadata: [String: String],
        storedURL: URL
    ) -> NoteImportAttachmentImportResult {
        NoteImportAttachmentImportResult(
            attachment: ImportedNoteAttachment(
                sourcePath: "/tmp/export/\(displayName)",
                displayName: displayName,
                metadata: metadata
            ),
            messageRef: AgentMessageAttachmentRef(
                id: "att-1",
                displayName: displayName,
                kind: .image,
                byteCount: 10,
                lifecycleStatus: .ready,
                extractionStatus: .pending,
                manifestRelativePath: "attachments/att-1/manifest.json"
            ),
            reused: false,
            storedFileURL: storedURL
        )
    }

    @Test("Rewrites Notion relative image targets to stored file URLs")
    func rewritesNotionRelativeImages() {
        let markdown = """
        # 标题

        正文内容。

        ![示例图片](assets/photo.png)
        """
        let stored = URL(fileURLWithPath: "/tmp/session/attachments/att-1/original/photo.png")
        let rewritten = NoteImportCoordinator.rewritingImageReferences(
            in: markdown,
            results: [
                result(metadata: ["notion_target": "assets/photo.png"], storedURL: stored)
            ]
        )
        #expect(rewritten.contains("![示例图片](file:///tmp/session/attachments/att-1/original/photo.png)"))
        #expect(!rewritten.contains("assets/photo.png"))
    }

    @Test("Rewrites percent-encoded and dot-prefixed Notion targets")
    func rewritesEncodedNotionTargets() {
        let markdown = "![图](./assets/%E6%88%91%E7%9A%84%E7%85%A7%E7%89%87.png)\n"
        let stored = URL(fileURLWithPath: "/tmp/session/attachments/att-2/original/我的照片.png")
        let rewritten = NoteImportCoordinator.rewritingImageReferences(
            in: markdown,
            results: [
                result(
                    displayName: "我的照片.png",
                    metadata: ["notion_target": "assets/我的照片.png"],
                    storedURL: stored
                )
            ]
        )
        #expect(rewritten.contains("file:///tmp/session/attachments/att-2/original/%E6%88%91%E7%9A%84%E7%85%A7%E7%89%87.png"))
    }

    @Test("Rewrites Obsidian embeds to stored file URLs")
    func rewritesObsidianEmbeddedImages() {
        let stored = URL(fileURLWithPath: "/tmp/session/attachments/att-3/original/pic.png")
        let obsidian = NoteImportCoordinator.rewritingImageReferences(
            in: "![[assets/pic.png]]",
            results: [
                result(metadata: ["obsidian_embed": "![[assets/pic.png]]"], storedURL: stored)
            ]
        )
        #expect(obsidian.contains("![photo.png](file:///tmp/session/attachments/att-3/original/pic.png)"))
    }

    @Test("Keeps Obsidian audio/video embeds as readable markers")
    func keepsNonImageAttachmentsAsMarkers() {
        let audio = NoteImportCoordinator.rewritingImageReferences(
            in: "![[voice.mp3]]",
            results: [
                result(
                    displayName: "voice.mp3",
                    metadata: ["obsidian_embed": "![[voice.mp3]]"],
                    storedURL: URL(fileURLWithPath: "/tmp/session/attachments/att-4/original/voice.mp3")
                )
            ]
        )
        #expect(audio.contains("🎵 voice.mp3"))
        #expect(!audio.contains("![voice.mp3]"))
        #expect(!audio.contains("/attachments/att-4/"))

        let video = NoteImportCoordinator.rewritingImageReferences(
            in: "![[clip.mp4]]",
            results: [
                result(
                    displayName: "clip.mp4",
                    metadata: ["obsidian_embed": "![[clip.mp4]]"],
                    storedURL: URL(fileURLWithPath: "/tmp/session/attachments/att-5/original/clip.mp4")
                )
            ]
        )
        #expect(video.contains("🎬 clip.mp4"))
    }

    @Test("Leaves non-matching images untouched")
    func leavesUnrelatedImagesUntouched() {
        let markdown = "![保持](remote-example.png)\n![其他](assets/other.png)\n"
        let rewritten = NoteImportCoordinator.rewritingImageReferences(
            in: markdown,
            results: [
                result(metadata: ["notion_target": "assets/photo.png"], storedURL: URL(fileURLWithPath: "/tmp/session/x.png"))
            ]
        )
        #expect(rewritten == markdown)
    }
}
