import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Test func agentPromptAssemblyUsesGeneralPurposeConnorInstruction() {
    let assembly = AgentPromptAssembler().assemble(
        request: AgentChatRequest(sessionID: "session-prompt", userMessage: "Help me plan"),
        memoryContract: nil
    )

    #expect(assembly.instruction.text.contains("康纳同学 (Connor)"))
    #expect(assembly.instruction.text.contains("personal AI assistant"))
    #expect(assembly.instruction.text.contains("Graph memory is background evidence"))
    #expect(assembly.instruction.text.contains("Follow the latest user request"))
    #expect(assembly.instruction.text.contains("get_current_time"))
    #expect(assembly.instruction.text.contains("Strict time rule"))
    #expect(assembly.instruction.text.contains("call the system-provided `get_current_time` tool first"))
    #expect(assembly.instruction.text.contains("Do not infer, calculate, or reuse current time from memory"))
    #expect(assembly.instruction.text.contains("If `get_current_time` is unavailable or fails, do not guess"))
    #expect(assembly.instruction.text.contains("ISO-8601 timestamps"))
    #expect(assembly.instruction.text.contains("session_get_status"))
    #expect(assembly.instruction.text.contains("session_set_status"))
    #expect(!assembly.instruction.text.contains("specialized AI assistant for knowledge graph operations"))
}

@Test func defaultSystemPromptDocumentsMemoryAndWebResearchTools() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("## Mandatory Research Workflow"))
    #expect(prompt.contains("Before solving a user problem"))
    #expect(prompt.contains("search local Memory OS"))
    #expect(prompt.contains("search current web information"))
    #expect(prompt.contains("memory_os_search"))
    #expect(prompt.contains("memory_os_read_record"))
    #expect(prompt.contains("memory_os_expand_l4"))
    #expect(prompt.contains("memory_os_read_provenance"))
    #expect(prompt.contains("web_search"))
    #expect(prompt.contains("web_fetch"))
    #expect(prompt.contains("browser_fetch"))
}

@Test func defaultSystemPromptRequiresLocalAndWebSearchForUserProblemSolving() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("must search local Memory OS"))
    #expect(prompt.contains("must search current web information"))
    #expect(prompt.contains("most complete and up-to-date background knowledge"))
    #expect(prompt.contains("If a required tool is unavailable"))
}

@Test func defaultSystemPromptDocumentsCurrentUserPersonalizationWorkflow() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("## Current User Personalization Workflow"))
    #expect(prompt.contains("current_user"))
    #expect(prompt.contains("normal Person"))
    #expect(prompt.contains("do not use mutable display names as identity keys"))
    #expect(prompt.contains("user preferences"))
    #expect(prompt.contains("user habits"))
    #expect(prompt.contains("user personality traits"))
    #expect(prompt.contains("user communication preferences"))
    #expect(prompt.contains("memory_os_search"))
    #expect(prompt.contains("memory_os_read_record"))
    #expect(prompt.contains("memory_os_expand_l4"))
    #expect(prompt.contains("memory_os_read_provenance"))
}

@Test func defaultSystemPromptRequiresCurrentUserLookupBeforeAnswering() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("Before answering or solving a user problem"))
    #expect(prompt.contains("Search relevant L2/L3/L4 memory for the user's preferences"))
    #expect(prompt.contains("never let older profile memory override the user's latest explicit request"))
    #expect(prompt.contains("If the user changes their name"))
}

@Test func agentPromptProjectorLegacyModeMatchesNormalizedPromptShape() async throws {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-prompt",
        content: "We already chose the runtime direction.",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let request = AgentChatRequest(
        sessionID: "session-prompt",
        userMessage: "What next?",
        sessionSummary: summary,
        recentMessages: [AgentMessage(id: "message-1", role: .assistant, content: "Earlier answer")]
    )
    var assembly = AgentPromptAssembler().assemble(request: request, memoryContract: nil)
    assembly = try await AgentPromptDiagnosticsTransformer().transform(assembly, projectionMode: .legacySingleUserMessage)

    let modelRequest = AgentTranscriptProjector(projectionMode: .legacySingleUserMessage).project(assembly, tools: [])

    #expect(modelRequest.messages.count == 2)
    #expect(modelRequest.messages[0].role == .system)
    #expect(modelRequest.messages[1].role == .user)
    #expect(modelRequest.messages[1].content == request.normalizedPrompt)
    #expect(modelRequest.promptDiagnostics?.projectionMode == .legacySingleUserMessage)
}

@Test func agentPromptProjectorStructuredModeKeepsCurrentUserRequestLast() async throws {
    let request = AgentChatRequest(
        sessionID: "session-prompt",
        userMessage: "Current task",
        recentMessages: [AgentMessage(id: "message-1", role: .user, content: "Old task")]
    )
    var assembly = AgentPromptAssembler().assemble(request: request, memoryContract: nil)
    assembly = try await AgentPromptDiagnosticsTransformer().transform(assembly, projectionMode: .structuredContextMessages)

    let modelRequest = AgentTranscriptProjector(projectionMode: .structuredContextMessages).project(assembly, tools: [])

    #expect(modelRequest.messages.count == 3)
    #expect(modelRequest.messages[1].content.contains("Context for continuity only"))
    #expect(modelRequest.messages[1].content.contains("Old task"))
    #expect(modelRequest.messages.last?.role == .user)
    #expect(modelRequest.messages.last?.content == "Current task")
}

@Test func agentPromptDedupeTransformerRemovesRepeatedConversationParagraphsOnly() async throws {
    let repeated = "This paragraph is intentionally long enough to be deduplicated because it repeats exactly across recent messages."
    let request = AgentChatRequest(
        sessionID: "session-dedupe",
        userMessage: "Keep current request even if it repeats: \(repeated)",
        recentMessages: [
            AgentMessage(id: "message-1", role: .assistant, content: "\(repeated)\n\nUnique assistant detail."),
            AgentMessage(id: "message-2", role: .user, content: "\(repeated)\n\nUnique user detail.")
        ]
    )
    let assembly = AgentPromptAssembler().assemble(request: request, memoryContract: nil)

    let transformed = try await AgentPromptDedupeTransformer(minParagraphCharacters: 40).transform(
        assembly,
        projectionMode: .structuredContextMessages
    )

    #expect(transformed.conversation.recentMessages[0].content.contains(repeated))
    #expect(!transformed.conversation.recentMessages[1].content.contains(repeated))
    #expect(transformed.conversation.recentMessages[1].content.contains("Unique user detail."))
    #expect(transformed.userRequest.text.contains(repeated))
    #expect(transformed.diagnostics.appliedTransformers.contains("dedupe"))
}

@Test func agentPromptBudgetTransformerTrimsOldRecentMessagesBeforeCurrentRequest() async throws {
    let oldRecent = String(repeating: "old context ", count: 300)
    let request = AgentChatRequest(
        sessionID: "session-prompt",
        userMessage: "Do not trim me",
        recentMessages: [
            AgentMessage(id: "message-1", role: .assistant, content: oldRecent),
            AgentMessage(id: "message-2", role: .user, content: "Keep this recent message")
        ]
    )
    let assembly = AgentPromptAssembler().assemble(request: request, memoryContract: nil)

    let transformed = try await AgentPromptBudgetTransformer(maxEstimatedTokens: 2_100).transform(
        assembly,
        projectionMode: .structuredContextMessages
    )

    #expect(transformed.conversation.recentMessages.map(\.id) == ["message-2"])
    #expect(transformed.userRequest.text == "Do not trim me")
    #expect(transformed.instruction.text.contains("康纳同学 (Connor)"))
    #expect(transformed.diagnostics.appliedTransformers.contains("budget"))
    #expect(transformed.diagnostics.sections.first(where: { $0.id == "conversation" })?.wasTrimmed == true)
}
