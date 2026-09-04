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

@Test func shellCommandPolicyAllowsCommonGitInspectionCommands() {
    let readOnlyCommands = [
        "git branch",
        "git branch -a",
        "git tag --list",
        "git remote -v",
        "git blame App.swift",
        "git grep TODO",
        "git rev-parse --show-toplevel",
        "git ls-files",
        "git describe --tags",
        "git shortlog -sn",
        "git stash list",
        "git config --get user.name",
        "git log --oneline -5",
        "git show HEAD --stat",
        "git diff --stat",
        "git status --short",
        "git symbolic-ref HEAD",
        "file README.md",
        "stat README.md",
        "du -sh Sources"
    ]
    for command in readOnlyCommands {
        #expect(LocalShellCommandPolicy.classify(command).risk == .readOnly, "Git 检查类命令应免审批执行: \(command)")
    }
    #expect(LocalShellCommandPolicy.classify("git commit -m fix").risk == .workspaceWrite)
    #expect(LocalShellCommandPolicy.classify("git push origin main").risk == .network)
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

@Test func bashToolHardKillsProcessThatIgnoresSIGTERM() async throws {
    let workspace = try makeShellTempWorkspace()
    let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    let start = ContinuousClock.now

    // SIGTERM 被 trap 忽略的进程：声明超时必须是硬期限——
    // SIGTERM 宽限期内未退出则 SIGKILL 强杀，工具不能永久卡死。
    await #expect(throws: LocalWorkspacePolicyError.self) {
        _ = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"command":"trap '' TERM; connorHardKillMarker=1; while :; do :; done","timeoutSeconds":1}"#),
            context: .shellToolTestContext(toolCallID: "bash-hard-timeout")
        )
    }
    let elapsed = ContinuousClock.now - start
    #expect(elapsed < .seconds(6), "忽略 SIGTERM 的进程应在 SIGKILL 宽限期内返回，实际耗时 \(elapsed)")
    let survivor = try pgrep("connorHardKillMarker")
    #expect(!survivor, "超时后进程应已被强杀，不应残留")
}

@Test func bashToolStopsProcessAndThrowsCancellationWhenTaskIsCancelled() async throws {
    let workspace = try makeShellTempWorkspace()
    let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))
    let start = ContinuousClock.now
    let task = Task {
        try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"command":"trap '' TERM; connorCancelMarker=1; while :; do :; done","timeoutSeconds":30}"#),
            context: .shellToolTestContext(toolCallID: "bash-cancel")
        )
    }
    try await Task.sleep(nanoseconds: 300_000_000)
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("任务取消后 Shell 工具应抛出 CancellationError，而不是正常返回")
    } catch is CancellationError {
        // 期望行为：立即终止进程并把取消传播给上层
    } catch {
        Issue.record("期望 CancellationError，实际得到 \(error)")
    }
    let elapsed = ContinuousClock.now - start
    #expect(elapsed < .seconds(8), "取消后应快速返回，实际耗时 \(elapsed)")
    let survivor = try pgrep("connorCancelMarker")
    #expect(!survivor, "取消后进程应已被终止，不应残留")
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

/// 用 pgrep -f 检查指定命令行特征是否仍有存活进程。
private func pgrep(_ pattern: String) throws -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-f", pattern]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
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
