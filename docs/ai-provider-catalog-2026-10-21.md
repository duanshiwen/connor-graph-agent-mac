# AI 连接预设官方资料核对（2026-10-21）

范围：macOS、iOS/iPadOS、Android、HarmonyOS、Windows、Linux 的内置对话/Agent 连接预设。按量 API、Coding/Token Plan、聚合网关分别核对。资料核对不等于使用账户密钥调用成功；模型权限、地区、订阅档位仍由提供商决定。现有用户连接、密钥、自定义模型不会被覆盖。

## 主要更新

| 提供商 | 本次确认的模型 ID | API Base URL / 协议 | 官方依据 |
| --- | --- | --- | --- |
| Xiaomi MiMo | `mimo-v2.6-pro`、`mimo-v2.6-flash`、`mimo-v2.6-pro-ultraspeed` | `https://api.xiaomimimo.com/v1`，Chat Completions；支持 api-key 或 Bearer | [API 文档](https://mimo.mi.com/docs/zh-CN/api/chat/openai-api)、[发布说明](https://mimo.mi.com/docs/zh-CN/news/latest/v2-6) |
| DeepSeek | `deepseek-flash`、`deepseek-v4-pro` | `https://api.deepseek.com`（兼容 `/v1`），Chat Completions | [快速开始](https://api-docs.deepseek.com/) |
| Kimi | 按量 `kimi-k3`、`kimi-k2.7-code`、`kimi-k2.7-code-highspeed`、`kimi-k2.6` | `https://api.moonshot.cn/v1`，Chat Completions | [快速开始](https://platform.kimi.com/docs/get-api-key) |
| 智谱 / Z.AI | `glm-5.3`、`glm-5.3-flash`、`glm-5.3-flashx` | 国内 `https://open.bigmodel.cn/api/paas/v4`，国际 `https://api.z.ai/api/paas/v4` | [GLM-5.3](https://docs.bigmodel.cn/cn/guide/models/text/glm-5.3)、[Flash/FlashX](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash)、[Z.AI](https://docs.z.ai/guides/vlm/glm-5.3-flash) |
| MiniMax | `MiniMax-M3.1-Flash`、`MiniMax-M3` | `https://api.minimax.cn/v1`，Chat Completions | [OpenAI SDK / 当前模型](https://platform.minimax.cn/docs/api-reference/text-openai-api) |
| StepFun | 稳定默认 `step-3.7-flash`；单独预览预设 `step-5-preview` | `https://api.stepfun.com/v1`，Chat Completions | [模型目录](https://platform.stepfun.com/docs/zh/guides/models/list)、[Step 5 Preview](https://platform.stepfun.com/docs/zh/guides/models/step-5-preview) |
| Google | 保留 `gemini-3.8-flash` 默认，新增 `gemini-4-argon` 选择 | `https://generativelanguage.googleapis.com/v1beta/openai`，Chat Completions | [模型目录](https://ai.google.dev/gemini-api/docs/models)、[OpenAI 兼容](https://ai.google.dev/gemini-api/docs/openai) |
| Anthropic | `claude-sonnet-5-5`、`claude-opus-5-5`、`claude-haiku-5-5`、`claude-fable-5-1` | `https://api.anthropic.com`，Messages，x-api-key | [模型目录](https://platform.claude.com/docs/en/models/overview) |
| xAI | `grok-4.7` | `https://api.x.ai/v1`，**Responses** | [Grok 4.7](https://docs.x.ai/developers/grok-4-7) |
| OpenRouter | `openai/gpt-6-luna`、`anthropic/claude-sonnet-5.5` | `https://openrouter.ai/api/v1`，Chat Completions | [公开实时目录](https://openrouter.ai/api/v1/models) |
| Vercel AI Gateway | `anthropic/claude-sonnet-5.5` | `https://ai-gateway.vercel.sh/v1`，Messages / Bearer（已有 Apple 预设） | [公开目录](https://ai-gateway.vercel.sh/v1/models)、[Messages 接入](https://vercel.com/docs/ai-gateway/sdks-and-apis/anthropic-messages-api) |
| Mistral | 保留 `mistral-large-latest`；单独预览预设 `mistral-large-4` | `https://api.mistral.ai/v1`，Chat Completions | [Large 4（Public Preview）](https://docs.mistral.ai/models/mistral-large-4-0) |

小米 V2.5-Pro / V2.5 的官方下线时间为 **2026-10-21 10:00（UTC+8）**；新预设和 Apple 添加连接向导均改用 V2.6，不把 ASR/TTS 模型放进对话模型清单。API 模型 ID 必须全小写；不存在本次已确认的小米“5.6”模型。

DeepSeek `deepseek-flash` 是当前推荐别名，服务于 V4.1-Flash-1017；避免把已退休的 `deepseek-v4-flash` 当作新连接的首选。直连官方 Anthropic 使用连字符版本号，聚合网关使用其目录中的点号，不能互相替换。

## 已核对、保留的预设

| 提供商 | 保留项 | 官方依据 |
| --- | --- | --- |
| OpenAI | `https://api.openai.com/v1` / Responses；`gpt-6-luna`、`gpt-6.1-sol`、`gpt-6-astra` 已是当前系列，保留低成本默认 | [OpenAI Docs 模型目录](https://developers.openai.com/api/docs/models) |
| 阿里百炼 | `https://dashscope.aliyuncs.com/compatible-mode/v1`；`qwen3.8-flash`、`qwen3.8-max` | [Qwen3.8-Flash](https://help.aliyun.com/zh/model-studio/qwen3-8-flash) |
| 火山方舟 | `https://ark.cn-beijing.volces.com/api/v3`；`doubao-seed-2-1-pro-260915`，补充 `doubao-seed-2-1-lite-260915` | [模型目录](https://docs.volcengine.com/docs/ark/model-list?lang=en)、[发布记录](https://docs.volcengine.com/docs/ark/model-release-announcement?lang=zh) |
| TokenDance | `https://tokendance.space/gateway/v1`；`seed-2.1-pro` 在公开目录中仍可用；网关自有 ID 与上游官方 ID 分开 | [公开实时目录](https://tokendance.space/gateway/v1/models) |
| Groq | `https://api.groq.com/openai/v1`；`openai/gpt-oss-120b` | [支持模型](https://console.groq.com/docs/models)、[兼容接口](https://console.groq.com/docs/openai) |
| Cerebras | `https://api.cerebras.ai/v1`；`gpt-oss-120b` | [支持模型](https://inference-docs.cerebras.ai/models/overview) |
| Hugging Face | `https://router.huggingface.co/v1`；`openai/gpt-oss-120b`，实际路由取决于服务商可用性 | [Inference Providers](https://huggingface.co/docs/inference-providers/index) |
| Ollama | 保留本机回环地址和原有本地模型示例；实际模型由用户安装情况决定 | [OpenAI 兼容](https://docs.ollama.com/api/openai-compatibility) |

## 套餐与兼容性

- [小米 Token Plan](https://mimo.mi.com/docs/tokenplan/subscription)：国内 `https://token-plan-cn.xiaomimimo.com/v1`，沿用 tp- Key；Apple 套餐模型同步为 V2.6。
- [百炼 Coding Plan](https://help.aliyun.com/zh/model-studio/coding-plan)：`https://coding.dashscope.aliyuncs.com/v1`，sk-sp- Key。官方套餐列表与普通 API 不同：更新默认为 `qwen3.7-plus`，保留列明的 `qwen3.6-plus`、`kimi-k2.5`、`glm-5`、`MiniMax-M2.5`、`qwen3.5-plus`，移除未在当前套餐文档列出的 coder-plus。
- [Kimi Code](https://www.kimi.com/help/kimi-code/models)：`https://api.kimi.com/coding/v1`；别名 `kimi-for-coding` 已就地升级至 K2.8 Preview，继续使用该别名。补充 `k3-256k`，保留 `k3` 和高速版；需相应会员权限。
- [Step Plan](https://platform.stepfun.com/docs/zh/step-plan/quick-start)：`https://api.stepfun.com/step_plan/v1`；官方推荐验证模型已改为 `step-5-preview`。
- 智谱/Z.AI Coding Plan 保留各自 `/api/coding/paas/v4` 专用地址，更新可选模型，不能拿普通按量模型权限推断套餐权限。
- GLM-5.3 默认开启思考，不能发送 `thinking.type=disabled`。新预设沿用现有 Chat Completions 实现，普通连接不注入该禁用参数。
- MiniMax-M3.1-Flash 强制开启思考；使用模型默认值。更新官方 Base URL，未使用密钥做计费请求。
- Apple / Android 新增 Haiku 5.5 的 adaptive thinking 识别，避免误用旧式 `budget_tokens`。

本次不调整用户现存连接、OAuth 登录、GitHub Copilot 订阅模型协商或生成媒体配置。旧连接如果仍保存了已下线模型，需要用户重新添加或修改该连接。静态目录确认无法替代六个平台的完整流式对话、工具续跑和账户授权验证。
