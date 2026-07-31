# Agent Loop 小规模真实测试方案

## 目标与边界

这套测试用于验证康纳同学的真实 Agent loop，而不是比较基础模型排行榜。它从公开评测集中抽取最小、最有代表性的行为，并增加产品特有的图片生成与轮内压缩检查。

固定边界：

- 每次只运行 6 个任务，每个任务一个新会话，避免历史状态互相污染。
- 历史轮次只携带用户消息和 LLM 最终回复；以前轮次的工具调用与结果不进入新 run。
- 轮内压缩只处理当前 run 的 tool-call/tool-result 轨迹。
- 文件数据从 `/Users/duanshiwen/Documents/一些导出的资料` 中人工白名单选择，最多 2 个文本文件，每个不超过 256 KB。
- 编辑任务只操作复制到临时测试工作区的 fixture，不改原始资料和仓库业务代码。
- 禁止发送邮件、发布内容、删除数据或执行其他不可逆外部操作。

## 公开评测依据

- [BFCL](https://gorilla.cs.berkeley.edu/blogs/8_berkeley_function_calling_leaderboard.html)：采用无需工具、单工具选择、工具相关性拒绝和多步工具调用四类行为。BFCL 完整集约 2,000 项，本方案只取行为模式，不下载或全跑数据集。
- [Terminal-Bench](https://github.com/harbor-framework/terminal-bench)：采用真实终端/文件环境、确定性验收和任务级隔离的做法，但不运行其高成本完整任务。
- [SWE-bench](https://www.swebench.com/)：采用“给定小型缺陷、修改代码、以测试结果判定”的闭环；本方案使用一个本地微型 fixture，不运行真实仓库级 issue。
- [GAIA](https://huggingface.co/datasets/gaia-benchmark/GAIA)：采用文件证据与多步推理的任务形式；本方案只保留一个受控文件问答动作。
- [OSWorld](https://os-world.github.io/)：采用最终状态验证而非仅评价回答文本的原则。图片任务通过真实产物文件验证。

## 六项微型测试

| ID | 动作 | 主要能力 | 通过条件 | Token 上限 |
|---|---|---|---|---:|
| A1 | 普通对话：“用三句话解释当前测试范围，不调用工具” | BFCL chatting / relevance | 无工具事件；恰好三句话；runCompleted | 2K |
| A2 | 读取一个白名单文本文件，回答一个可由文件中唯一标记确定的问题 | 文件选择、读取、证据约束 | 只读；答案含唯一标记；无臆造路径 | 5K |
| A3 | 修复临时 fixture 中一个 10-20 行函数，并运行一个定向测试 | 读取、编辑、终端、错误恢复 | diff 仅涉及 fixture；测试通过；无重复写入 | 12K |
| A4 | 生成一张 512x512 的简单测试图片并保存到测试输出目录 | 媒体工具选择、产物交付 | 文件存在；格式可解码；尺寸正确；非空白 | 4K 文本 Token |
| A5 | 从一个只读 MCP 工具和一个已订阅知识库各取一条事实，回答并区分来源 | 多工具路由、MCP、知识融合 | 两个来源均实际调用；引用可对应；不调用无关 Memory/邮箱工具 | 10K |
| A6 | 在 20K 有效输入窗口下连续读取 3 个受控大结果，并完成最终汇总 | 单 run 多轮、压缩、继续执行 | 出现 started/completed；压缩后继续调用；最终答案正确；无 tool orphan | 24K |

总文本预算上限为 57K Token。任何单项达到上限立即停止该项，不借助压缩绕过累计预算。

## A6 压缩专项设置

使用测试配置而不是消耗真实大上下文：

```text
modelContextWindowTokens = 24_000
reservedOutputTokens = 4_000
maximumInputTokens = 20_000
checkpoint = 70% (14_000)
compact = 80% (16_000)
emergency = 90% (18_000)
target = 45% (9_000)
minimumTokenGrowth = 2_000  // 仅测试配置
```

三个只读 fixture 工具结果各约 20-28 KB，内容包含不同的首尾校验标记。预期序列：

```text
turnStarted
toolRequested -> toolStarted -> toolFinished
...
compactionStarted
compactionCompleted
下一次模型调用或工具调用
textComplete -> runCompleted
```

验收额外检查：

- 压缩前后的历史 user/assistant 消息内容完全一致。
- 旧 tool result 替换为 checkpoint 引用，最近两个结果保留原文。
- assistant tool call ID 与 tool result ID 始终成对。
- 同一 run 可以产生 generation 1、2...，但 80% 以下且新增不足 2K Token 时不得抖动压缩。
- UI 在 started 后显示“正在压缩上下文”及流光，在 completed/failed 后自动恢复普通活动表头。

## 执行顺序

1. 建立独立测试用户与新会话，固定模型、连接和工具白名单。
2. 记录测试前 Git SHA、应用版本、模型 ID、MCP server ID、知识库 ID 与数据文件 SHA-256。
3. 按 A1-A5 运行功能冒烟；失败时停止当前项，不自动扩大范围。
4. 以测试窗口配置单独运行 A6，避免污染日常配置。
5. 导出事件日志和 LLM usage audit，按 runID 关联。
6. 对产物、diff、工具配对和 Token 总账执行确定性检查。

## 审计表

每个 run 输出一行汇总，每个步骤输出一行明细：

```text
run_id, case_id, started_at, completed_at, duration_ms, status,
model_id, prompt_tokens, completion_tokens, total_tokens,
tool_call_count, tool_failure_count, compaction_count, final_artifact

run_id, sequence, event_kind, operation, tool_name, started_at,
duration_ms, estimated_tokens_before, estimated_tokens_after,
provider_prompt_tokens, provider_completion_tokens, status, error
```

Token 统计以 Provider usage 为总账；本地估算只用于阈值判断，两者必须分栏。压缩事件记录 generation、iteration、压缩前后估算、清理的 tool result 数量和耗时。

## 停止条件

- 单项或总 Token 达到上限。
- 连续 2 次相同工具失败或相同参数重复调用。
- 发生未授权写入、发送、删除或外部副作用请求。
- 压缩后请求仍超过 90%，或压缩连续失败 2 次。
- tool-call/tool-result 配对破坏，立即判为基础设施失败，不让模型自行掩盖。

## 评分

每项只有 `pass`、`fail`、`infra_error` 三种结果。总套件通过要求 A1-A6 全部 pass；Provider 配额、网络或 MCP 服务不可用记为 infra_error，不计作 Agent 推理失败，但必须保留调用和耗时审计。
