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
    #expect(assembly.instruction.text.contains("prefer the information with the later `updated_at`"))
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
    #expect(prompt.contains("memory_os_get_current_user_profile"))
    #expect(!prompt.contains("memory_os_search"))
    #expect(!prompt.contains("memory_os_read_record"))
    #expect(!prompt.contains("memory_os_l2_find_entities"))
    #expect(prompt.contains("web_search"))
    #expect(prompt.contains("web_fetch"))
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
    #expect(prompt.contains("mail_list_recent_messages"))
    #expect(prompt.contains("mail_list_recent_messages_with_body_preview"))
    #expect(prompt.contains("mail_search_messages_with_body_preview"))
    #expect(prompt.contains("latest/recent mail browsing across all accounts"))
    #expect(prompt.contains("`direction` filter supports `all`, `received`, and `sent`"))
    #expect(prompt.contains("optional `accountID` limits one mailbox account"))
    #expect(prompt.contains("bodyPreviewMaxChars"))
    #expect(prompt.contains("do not fetch missing bodies remotely"))
    #expect(prompt.contains("mail_search_messages"))
    #expect(prompt.contains("mail_get_message"))
    #expect(prompt.contains("Never invent `messageID` values"))
    #expect(prompt.contains("message1"))
    #expect(prompt.contains("summary.id"))
    #expect(prompt.contains("calendar_search_events"))
    #expect(prompt.contains("rss_search_items"))
    #expect(prompt.contains("rss_get_item"))
    #expect(prompt.contains("browser_history_search"))
    #expect(prompt.contains("browser_history_get"))
    #expect(prompt.contains("Search/list first"))
    #expect(prompt.contains("Calendar workflow: call `calendar_search_events` first to find candidate events"))
    #expect(prompt.contains("copy the exact `eventID` from a search/list candidate"))
    #expect(prompt.contains("then call `calendar_read` with `operation: get_event`"))
    #expect(!prompt.contains("Calendar search results already return full event details"))
    #expect(prompt.contains("contentMarkdown"))
    #expect(prompt.contains("automatically capture source references into Memory OS L1"))
    #expect(prompt.contains("Do not attempt to write to memory directly"))
}

@Test func defaultSystemPromptDocumentsCalendarMutationWorkflow() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("For create, first call `calendar_read` with `operation: list_calendars`"))
    #expect(prompt.contains("exact writable `calendarID`"))
    #expect(prompt.contains("`default` is not a special calendar ID"))
    #expect(prompt.contains("display names or example IDs"))
    #expect(prompt.contains("copy the exact writable ID returned by that call"))
    #expect(prompt.contains("`operation: create_event`"))
    #expect(prompt.contains("`calendarID`, `title`, `start`, `end`, and `isAllDay`"))
    #expect(prompt.contains("`operation: update_event`"))
    #expect(prompt.contains("`operation: delete_event`"))
    #expect(prompt.contains("exact `expectedVersion`"))
    #expect(prompt.contains("copy the exact `eventID` from a search/list candidate"))
    #expect(prompt.contains("only after `get_event` succeeds"))
    #expect(prompt.contains("never reuse an ID that `get_event` did not find"))
    #expect(prompt.contains("`calendarID` is not an `eventID`"))
    #expect(prompt.contains("always pass `operation` explicitly"))
    #expect(prompt.contains("never guess calendar/event IDs or time zones"))
    #expect(prompt.contains("recurring or contains organizer/attendee scheduling semantics"))
}

@Test func defaultSystemPromptDocumentsOutboundMailApprovalWorkflow() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("Outbound mail approval workflow"))
    #expect(prompt.contains("MailDraft.id"))
    #expect(prompt.contains("mail_send_draft"))
    #expect(prompt.contains("native Compose approval card"))
    #expect(prompt.contains("Do not replace this native approval flow"))
    #expect(prompt.contains("never ask the user to provide or find a draft ID"))
    #expect(prompt.contains("omit accountID and identityID to use the Settings default send account"))
    #expect(prompt.contains("never invent default as a literal mail account ID"))
    #expect(prompt.contains("mail_list_accounts"))
}

@Test func defaultSystemPromptDocumentsPersonRegistrySemantics() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("## Person Registry and Contacts"))
    #expect(prompt.contains("not only an address book"))
    #expect(prompt.contains("people without contact methods"))
    #expect(prompt.contains("correct, merge, or delete people"))
    #expect(prompt.contains("merged people should resolve to the target person"))
    #expect(prompt.contains("deleted people should not be used as active memory context"))
    #expect(prompt.contains("Referenced People in Current User Request"))
    #expect(prompt.contains("authoritative structured resolution"))
    #expect(prompt.contains("person_id"))
    #expect(prompt.contains("Do not infer, invent, or substitute a `person_id` from `display_name`"))
    #expect(prompt.contains("status: merged"))
    #expect(prompt.contains("status: deleted"))
}

@Test func defaultSystemPromptDocumentsAtMentionPersonContext() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("@person"))
    #expect(prompt.contains("@人物"))
    #expect(prompt.contains("default attribution anchor"))
}

@Test func defaultSystemPromptDocumentsCurrentUserRelationshipEndpointRules() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("## Person Relationships"))
    #expect(prompt.contains("protected `current_user` endpoint"))
    #expect(prompt.contains("Do not expect the current user to appear in Composer @person mentions"))
    #expect(prompt.contains("I/me/my/我/我的/当前用户"))
    #expect(prompt.contains("Use Person Relationship tools for relationship edges"))
    #expect(prompt.contains("Use current-user MemoryOS tools for preferences, habits, constraints, and self-profile facts"))
}

@Test func defaultSystemPromptRequiresTaskBootstrapWorkflowOrder() throws {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    let currentTimeIndex = try #require(prompt.range(of: "At the start of every user task")?.lowerBound)
    let contextIndex = try #require(prompt.range(of: "memory_os_context", range: currentTimeIndex..<prompt.endIndex)?.lowerBound)
    let profileIndex = try #require(prompt.range(of: "memory_os_get_current_user_profile", range: contextIndex..<prompt.endIndex)?.lowerBound)
    let webSearchIndex = try #require(prompt.range(of: "web_search", range: profileIndex..<prompt.endIndex)?.lowerBound)
    let skillIndex = try #require(prompt.range(of: "connor_skill_activate", range: webSearchIndex..<prompt.endIndex)?.lowerBound)
    let synthesizeIndex = try #require(prompt.range(of: "Only after current time, internal memory, external evidence, and relevant skill instructions", range: skillIndex..<prompt.endIndex)?.lowerBound)

    #expect(currentTimeIndex < contextIndex)
    #expect(contextIndex < profileIndex)
    #expect(profileIndex < webSearchIndex)
    #expect(!prompt.contains("Other memory graph tools are available"))
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
    #expect(prompt.contains("Person instance anchored by the protected internal role marker"))
    #expect(prompt.contains("do not use mutable display names, aliases, or generic user concepts as identity keys"))
    #expect(prompt.contains("memory_os_get_current_user_profile"))
    #expect(!prompt.contains("memory_os_update_current_user_profile"))
    #expect(!prompt.contains("memory_os_search"))
    #expect(!prompt.localizedCaseInsensitiveContains("shiwen"))
}

@Test func defaultSystemPromptRequiresCurrentUserLookupBeforeAnswering() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("memory_os_get_current_user_profile"))
    #expect(prompt.contains("never let older profile memory override the user's latest explicit request"))
    #expect(prompt.contains("If the user changes their name"))
    #expect(!prompt.localizedCaseInsensitiveContains("shiwen"))
}

@Test func defaultSystemPromptDocumentsCurrentUserProfileTool() {
    let prompt = AgentInstructionSection.defaultConnorInstruction

    #expect(prompt.contains("memory_os_get_current_user_profile"))
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

@Test func agentPromptAssemblerRendersStructuredPersonReferences() async throws {
    let reference = PersonReference(
        personID: ContactID(rawValue: "person-duan-leiqiang"),
        displayName: "段磊强",
        mentionText: "@段磊强",
        status: .active,
        memoryEntityID: "memory-person-duan",
        memoryStableKey: "person:duan-leiqiang"
    )
    var assembly = AgentPromptAssembler().assemble(
        request: AgentChatRequest(
            sessionID: "session-person-ref",
            userMessage: "@段磊强 明天提醒我问他项目进展",
            personReferences: [reference]
        ),
        memoryContract: nil
    )
    assembly = try await AgentPromptDiagnosticsTransformer().transform(assembly, projectionMode: .legacySingleUserMessage)

    let rendered = try #require(assembly.personContext?.renderedText)
    #expect(rendered.contains("Referenced People in Current User Request"))
    #expect(rendered.contains("type: person"))
    #expect(rendered.contains("person_id: person-duan-leiqiang"))
    #expect(rendered.contains("display_name: 段磊强"))
    #expect(rendered.contains("memory_entity_id: memory-person-duan"))
    #expect(assembly.diagnostics.sections.contains { $0.id == "person_context" })
}

@Test func agentPromptProjectorLegacyModeIncludesPersonContextBeforeCurrentRequest() async throws {
    let request = AgentChatRequest(
        sessionID: "session-person-ref",
        userMessage: "@段磊强 明天提醒我问他项目进展",
        personReferences: [
            PersonReference(
                personID: ContactID(rawValue: "person-duan-leiqiang"),
                displayName: "段磊强",
                mentionText: "@段磊强",
                status: .active
            )
        ]
    )
    var assembly = AgentPromptAssembler().assemble(request: request, memoryContract: nil)
    assembly = try await AgentPromptDiagnosticsTransformer().transform(assembly, projectionMode: .legacySingleUserMessage)

    let modelRequest = AgentTranscriptProjector(projectionMode: .legacySingleUserMessage).project(assembly, tools: [])
    let userContent = try #require(modelRequest.messages.last?.content)

    #expect(userContent.contains("Referenced People in Current User Request"))
    #expect(userContent.contains("person_id: person-duan-leiqiang"))
    let personContextIndex = try #require(userContent.range(of: "Referenced People in Current User Request")?.lowerBound)
    let requestIndex = try #require(userContent.range(of: "@段磊强 明天提醒我问他项目进展")?.lowerBound)
    #expect(personContextIndex < requestIndex)
    #expect(request.normalizedPrompt == userContent)
}

@Test func agentPromptProjectorStructuredModeKeepsPersonContextBeforeCurrentRequest() async throws {
    let request = AgentChatRequest(
        sessionID: "session-person-ref",
        userMessage: "请整理和 @段磊强 相关的事项",
        recentMessages: [AgentMessage(id: "message-1", role: .assistant, content: "Earlier answer")],
        personReferences: [
            PersonReference(
                personID: ContactID(rawValue: "person-duan-leiqiang"),
                displayName: "段磊强",
                mentionText: "@段磊强",
                status: .active
            )
        ]
    )
    var assembly = AgentPromptAssembler().assemble(request: request, memoryContract: nil)
    assembly = try await AgentPromptDiagnosticsTransformer().transform(assembly, projectionMode: .structuredContextMessages)

    let modelRequest = AgentTranscriptProjector(projectionMode: .structuredContextMessages).project(assembly, tools: [])

    #expect(modelRequest.messages.count == 4)
    #expect(modelRequest.messages[1].content.contains("Context for continuity only"))
    #expect(modelRequest.messages[2].content.contains("Referenced People in Current User Request"))
    #expect(modelRequest.messages[2].content.contains("person_id: person-duan-leiqiang"))
    #expect(modelRequest.messages[3].content == "请整理和 @段磊强 相关的事项")
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

    let transformed = try await AgentPromptBudgetTransformer(maxEstimatedTokens: 3_500).transform(
        assembly,
        projectionMode: .structuredContextMessages
    )

    #expect(transformed.conversation.recentMessages.map(\.id) == ["message-2"])
    #expect(transformed.userRequest.text == "Do not trim me")
    #expect(transformed.instruction.text.contains("康纳同学 (Connor)"))
    #expect(transformed.diagnostics.appliedTransformers.contains("budget"))
    #expect(transformed.diagnostics.sections.first(where: { $0.id == "conversation" })?.wasTrimmed == true)
}
