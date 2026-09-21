# AI 连接预设核对（2026-09-21）

范围：macOS、iOS/iPadOS、Android、HarmonyOS、Windows、Linux 的新建连接预设。不会迁移用户保存的模型、密钥或订阅连接。模型可用性仍取决于账号、地区及套餐。

| 服务 | 新建连接默认 / 新增选项 | 官方依据 |
| --- | --- | --- |
| OpenAI API | 常规预设默认 gpt-5.6-luna，Apple 独立 Responses 入口默认 terra；有列表的客户端提供 terra、sol、gpt-6-astra | https://developers.openai.com/api/docs/models |
| Anthropic | claude-sonnet-5；Mac/iOS/Android 列表增加 opus-5、fable-5-1、haiku-4-5 | https://platform.claude.com/docs/en/models/overview |
| Gemini | gemini-3.8-flash | https://ai.google.dev/gemini-api/docs/openai |
| DeepSeek | deepseek-flash（V4.1-Flash 的 API 名称） | https://api-docs.deepseek.com/news/news260910/ |
| 百炼 | qwen3.8-flash；列表增加 qwen3.8-max | https://help.aliyun.com/zh/model-studio/qwen3-8-flash |
| 豆包 | doubao-seed-2-1-pro-260915 | https://docs.volcengine.com/docs/ark/model-release-announcement?lang=zh |
| Kimi | 保留 kimi-k2.6 默认，在模型列表增加 kimi-k3 | https://www.kimi.com/help/kimi-api/api-overview |
| Z.AI 国际站 | glm-5.3 | https://docs.z.ai/guides/llm/glm-5.3 |
| xAI | grok-4.6 | https://docs.x.ai/developers/models/grok-4.6 |
| Cerebras | gpt-oss-120b，替换已下线的 llama3.1-8b | https://inference-docs.cerebras.ai/models/overview |
| Groq | openai/gpt-oss-120b | https://console.groq.com/docs/models |
| MiniMax | MiniMax-M3，原配置已是新版 | https://www.minimax.cn/models/text/m3 |
| StepFun | step3.7-flash；套餐保持 step-3.7-flash | https://github.com/stepfun-ai/Step-3.7-Flash |
| MiMo | 保留 mimo-v2.5-pro / mimo-v2.5；移除聊天选择器中的 ASR 和旧 V2 | https://platform.xiaomimimo.com/docs/en-US/news/v2.5-tts-release |
| OpenRouter | openai/gpt-5.6-luna、anthropic/claude-sonnet-5 | https://openrouter.ai/openai / https://openrouter.ai/anthropic/claude-sonnet-5 |

## 协议兼容

- OpenAI 官方 API 新预设使用 Responses，以满足 Astra 工具调用要求。GPT-5.6/6 请求不发送 temperature。
- Android Claude 5 使用 adaptive thinking，不发送旧 budget_tokens 和 temperature。Mac/iOS 已有 adaptive 支持。
- Windows/Linux/HarmonyOS 尚未持久化 Claude 签名思考块，因此 Sonnet 5 / Opus 5 显式 disabled，避免工具续跑失败；不宣称这些客户端已支持 Fable 的强制思考回放。
- Windows/Linux 的 OpenRouter Anthropic 预设改为 OpenAI 兼容协议，与 /api/v1 端点一致。
- 鸿蒙增加主要国内外服务商入口，并允许按钮换行。

## 有意保留

- 国内智谱端点保留 glm-5.2：本次未取得与国际站同等明确的国内 GLM 5.3 上线证据。
- TokenDance、Vercel、Coding Plan、GitHub Copilot 的专属模型别名不套用普通 API 名称；Z.AI 已明确公布的套餐除外。
- 桌面原有 ChatGPT 登录链路仍使用其既有配置；Android/鸿蒙的 Responses 登录链路默认更新为 gpt-5.6-terra。此次不重写桌面 OAuth。
- 本地 Ollama 默认不变，避免指定用户尚未下载的模型；Mistral/Hugging Face 已有效的配置不变。
- 没有使用用户密钥执行收费联网调用。自动化验证覆盖本地请求格式和配置；实际账号权限需在客户端连接测试确认。

## 本地验证

- Mac：构建通过；Responses、Kimi 与套餐预设定向测试 28 项通过。

- Android：`:core:provider:test :app:compileDebugKotlin --offline` 通过，84 项测试、0 失败；包含新增的 GPT temperature 和 Claude adaptive 请求回归用例。
- Linux：`cargo check -p connor-core --offline` 通过；存在与本次改动无关的已有警告。
- 鸿蒙：ChatGPT 离线自检 4 组通过；未安装完整鸿蒙 SDK，未构建 HAP。
- iOS：3 个改动文件 Swift 语法解析通过；未执行模拟器或真机整包构建。
- Windows：静态检查；当前机器无 .NET SDK，未构建安装包。
- 六端目标模型存在性、Mac/iOS 预设一致性、模型选项无重复检查通过；各仓库 `git diff --check` 通过。
