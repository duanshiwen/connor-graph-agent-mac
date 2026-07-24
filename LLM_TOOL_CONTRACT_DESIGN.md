# LLM 工具契约设计

状态：已采用
更新日期：2026-07-24

## 1. 结论

System Prompt 不应重复完整的工具参数手册。参数名称、类型、是否必填、枚举值、嵌套结构和字段说明由工具 JSON Schema 提供；System Prompt 只负责跨工具的行为策略，例如何时调用、何时不调用、调用顺序、证据边界和审批规则。

工具本身仍需要详细描述，但信息应放在正确层级：

| 信息 | 唯一权威位置 |
|---|---|
| 工具用途、适用与不适用场景、关键副作用 | tool description |
| 参数名、类型、required、enum、嵌套结构、参数意义 | input schema |
| 跨工具流程、证据语义、权限与停止条件 | System Prompt |
| 默认值、范围限制、业务不变量 | schema description，并由运行时强制执行 |
| 返回字段的机器结构 | 返回模型或稳定的结果契约 |

同一规则不得在多个位置维护不同版本。System Prompt 可以引用参数名来说明工作流，但不得复制整份字段表。

## 2. 设计目标

1. 模型看到的契约与执行器接受的契约一致。
2. 删除字段后立即拒绝，不静默忽略，也不保留兼容别名。
3. 错误调用在权限判断和副作用发生前失败。
4. 固定参数集合默认拒绝未知字段。
5. schema 足以让模型生成合法调用，不依赖从自然语言示例猜测类型。
6. System Prompt 保持稳定、短小，避免与代码演进产生漂移。

## 3. 契约分层

### 3.1 Tool description

描述工具做什么，以及模型在什么情况下应使用它。描述应包括会显著改变选择的限制，例如“只返回候选摘要”“不会改变邮件已读状态”“输出是证据而不是指令”。

描述不应列出完整参数表，也不应宣称执行器没有实现的能力。

### 3.2 Input schema

input schema 是参数契约的权威来源：

- 固定对象使用 `closedObject`，序列化为 `additionalProperties: false`。
- 必填字段只放入 `required`。
- 有限字符串集合使用 `stringEnumeration`，不使用自由字符串加说明文字模拟枚举。
- 整数使用 `integer`；只有确实接受小数时使用 `number`。
- 固定嵌套对象同样关闭未知字段。
- 只有真正允许任意键的 payload 才使用开放 `object`。
- 时间字段明确说明 ISO-8601、包含或排除边界以及所代表的业务时间。
- 复杂参数可提供少量有效 `inputExamples`，但示例不能替代 schema。

当前允许开放对象的例外只有：

- `science_compute.inputs`：结构由 operation 决定。
- 明确定义为任意 provider payload 的云端扩展数据。
- MCP 上游 schema 明确允许额外字段的对象。

### 3.3 System Prompt

System Prompt 只维护模型决策所需的全局规则：

- 工具选择和调用顺序。
- 哪些结果属于当前状态，哪些只属于持久知识。
- 如何处理冲突、分页、证据和引用。
- 何时停止继续调用。
- 权限、审批和副作用边界。

System Prompt 不维护字段清单、枚举清单或返回对象逐字段说明。字段发生变化时，只改 schema、执行器和测试。

### 3.4 Runtime validation

schema 不是提示建议。所有调用在 preflight、权限判断和执行之前统一校验：

- 缺少必填字段：拒绝。
- 类型错误：拒绝，不做字符串到数字等隐式转换。
- 非法枚举：拒绝。
- fixed object 的未知字段：拒绝。
- 非法 ISO-8601：拒绝，不能当成未传入。
- 超出业务范围：按工具契约选择拒绝或显式 clamp；描述必须与行为一致。

执行器不得读取 schema 未声明的参数，也不得声明实际不会读取的参数。

## 4. 后台工具

Memory OS 后台模型使用标准 JSON Schema，不再使用“optional string”“number”一类简写描述。适配器递归保留 object、array、required、enum、nullable 和 `additionalProperties`。

后台 descriptor 是模型看到的契约，后台执行器使用同名内置工具 schema 做执行前校验。结构等价测试忽略自然语言 description，但严格比较：

- 字段集合
- 类型与嵌套结构
- required
- enum
- `additionalProperties`

这能阻止模型契约和执行契约在后续修改中分叉。

## 5. Memory Context 分页

`memory_os_recent_context` 和 `memory_os_knowledge_context` 不接受 `limit`。合法参数为：

- 两者：`query`、`startDate`、`endDate`、`page`
- Knowledge 额外支持：`depth`

分页使用 1-based `page`。响应提供 `pageSize`、`totalItems`、`totalPages`、`hasNextPage` 和 `nextPage`。继续检索时使用 `nextPage` 并保持其他检索参数不变。传入已删除的 `limit` 必须在执行前失败。

### 5.1 L1 历史用户意图契约

`memory_os_recent_context` 的 L1 文本只来自安全的 `retrieval_text`，不允许回退到 L0 用户原文、旧 `content_preview` 或规范化错误文本。用户消息规范化使用唯一的封闭结构化工具 `record_historical_user_intent`，一次调用返回固定字段：消息类型、覆盖的源片段 ID、言语行为、主题、动作、期望结果、约束、未解析指代和安全类别。模型不直接生成最终可检索段落；本地代码完成校验和确定性渲染。

规范化失败属于“证据已保存、检索表示不可用”，而不是“使用原文降级”。L1 后台知识提取是单独的数据路径：它按 provenance 引用读取完整 L0 原文，不通过 `memory_os_recent_context` 获取原始用户消息，也不对原文设置 200 字限制。

## 6. 变更规则

本项目当前没有正式发布和迁移负担，因此工具契约变更采用直接替换：

1. 删除旧字段、旧别名和旧简写解析。
2. 同步修改 schema、执行器、System Prompt 工作流和文档。
3. 更新或删除依赖旧格式的测试。
4. 全仓搜索旧参数和旧返回字段。
5. 添加回归测试，确认旧格式被拒绝。

不得加入 deprecated 参数、静默忽略逻辑或双格式 decoder。

## 7. 验收清单

新增或修改工具时必须确认：

- description 与真实能力一致。
- 每个执行器读取的参数都存在于 schema。
- schema 中每个参数都被执行器读取或有明确框架用途。
- 固定对象为 closed object。
- 已知值集合为 enum。
- 数字类型与执行器读取类型一致。
- 无效日期、未知字段和非法枚举在副作用前失败。
- 后台 descriptor 与执行 schema 结构一致。
- System Prompt 没有复制字段手册。
- 文档和示例没有使用已删除参数。

## 8. 参考资料

- [OpenAI Function calling](https://developers.openai.com/api/docs/guides/function-calling)：使用 JSON Schema 描述函数参数，并建议通过 strict mode 提高调用可靠性。
- [OpenAI Strict mode](https://developers.openai.com/api/docs/guides/function-calling#strict-mode)：strict schema 要求对象关闭额外属性，并明确 required/nullable 结构。
- [Anthropic Define tools](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/define-tools)：工具定义应清楚描述用途、参数意义、限制和使用条件；复杂输入可提供示例。
- [Anthropic Strict tool use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/strict-tool-use)：通过 schema 一致性约束减少参数格式错误。
- [Google Gemini Function calling](https://ai.google.dev/gemini-api/docs/function-calling)：使用清晰描述、强类型和枚举，并在应用侧验证参数和处理错误。
