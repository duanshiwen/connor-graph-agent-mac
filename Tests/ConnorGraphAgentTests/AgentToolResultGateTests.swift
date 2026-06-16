import Testing
import ConnorGraphAgent

@Test func toolResultGateTruncatesLargeTextWithMetadata() {
    let result = AgentToolResult(
        toolCallID: "call-read-1",
        toolName: "readWorkspaceFile",
        contentText: "abcdefghijklmnopqrstuvwxyz"
    )
    let gate = AgentToolResultGate(configuration: AgentToolResultGateConfiguration(maxResultCharacters: 10))

    let gated = gate.gatedContent(for: result)

    #expect(gated.hasPrefix("abcdefghij"))
    #expect(!gated.contains("klmnopqrstuvwxyz"))
    #expect(gated.contains("...[truncated tool result:"))
    #expect(gated.contains("tool=readWorkspaceFile"))
    #expect(gated.contains("kept=10 chars"))
    #expect(gated.contains("original=26 chars"))
}

@Test func toolResultGateKeepsSmallResultsUnchanged() {
    let result = AgentToolResult(
        toolCallID: "call-small-1",
        toolName: "science_compute",
        contentText: "small result"
    )
    let gate = AgentToolResultGate(configuration: AgentToolResultGateConfiguration(maxResultCharacters: 100))

    let gated = gate.gatedContent(for: result)

    #expect(gated == "small result")
    #expect(!gated.contains("truncated"))
}

@Test func toolResultGatePrefersTextContentOverJSONMetadataWhenAvailable() {
    let result = AgentToolResult(
        toolCallID: "call-bash-1",
        toolName: "Bash",
        contentText: "exitCode: 0\nstdout:\nhello\n\nstderr:\n",
        contentJSON: "{\"exitCode\":0,\"truncated\":false}"
    )
    let gate = AgentToolResultGate(configuration: AgentToolResultGateConfiguration(maxResultCharacters: 100))

    let gated = gate.gatedContent(for: result)

    #expect(gated.contains("stdout:"))
    #expect(gated.contains("hello"))
    #expect(gated != "{\"exitCode\":0,\"truncated\":false}")
}

@Test func toolResultGateFallsBackToJSONContentWhenTextIsEmpty() {
    let result = AgentToolResult(
        toolCallID: "call-json-1",
        toolName: "graph_search",
        contentText: "",
        contentJSON: "{\"ok\":true}"
    )
    let gate = AgentToolResultGate(configuration: AgentToolResultGateConfiguration(maxResultCharacters: 100))

    let gated = gate.gatedContent(for: result)

    #expect(gated == "{\"ok\":true}")
}

@Test func toolResultGateUsesPerToolCharacterLimit() {
    let result = AgentToolResult(
        toolCallID: "call-bash-1",
        toolName: "Bash",
        contentText: "abcdefghijklmnopqrstuvwxyz"
    )
    let gate = AgentToolResultGate(configuration: AgentToolResultGateConfiguration(
        maxResultCharacters: 100,
        perToolCharacterLimits: ["Bash": 5]
    ))

    let gated = gate.gatedContent(for: result)

    #expect(gated.hasPrefix("abcde"))
    #expect(!gated.contains("fghijklmnopqrstuvwxyz"))
    #expect(gated.contains("tool=Bash"))
    #expect(gated.contains("kept=5 chars"))
    #expect(gated.contains("original=26 chars"))
}
