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
}
