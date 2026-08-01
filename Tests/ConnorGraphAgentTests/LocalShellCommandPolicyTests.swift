import Foundation
import Testing
import ConnorGraphAgent

@Test func shellCommandPolicyClassifiesReadOnlyAndDestructiveCommands() {
    #expect(LocalShellCommandPolicy.classify("pwd").risk == .readOnly)
    #expect(LocalShellCommandPolicy.classify("git status --short").risk == .readOnly)
    #expect(LocalShellCommandPolicy.classify("mkdir Sources").risk == .workspaceWrite)
    #expect(LocalShellCommandPolicy.classify("swift test --filter ParserTests").risk == .workspaceWrite)
    #expect(LocalShellCommandPolicy.classify("xcodebuild test -scheme Connor").risk == .workspaceWrite)
    #expect(LocalShellCommandPolicy.classify("curl https://example.com").risk == .network)
    #expect(LocalShellCommandPolicy.classify("sudo rm -rf /").risk == .destructive)
}

@Test func shellCommandPolicyDoesNotTrustAReadOnlyLeadingCommand() {
    #expect(LocalShellCommandPolicy.classify("git status && touch changed.txt").risk == .workspaceWrite)
    #expect(LocalShellCommandPolicy.classify("git status; curl https://example.com").risk == .network)
    #expect(LocalShellCommandPolicy.classify("git status && sudo rm -rf /").risk == .destructive)
    #expect(LocalShellCommandPolicy.classify("git status && unknown-command").risk == .unknown)
    #expect(LocalShellCommandPolicy.classify("git status > status.txt").risk == .unknown)
}

@Test func bashToolExecutesReadOnlyCommandInWorkspace() async throws {
    let workspace = try makeShellTempWorkspace()
    try "hello\n".write(to: workspace.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
    let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"command":"cat hello.txt","timeoutSeconds":15}"#),
        context: .shellToolTestContext(toolCallID: "bash-1")
    )

    #expect(result.toolName == "Shell")
    #expect(result.contentText.contains("hello"))
    #expect(result.contentJSON?.contains(#""exitCode":0"#) == true)
}

@Test func bashToolRejectsDestructiveCommand() async throws {
    let workspace = try makeShellTempWorkspace()
    let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    await #expect(throws: LocalWorkspacePolicyError.self) {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"command":"sudo rm -rf /","timeoutSeconds":5}"#),
            context: .shellToolTestContext(toolCallID: "bash-danger")
        )
    }
}

@Test func bashToolTimesOutLongRunningCommand() async throws {
    let workspace = try makeShellTempWorkspace()
    let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    await #expect(throws: LocalWorkspacePolicyError.self) {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"command":"sleep 2","timeoutSeconds":1}"#),
            context: .shellToolTestContext(toolCallID: "bash-timeout")
        )
    }
}

@Test func bashToolDrainsLargeOutputWithoutDeadlockingAndPreservesTheTail() async throws {
    let workspace = try makeShellTempWorkspace()
    let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace, maxToolOutputBytes: 4_096))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"command":"printf 'BEGIN\\n'; yes x | head -c 200000; printf '\\nEND\\n'","timeoutSeconds":10}"#),
        context: .shellToolTestContext(toolCallID: "bash-large-output")
    )

    #expect(result.error == nil)
    #expect(result.contentText.contains("BEGIN"))
    #expect(result.contentText.contains("END"))
    #expect(result.contentText.contains("middle omitted"))
    #expect(result.contentJSON?.contains(#""truncated":true"#) == true)
}

private func makeShellTempWorkspace(_ name: String = UUID().uuidString) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("connor-local-shell-tests-")
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private extension AgentToolExecutionContext {
    static func shellToolTestContext(toolCallID: String) -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run-local-shell",
            sessionID: "session-local-shell",
            groupID: "default",
            userPrompt: "test",
            toolCallID: toolCallID,
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    }
}
