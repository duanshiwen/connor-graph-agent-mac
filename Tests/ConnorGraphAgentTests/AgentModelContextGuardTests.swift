import Testing
import ConnorGraphAgent

@Test func contextGuardCountsToolSchemasAndImagePayloads() {
    let request = AgentModelRequest(
        messages: [
            AgentModelMessage(
                role: .user,
                content: "inspect",
                contentParts: [.imageDataURL("data:image/png;base64," + String(repeating: "A", count: 400), mimeType: "image/png")]
            )
        ],
        tools: [
            AgentToolDefinition(
                name: "lookup",
                description: String(repeating: "schema description ", count: 20),
                inputSchema: .object(properties: ["query": .string(description: "search query")], required: ["query"])
            )
        ]
    )

    #expect(AgentModelContextGuard().estimatedInputTokens(request) > 100)
}

@Test func contextGuardClassifiesNewOversizedRequestAsCurrentInput() {
    let request = AgentModelRequest(messages: [
        AgentModelMessage(role: .system, content: "system"),
        AgentModelMessage(role: .user, content: String(repeating: "current input ", count: 100))
    ])

    #expect(throws: AgentModelContextLimitError.self) {
        try AgentModelContextGuard().validate(
            request,
            currentUserInput: String(repeating: "current input ", count: 100),
            currentAttachmentEstimatedTokens: 0,
            contextWindowTokens: 100,
            configuredPromptLimit: 1_000_000,
            reservedOutputTokens: 10,
            isAfterToolExecution: false
        )
    }
}

@Test func contextGuardClassifiesToolTraceOverflowWithoutChangingConversationState() {
    let request = AgentModelRequest(messages: [
        AgentModelMessage(role: .system, content: "system"),
        AgentModelMessage(role: .user, content: "small request"),
        AgentModelMessage(role: .tool, content: String(repeating: "tool output ", count: 100))
    ])

    do {
        try AgentModelContextGuard().validate(
            request,
            currentUserInput: "small request",
            currentAttachmentEstimatedTokens: 0,
            contextWindowTokens: 100,
            configuredPromptLimit: 1_000_000,
            reservedOutputTokens: 10,
            isAfterToolExecution: true
        )
        Issue.record("Expected tool trace overflow")
    } catch let error as AgentModelContextLimitError {
        #expect(error.kind == .currentRunToolTrace)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
