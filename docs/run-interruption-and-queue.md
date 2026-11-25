# 运行中补充、排队、停止与恢复（2026-11-25）

Android、macOS、iOS/iPadOS、Linux、鸿蒙手机/平板及桌面客户端已接入会话级持久化指令收件箱。Windows 保留已有实现。本文记录代码与验证范围，不表示已经发布安装包或完成 Apple 原生验收。

## 共同交互语义

- 运行中普通发送加入 FIFO 队列，不进入当前模型请求；当前任务成功结束后由会话运行管理器继续消费。
- “打断”保存新指令后只中断模型生成；已经执行的工具先返回并保存结果，再把新 user 指令接入原上下文。未派发调用明确记为未执行。
- 已过时的审批等待被取消。后续规划继续使用原有权限、参数审核和发送确认，不沿用失效审批。
- 停止会暂停队列；停止或进程重启不会自动重放写操作。明确继续后复用已保存上下文、部分输出、工具调用和结果。
- 指令接收与完成提交共用串行持久化边界；完成后到达的打断进入后续队列，不会静默消失。队列在新任务上下文保存时领取，并按指令 ID 去重。
- 已保存的工具结果按 call ID 恢复；未能确认执行结果时注入“状态未知、先核对、不要自动重复写入”的修复结果。
- 文本、完整结构化结果、附件模型上下文及 provider 元数据分别按各端协议保存；大工具结果不因本次打断而截断。Apple 图片工具结果另存模型内容部分以支持停止后的恢复。

## 实现位置

| 客户端 | 收件箱与持久化 | 界面/调度 |
| --- | --- | --- |
| Android | `RunMailbox.kt`；应用私有 `agent-inboxes/<sessionId>.json` | `AgentRuntime`、`ConnorViewModel`、Compose 输入区 |
| macOS、iOS/iPadOS | `AgentRunMailbox.swift`；`sessions/<id>/state/run-mailbox.json` | `AgentLoopController`、`NativeSessionManager`、`AppRuntimeLifecycle`、SwiftUI 输入区 |
| Linux | `agent/mailbox.rs`；`sessions/<id>/state/run-mailbox.json` | `loop_runner.rs`、GTK 输入区、后台队列推进 |
| 鸿蒙 | `RunMailbox.ets`；SettingsDao 的 `agent.inbox.<sessionId>` | `AgentRuntime`、`ChatRunCoordinator`、按设备类型保留原布局的输入区 |

Linux 与 Apple 通过 `read_run_tool_result` 分页回读原始工具结果。完整持久化不等于每次请求无限量装入模型窗口；上下文预算与权限流程仍然有效。

## 已执行验证

| 客户端 | 本机结果 |
| --- | --- |
| Android | `:core:agent:test` 311 项通过；`:app:compileDebugKotlin` 通过 |
| Linux | `run_mailbox` 6 项、`round3_agent` 16 项、`agent_run_persistence_parity` 6 项通过；`cargo check -p connor-linux --offline` 通过 |
| 鸿蒙 | 22 项生产运行时/协调器行为检查通过；原生流取消、UTF-8 和资源释放检查通过；DevEco `assembleApp` 通过（未配置发布签名） |
| macOS | 2026-11-25 在本机 Apple SDK 下执行 9 项相关原生回归通过：7 项收件箱测试、事件恢复测试及运行所有权测试 |
| iOS/iPadOS | 独立 Swift 6.2 容器运行同组 7 项测试通过；修改的运行时和 SwiftUI 源码语法检查通过 |

关键回归覆盖生成中打断、工具边界打断、完整 50,000 字符以上结果、失效审批、停止后部分输出恢复、FIFO/去重/领取、完成竞态、准备阶段目标保留、重启暂停与未知写操作处理。

Apple 两端另外新增了 `RunInteractionOwnershipTests`，用于原生环境核对停止后必须等待旧执行者结算才能恢复，防止两个工具执行循环重叠。macOS 版已在本机原生 Swift 测试中通过；iOS/iPadOS 仍仅通过语法检查。macOS 原生测试首次编译发现事件恢复测试辅助编码函数遗漏 `instructionApplied` 与 `generationInterrupted` 分支，补齐后上述 9 项测试通过。

Apple 的可移植测试使用真实生产收件箱与模型信封，只替换环境依赖类型；它不替代 Xcode 类型检查、完整应用构建和设备交互测试。最初移植所用的 Windows 主机没有 Apple SDK；macOS 的相关原生回归现已补验，iOS/iPadOS 原生验收及真机交互仍未执行。鸿蒙生命周期检查通过订阅者重建模拟页面切换，不等于真实设备锁屏验收。Linux 本轮执行了原生核心测试与桌面编译检查，未执行 GTK 实机交互测试。

## 复现命令

Android：`./gradlew :core:agent:test :app:compileDebugKotlin --offline`

Linux：`cargo test -p connor-core --test run_mailbox --test round3_agent --test agent_run_persistence_parity --offline`，然后 `cargo check -p connor-linux --offline`。

鸿蒙：`node --experimental-strip-types --experimental-transform-types tools/chat-lifecycle-self-check.mjs`、`node tools/stream-transport-self-check.mjs`，然后使用 DevEco 工具链执行 `hvigorw assembleApp --mode project -p product=default --no-daemon`。

Apple：`python3 Scripts/prepare-run-mailbox-portable-tests.py`，然后在 `.build/run-mailbox-portable` 执行 `swift test`；具备 Apple SDK 时还应在原包执行 `swift test` 和对应 Xcode 应用构建。

最初移植未发布安装包。2026-11-25 已补验 macOS Apple 芯片与 Intel 双架构 Release 构建及 Ad-hoc 签名，DMG 完整性通过；版本升级至 1.0.143，并在本机替换安装后确认原账号及会话正常恢复。多设备远程运行租约、跨设备实时指令同步和发布签名不属于这次本机会话交互移植。
