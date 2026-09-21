# TokenDance API Key 授权

依据：[TokenDance 官方接入文档](https://tokendance.space/docs/api-key-oauth)，核对日期 2026-09-21。

## 使用

1. 打开 AI 连接设置，新增连接并选择 **TokenDance · 词元跳动**。
2. 点击 **使用 TokenDance 授权**，在系统浏览器登录并确认 Key 名称、额度、周期、有效期和 RPM。
3. 将授权页显示的一次性授权码复制回原客户端，点击 **交换授权码并保存/添加**。
4. Key 经客户端原有凭据加密存储保存。可从连接设置测试服务可用性；已有手动输入 Key 的入口仍可使用。

本次统一采用文档规定的 Headless S256 流程，不需要本地回调端口或 URL Scheme。浏览器可在另一台设备上完成授权，但必须回到发起流程的客户端交换授权码。退出页面、切换服务商或进程重启后应重新发起授权。

## 协议与凭据

- 授权页：`https://tokendance.space/auth`。
- 参数：`code_challenge`、`code_challenge_method=S256`、稳定的 `app_url` 和 `key_name`；不传 `callback_url`。
- `app_url`：`https://duanshiwen.github.io/connor-graph-agent-mac/`，与现有应用归因一致。
- 随机 verifier 使用 32 字节安全随机数的 Base64URL 编码，仅在内存中保留；SHA-256 摘要作为 challenge。
- 交换：JSON POST `https://tokendance.space/portal/api/v1/auth/keys`，包含 `code`、`code_verifier`、`code_challenge_method`。
- 成功响应的 `key` 是普通 API Key，不是 OAuth access token；不涉及 refresh token，不改变模型协议。
- 推理地址固定为 `https://tokendance.space/gateway/v1`，采用 OpenAI Chat Completions 兼容协议。
- 客户端只允许每个流程进行一次交换尝试；授权页面的码有效期为 10 分钟，客户端另行设置从发起算起的 10 分钟保守上限。交换不自动重试。
- 若服务端已成功创建 Key、客户端却丢失响应，只能重新授权，并在 TokenDance 控制台撤销不再使用的 Key。
- 代码不记录授权码、verifier、返回 Key 或服务端错误响应正文，不把这些值放入浏览器 URL。

## 范围

此次实现主授权流程。文档中可选的 `TokenDance-Recovery-Action` 自动恢复 UI 未加入：模型请求仍使用现有错误处理，余额不足需用户充值，周期额度可等待刷新，失效 Key 可重新授权。没有自动充值、自动删除 Key 或无人值守授权。

验证仅使用本地/模拟数据，未登录真实 TokenDance 账号、未创建真实 Key、未执行收费模型请求。平台完整构建受本机 SDK 条件限制；提交记录与任务结果列出实际运行的检查。

## 本次验证

`swift test --skip-update --filter TokenDanceAPIKeyAuthTests`：构建及 2 项新增测试通过；此前 Responses/Kimi 回归通过。

没有执行真实账号端到端授权。全部步骤均保留独立本地 Git 提交，未推送。
