import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Test func agentPromptAssemblyUsesGeneralPurposeConnorInstruction() {
    let assembly = AgentPromptAssembler().assemble(
        request: AgentChatRequest(sessionID: "session-prompt", userMessage: "Help me plan"),
        memoryContract: nil
    )

    #expect(assembly.instruction.text.contains("general-purpose local AI assistant"))
    #expect(assembly.instruction.text.contains("Graph memory is background evidence"))
    #expect(assembly.instruction.text.contains("Follow the latest user request"))
    #expect(!assembly.instruction.text.contains("specialized AI assistant for knowledge graph operations"))
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

@Test func agentPromptBudgetTransformerTrimsRecentMessagesBeforeCurrentRequest() async throws {
    let longRecent = String(repeating: "old context ", count: 600)
    let request = AgentChatRequest(
        sessionID: "session-prompt",
        userMessage: "Do not trim me",
        recentMessages: [AgentMessage(id: "message-1", role: .assistant, content: longRecent)]
    )
    let assembly = AgentPromptAssembler().assemble(request: request, memoryContract: nil)

    let transformed = try await AgentPromptBudgetTransformer(maxEstimatedTokens: 100).transform(
        assembly,
        projectionMode: .structuredContextMessages
    )

    #expect(transformed.conversation.recentMessages.isEmpty)
    #expect(transformed.userRequest.text == "Do not trim me")
    #expect(transformed.instruction.text.contains("general-purpose local AI assistant"))
    #expect(transformed.diagnostics.appliedTransformers.contains("budget"))
}
