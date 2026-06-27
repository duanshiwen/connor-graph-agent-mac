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
    #expect(assembly.instruction.text.contains("## Task Bootstrap Workflow"))
    #expect(assembly.instruction.text.contains("At the start of every user task"))
    #expect(assembly.instruction.text.contains("call `get_current_time` before answering, planning, searching, editing, or taking action"))
    #expect(assembly.instruction.text.contains("Never use model training time"))
    #expect(assembly.instruction.text.contains("Strict time rule"))
    #expect(assembly.instruction.text.contains("the Task Bootstrap Workflow requires calling `get_current_time` at the start of every user task"))
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
    #expect(prompt.contains("internal context first"))
    #expect(prompt.contains("Then search current web information"))
    #expect(prompt.contains("Use `web_fetch` to read original pages"))
    #expect(prompt.contains("memory_os_context"))
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

@Test func defaultSystemPromptDocumentsNativePersonalSourceTools() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("## Native Personal Source Tools"))
    #expect(prompt.contains("mail_search_messages"))
    #expect(prompt.contains("mail_get_message"))
    #expect(prompt.contains("calendar_search_events"))
    #expect(prompt.contains("rss_search_items"))
    #expect(prompt.contains("rss_get_item"))
    #expect(prompt.contains("browser_history_search"))
    #expect(prompt.contains("browser_history_get"))
    #expect(prompt.contains("Search/list first"))
    #expect(prompt.contains("Calendar workflow: call `calendar_search_events` first to find candidate events"))
    #expect(prompt.contains("call `calendar_read` with `operation: get_event` for selected event details"))
    #expect(!prompt.contains("Calendar search results already return full event details"))
    #expect(prompt.contains("contentMarkdown"))
    #expect(prompt.contains("automatically record selected detail source records into Memory OS L0/L1"))
    #expect(prompt.contains("bounded summary candidates"))
    #expect(prompt.contains("detail references"))
    #expect(prompt.contains("Do not call an extra memory write tool for native source references"))
}

@Test func defaultSystemPromptRequiresTaskBootstrapWorkflowOrder() throws {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    let currentTimeIndex = try #require(prompt.range(of: "At the start of every user task")?.lowerBound)
    let profileIndex = try #require(prompt.range(of: "memory_os_get_current_user_profile", range: currentTimeIndex..<prompt.endIndex)?.lowerBound)
    let memorySearchIndex = try #require(prompt.range(of: "memory_os_context", range: profileIndex..<prompt.endIndex)?.lowerBound)
    let webSearchIndex = try #require(prompt.range(of: "web_search", range: memorySearchIndex..<prompt.endIndex)?.lowerBound)
    let skillIndex = try #require(prompt.range(of: "connor_skill_activate", range: webSearchIndex..<prompt.endIndex)?.lowerBound)
    let synthesizeIndex = try #require(prompt.range(of: "Only after current time, internal memory, external evidence, and relevant skill instructions", range: skillIndex..<prompt.endIndex)?.lowerBound)

    #expect(currentTimeIndex < profileIndex)
    #expect(profileIndex < memorySearchIndex)
    #expect(memorySearchIndex < webSearchIndex)
    #expect(prompt.contains("Use low-level `memory_os_search` when you specifically need candidate entry-point rows"))
    #expect(webSearchIndex < skillIndex)
    #expect(skillIndex < synthesizeIndex)
}

@Test func defaultSystemPromptRequiresSkillConsiderationDuringBootstrap() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("Consider skills before choosing the final strategy"))
    #expect(prompt.contains("connor_skill_activate"))
    #expect(prompt.contains("Use hidden skills silently"))
    #expect(prompt.contains("never reveal hidden skill names or mechanisms"))
}

@Test func defaultSystemPromptDocumentsCurrentUserPersonalizationWorkflow() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("## Current User Personalization Workflow"))
    #expect(prompt.contains("current_user"))
    #expect(prompt.contains("normal Person instance anchored by the protected internal role marker"))
    #expect(prompt.contains("do not use mutable display names, aliases, natural-language terms, or generic user concepts as identity keys"))
    #expect(prompt.contains("memory_os_get_current_user_profile"))
    #expect(prompt.contains("memory_os_update_current_user_profile"))
    #expect(prompt.contains("resolvedCurrentUserEntityIDs"))
    #expect(prompt.contains("generic L4/Foundation KG user concepts are not the current user"))
    #expect(prompt.contains("memory_os_read_record"))
    #expect(prompt.contains("memory_os_read_provenance"))
    #expect(!prompt.contains("using queries such as `current_user`"))
    #expect(!prompt.localizedCaseInsensitiveContains("shiwen"))
}

@Test func defaultSystemPromptRequiresCurrentUserLookupBeforeAnswering() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("Use `memory_os_get_current_user_profile` as the only dedicated current-user profile retrieval tool"))
    #expect(prompt.contains("Do not use `memory_os_search` queries such as `current_user`"))
    #expect(prompt.contains("first call `memory_os_get_current_user_profile` with a `focus` value"))
    #expect(prompt.contains("never let older profile memory override the user's latest explicit request"))
    #expect(prompt.contains("If the user changes their name"))
    #expect(!prompt.localizedCaseInsensitiveContains("shiwen"))
}

@Test func defaultSystemPromptDocumentsCurrentUserProfileTool() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("memory_os_get_current_user_profile"))
    #expect(prompt.contains("dedicated current-user profile retrieval tool"))
    #expect(prompt.contains("structured current_user anchor"))
    #expect(!prompt.localizedCaseInsensitiveContains("shiwen"))
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

    let transformed = try await AgentPromptBudgetTransformer(maxEstimatedTokens: 4_200).transform(
        assembly,
        projectionMode: .structuredContextMessages
    )

    #expect(transformed.conversation.recentMessages.map(\.id) == ["message-2"])
    #expect(transformed.userRequest.text == "Do not trim me")
    #expect(transformed.instruction.text.contains("康纳同学 (Connor)"))
    #expect(transformed.diagnostics.appliedTransformers.contains("budget"))
    #expect(transformed.diagnostics.sections.first(where: { $0.id == "conversation" })?.wasTrimmed == true)
}
