# AI 连接预设核对（2026-10-04）

范围：macOS、iOS/iPadOS、Android、HarmonyOS、Windows、Linux 的新建连接预设。不会迁移用户保存的模型、密钥或订阅连接。模型可用性仍取决于账号、地区及套餐。

| 服务 | 新建连接默认 / 新增选项 | 官方依据 |
| --- | --- | --- |
| OpenAI API | 常规预设默认 gpt-5.6-luna → gpt-6-luna；Apple 独立 Responses 入口默认 terra → gpt-6.1-sol；Mac/iOS/Android 列表增加 gpt-6-luna、gpt-6.1-sol，保留 gpt-6-astra 与 5.6 世代 | https://developers.openai.com/api/docs/models |
| Anthropic | 默认 claude-sonnet-5 → claude-sonnet-5-5；Mac/iOS/Android 列表增加 claude-sonnet-5-5、claude-opus-5-5，保留 sonnet-5、opus-5、fable-5-1、haiku-4-5 | https://platform.claude.com/docs/en/about-claude/models/overview |
| Gemini | 保持 gemini-3.8-flash（官方当前最新稳定版本，未加入未上线的 Gemini 4 Argon） | https://ai.google.dev/gemini-api/docs/models |
| 上下文窗口 | Mac/iOS/Android 的 SessionContextBudget，以及 Linux / Windows 的模型窗口目录（governance.rs / ContextGovernance.cs）新增 claude-opus-5 / claude-sonnet-5 / claude-fable-5 = 1,000,000 与 gpt-6 = 1,050,000；Mac 表头日期更新为 2026 Q4 | 同上 OpenAI / Anthropic 官方文档 |
| 其他服务 | 未改动（本周未取得 DeepSeek / Qwen / 豆包 / Kimi / GLM / xAI / MiniMax / StepFun 等新模型上线证据） | — |

## 协议兼容

- OpenAI 官方 API 新预设继续使用 Responses；Windows 与 Linux 的 `openai` / `openai-responses` 默认同步更新为 gpt-6-luna，两端保持与 Apple 端同一默认层级（luna = 高性价比档）。
- Claude 5.5 沿用既有 modern 判定（`contains("claude-sonnet-5")` / `contains("claude-opus-5")`），因此 claude-sonnet-5-5 与 claude-opus-5-5 自动继承 Mac/iOS/Android 的 adaptive thinking，以及 Windows/Linux 的显式 disabled 策略，无需改动判定代码。
- 本次只改默认模型与可选模型列表，未触碰各端请求构造、流式解析与工具调用逻辑。

## 有意保留

- 未加入 Gemini 4 Argon：Google 官方模型文档未出现该模型，仅有社区与订阅源消息，不作为预设依据。
- 未加入 GPT-6.1 Astra：本周报道为「因幻觉问题暂停发布」，未上线，不写入预设。
- OpenRouter 与 OpenRouter · Anthropic 预设保持 `openai/gpt-5.6-luna`、`anthropic/claude-sonnet-5`：第三方网关目录未在本轮取得官方确认。
- 国内智谱端点保留 glm-5.2；TokenDance、Vercel、Coding Plan、GitHub Copilot 的专属模型别名不套用普通 API 名称。
- 桌面原有 ChatGPT / Codex OAuth 链路不变；本地 Ollama、Mistral、Hugging Face 等已有效配置不变。
- 没有使用用户密钥执行收费联网调用。自动化验证覆盖本地请求格式和配置；实际账号权限需在客户端连接测试确认。

## 本地验证

- Mac：`swift build` 通过；`swift test --filter "Preset|ContextBudget|LLMSettings|AnthropicCompatible|OpenAIResponses"` 17 项通过（含 Kimi、GLM、国内套餐与 Anthropic 兼容预设）。
- Linux：`cargo test --offline` 全量通过（connor-core、memory-search-kernel、RSS 与搜索套件均 0 失败），新增窗口推断断言通过。
- Android：`:core:provider:test :core:agent:test --offline --rerun` BUILD SUCCESSFUL。
- iOS：2 个改动文件 `swiftc -parse` 通过；未执行模拟器或真机整包构建。
- 鸿蒙：静态检查；tools 下自检脚本不覆盖预设列表，未安装完整鸿蒙 SDK，未构建 HAP。
- Windows：静态检查；当前机器无 .NET SDK，未构建安装包、未运行 xUnit 用例。
- 官方依据复核：OpenAI 模型文档确认 gpt-6-astra / gpt-6.1-sol / gpt-6-luna 均为 1.05M 上下文；Anthropic 模型总览确认 Claude Sonnet 5.5 / Opus 5.5 / Fable 5.1 均为 1M 上下文、Haiku 4.5 为 200K。
- 六端一致性：OpenAI 与 Anthropic 的默认模型与可选列表已逐端对齐；上下文窗口目录对齐 Mac/iOS/Android/Linux/Windows 五处（鸿蒙无该目录）；各仓库 `git diff` 复核通过。
