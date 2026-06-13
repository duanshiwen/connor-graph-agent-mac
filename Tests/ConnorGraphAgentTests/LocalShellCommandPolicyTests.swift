import Foundation
import Testing
import ConnorGraphAgent

@Test func shellCommandPolicyClassifiesReadOnlyAndDestructiveCommands() {
    #expect(LocalShellCommandPolicy.classify("pwd").risk == .readOnly)
    #expect(LocalShellCommandPolicy.classify("git status --short").risk == .readOnly)
    #expect(LocalShellCommandPolicy.classify("mkdir Sources").risk == .workspaceWrite)
    #expect(LocalShellCommandPolicy.classify("curl https://example.com").risk == .network)
    #expect(LocalShellCommandPolicy.classify("sudo rm -rf /").risk == .destructive)
}

@Test func bashToolExecutesReadOnlyCommandInWorkspace() async throws {
    let workspace = try makeShellTempWorkspace()
    try "hello\n".write(to: workspace.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
    let tool = LocalBashTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    let result = try await tool.execute(
        arguments: try AgentToolArguments(json: #"{"command":"cat hello.txt","timeout_seconds":5}"#),
        context: .shellToolTestContext(toolCallID: "bash-1")
    )

    #expect(result.toolName == "Bash")
    #expect(result.contentText.contains("hello"))
    #expect(result.contentJSON?.contains(#""exitCode":0"#) == true)
}

@Test func bashToolRejectsDestructiveCommand() async throws {
    let workspace = try makeShellTempWorkspace()
    let tool = LocalBashTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    await #expect(throws: LocalWorkspacePolicyError.self) {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"command":"sudo rm -rf /","timeout_seconds":5}"#),
            context: .shellToolTestContext(toolCallID: "bash-danger")
        )
    }
}

@Test func bashToolTimesOutLongRunningCommand() async throws {
    let workspace = try makeShellTempWorkspace()
    let tool = LocalBashTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

    await #expect(throws: LocalWorkspacePolicyError.self) {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"command":"sleep 2","timeout_seconds":1}"#),
            context: .shellToolTestContext(toolCallID: "bash-timeout")
        )
    }
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
