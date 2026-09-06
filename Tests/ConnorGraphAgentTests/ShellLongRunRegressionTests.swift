import Foundation
import Testing
import ConnorGraphAgent

// 复现「运行久了 Shell 结果返回为空」的候选根因：
// 1) 死线竞争：命令在超时期限内自然完成（含 zsh 启动开销），却被误判为超时 → 结果为空/报错
// 2) 长会话累积：连续多轮执行后文件描述符 / 临时捕获目录泄漏，最终导致输出丢失或工具失效
// 3) 结果门禁：token 预算耗尽时 gate 把工具结果压成空串
//
// 这些用例对机器负载敏感（贴着超时期限跑、大量进程创建），必须串行执行：
// 并行用例互相抢 CPU 会让 sleep 2.90 + zsh 启动开销偶发越过 3s 期限，产生假超时。
@Suite(.serialized)
private struct ShellLongRunRegressionTests {

    @Test func shellLongSessionDoesNotLeakCaptureTempDirs() async throws {
        let workspace = try makeShellTempWorkspace()
        let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

        func captureTempCount() -> Int {
            let tmp = FileManager.default.temporaryDirectory
            let entries = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
            return entries.filter { $0.lastPathComponent.hasPrefix("connor-shell-capture-") }.count
        }

        let tempsBefore = captureTempCount()

        // 模拟长会话：连续 300 次执行，每次输出固定标记，逐次断言非空且包含标记。
        // （文件描述符计数在并行测试进程里会被其他 suite 干扰，这里只验证输出与临时目录。）
        for iteration in 1...300 {
            let marker = "seq-marker-\(iteration)"
            let result = try await tool.execute(
                arguments: try AgentToolArguments(json: #"{"command":"echo \#(marker)","timeoutSeconds":15}"#),
                context: .shellToolTestContext(toolCallID: "bash-seq-\(iteration)")
            )
            #expect(result.error == nil, "第 \(iteration) 次执行不应报错，实际: \(String(describing: result.error))")
            #expect(result.contentText.contains(marker), "第 \(iteration) 次执行输出不应为空/丢内容，实际: \(result.contentText)")
        }

        let tempsAfter = captureTempCount()
        #expect(tempsAfter - tempsBefore <= 3, "300 次执行后不应残留临时捕获目录: before=\(tempsBefore) after=\(tempsAfter)")
    }

    @Test func shellConcurrentRunsNeverReturnEmpty() async throws {
        let workspace = try makeShellTempWorkspace()
        let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

        // 满载并发：同一批 8 路并行，各自输出独立标记，全部非空。
        let batchSize = 8
        let tasks = (0..<batchSize).map { index in
            Task {
                let marker = "par-marker-\(index)"
                return try await tool.execute(
                    arguments: try AgentToolArguments(json: #"{"command":"echo \#(marker)","timeoutSeconds":20}"#),
                    context: .shellToolTestContext(toolCallID: "bash-par-\(index)")
                )
            }
        }
        for (index, task) in tasks.enumerated() {
            let result = try await task.value
            let marker = "par-marker-\(index)"
            #expect(result.error == nil, "并发路 \(index) 不应报错，实际: \(String(describing: result.error))")
            #expect(result.contentText.contains(marker), "并发路 \(index) 输出不应为空/丢内容，实际: \(result.contentText)")
        }
    }

    @Test func shellNearDeadlineCompletingCommandNeverSpuriouslyTimesOut() async throws {
        let workspace = try makeShellTempWorkspace()
        let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

        // sleep 2.90 + zsh 启动开销（约 40–80ms）≈ 2.95–2.98s，在 3s 期限内自然完成。
        // 若退出检测与超时定时器在期限附近竞争，命令会被误判为超时、结果返回为空。
        for iteration in 1...15 {
            let marker = "deadline-ok-\(iteration)"
            let result = try await tool.execute(
                arguments: try AgentToolArguments(json: #"{"command":"sleep 2.90; echo \#(marker)","timeoutSeconds":3}"#),
                context: .shellToolTestContext(toolCallID: "bash-deadline-\(iteration)")
            )
            #expect(result.error == nil, "期限内完成的命令第 \(iteration) 次不应被误判超时，实际: \(String(describing: result.error))")
            #expect(result.contentText.contains(marker), "期限内完成的命令输出不应为空，实际: \(result.contentText)")
        }
    }

    @Test func resultGateNeverSilentlyEmptiesToolResultWhenTokenBudgetIsZero() throws {
        // 修复验证：token 预算耗尽（maximumEstimatedTokens == 0）时，gate 不得把工具结果静默压成空串——
        // 这正是长会话下「Shell 结果返回为空」的机制。修复后应返回截断说明，保持行为可观测。
        let gate = AgentToolResultGate(configuration: AgentToolResultGateConfiguration())
        let result = AgentToolResult(
            toolCallID: "bash-gate",
            toolName: "Shell",
            contentText: "exitCode: 0\nstdout:\nsome meaningful output\n\nstderr:\n",
            contentJSON: "{}",
            error: nil
        )
        let gated = gate.gatedContent(for: result, maximumEstimatedTokens: 0)
        #expect(!gated.isEmpty, "token 预算为 0 时不应把结果压成空串，实际输出长度 \(gated.count)")
        #expect(gated.contains("tool result omitted"), "预算耗尽时应给出截断说明，实际: \(gated)")
    }

    @Test func shellRapidExitNeverAbortsOnTerminationStatusRead() async throws {
        let workspace = try makeShellTempWorkspace()
        let tool = LocalShellTool(policy: LocalWorkspacePolicy(workingDirectory: workspace))

        // 回归 Task 105666：轮询侧在 Foundation 感知终止前读取 process.terminationStatus 时，
        // Foundation 抛 NSInternalInconsistencyException → std::terminate → abort（测试进程
        // 直接崩溃，即为本测试失败）；退出码现统一由 terminationHandler 回收后记录进 state。
        // 高频超短命令把「退出 ↔ 回收 ↔ 退出码读取」竞态窗口打满：4 轮 × 12 路并发 echo。
        for round in 0..<4 {
            let tasks = (0..<12).map { index -> Task<AgentToolResult, Error> in
                let marker = "race-\(round)-\(index)"
                return Task {
                    try await tool.execute(
                        arguments: try AgentToolArguments(json: #"{"command":"echo \#(marker)","timeoutSeconds":10}"#),
                        context: .shellToolTestContext(toolCallID: "bash-race-\(round)-\(index)")
                    )
                }
            }
            for (index, task) in tasks.enumerated() {
                let result = try await task.value
                let marker = "race-\(round)-\(index)"
                #expect(result.error == nil, "第 \(round) 轮并发路 \(index) 不应报错，实际: \(String(describing: result.error))")
                #expect(result.contentText.contains(marker), "第 \(round) 轮并发路 \(index) 退出码不应丢失/误判，实际: \(result.contentText)")
            }
        }
    }
}

private extension AgentToolExecutionContext {
    static func shellToolTestContext(toolCallID: String) -> AgentToolExecutionContext {
        AgentToolExecutionContext(
            runID: "run-local-shell-longrun",
            sessionID: "session-local-shell-longrun",
            groupID: "default",
            userPrompt: "test",
            toolCallID: toolCallID,
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    }
}

private func makeShellTempWorkspace(_ name: String = UUID().uuidString) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("connor-local-shell-tests-")
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
