import Testing
@testable import ConnorGraphCore
@testable import ConnorGraphAgent

@Suite("Attachment Prompt Routing Tests")
struct AttachmentPromptRoutingTests {
    @Test func renderedAttachmentContextIncludesProviderNativeDelivery() {
        let plan = AttachmentContextPlan(providerNativeBlocks: [
            AttachmentProviderNativeBlock(
                attachmentID: "a",
                displayName: "video.mp4",
                provider: .gemini,
                remoteFileID: "files/a",
                remoteURI: "gemini://files/a",
                reason: "Gemini supports video files"
            )
        ])

        let rendered = AgentAttachmentContextSection(plan: plan).renderedText

        #expect(rendered.contains("Provider-native attachment delivery"))
        #expect(rendered.contains("gemini"))
        #expect(rendered.contains("files/a"))
    }

    @Test func imageAttachmentsRenderAsVisionDeliveryAndProjectToContentParts() throws {
        let dataURL = "data:image/png;base64,aGVsbG8="
        let plan = AttachmentContextPlan(imageBlocks: [
            AttachmentImageBlock(
                attachmentID: "img-1",
                displayName: "diagram.png",
                mimeType: "image/png",
                dataURL: dataURL,
                sourceRelativePath: "attachments/img-1/original/diagram.png"
            )
        ])
        let rendered = AgentAttachmentContextSection(plan: plan).renderedText
        #expect(rendered.contains("Vision image attachments"))
        #expect(rendered.contains("diagram.png"))
        #expect(!rendered.contains("aGVsbG8="))

        let request = AgentTranscriptProjector().project(
            AgentPromptAssembly(
                conversation: AgentConversationSection(),
                userRequest: AgentUserRequestSection(text: "Describe it."),
                attachmentContext: AgentAttachmentContextSection(plan: plan)
            ),
            tools: []
        )
        let user = try #require(request.messages.last)
        #expect(user.contentParts?.count == 2)
        #expect(user.contentParts?.last?.kind == .imageDataURL)
        #expect(user.contentParts?.last?.dataURL == dataURL)
    }

    @Test func renderedAttachmentContextMarksTruncatedInlineBlocks() {
        let plan = AttachmentContextPlan(inlineBlocks: [
            AttachmentInlineBlock(
                attachmentID: "a",
                displayName: "notes.md",
                kind: .markdown,
                content: "# Notes",
                sourceRelativePath: "attachments/a/derivatives/current/extracted.md",
                isTruncated: true
            )
        ])

        let rendered = AgentAttachmentContextSection(plan: plan).renderedText

        #expect(rendered.contains("## User Attachments"))
        #expect(rendered.contains("Attachment content truncated"))
        #expect(rendered.contains("attachments/a/derivatives/current/extracted.md"))
    }
}
