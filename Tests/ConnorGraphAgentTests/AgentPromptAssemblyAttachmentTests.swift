import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore

@Test func promptAssemblyIncludesAttachmentSectionForInlineBlocks() async throws {
    let plan = AttachmentContextPlan(
        inlineBlocks: [
            AttachmentInlineBlock(
                attachmentID: "attachment-1",
                displayName: "notes.md",
                kind: .markdown,
                content: "# Notes\nImportant context.",
                sourceRelativePath: "attachments/attachment-1/derivatives/extracted.md"
            )
        ],
        omittedAttachments: [],
        estimatedTokens: 10
    )
    let request = AgentChatRequest(
        sessionID: "session-1",
        userMessage: "Summarize the attachment.",
        attachmentContextPlan: plan
    )

    let assembly = AgentPromptAssembler().assemble(request: request, memoryContract: nil)
    let projected = AgentTranscriptProjector(projectionMode: .structuredContextMessages).project(assembly, tools: [])

    #expect(projected.messages.contains { message in
        message.content.contains("## User Attachments") &&
        message.content.contains("notes.md") &&
        message.content.contains("Important context.")
    })
}

@Test func promptDiagnosticsIncludesAttachmentSection() {
    let plan = AttachmentContextPlan(
        inlineBlocks: [
            AttachmentInlineBlock(
                attachmentID: "attachment-1",
                displayName: "notes.md",
                kind: .markdown,
                content: "Important context.",
                sourceRelativePath: nil
            )
        ],
        omittedAttachments: [
            AttachmentOmission(
                attachmentID: "attachment-2",
                displayName: "archive.zip",
                reason: "unsupported"
            )
        ],
        estimatedTokens: 5
    )
    let assembly = AgentPromptAssembly(
        conversation: AgentConversationSection(),
        userRequest: AgentUserRequestSection(text: "Use the attachment."),
        attachmentContext: AgentAttachmentContextSection(plan: plan)
    )

    let diagnostics = AgentPromptDiagnosticsTransformer.diagnostics(
        for: assembly,
        projectionMode: .structuredContextMessages
    )

    let attachmentSection = diagnostics.sections.first { $0.id == "attachments" }
    #expect(attachmentSection?.title == "User attachments")
    #expect(attachmentSection?.notes.contains("inline=1") == true)
    #expect(attachmentSection?.notes.contains("omitted=1") == true)
}
