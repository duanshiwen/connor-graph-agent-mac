# Connor Graph Agent Mac 工程说明

文档更新时间：2026-07-08 GMT+8  
定位：本文件记录 Connor Graph Agent Mac 的工程架构、边界、运行布局、Memory OS、开发命令和质量约束。普通用户使用说明请看 [README.md](README.md)。

Connor Graph Agent Mac 是一个 Swift / SwiftUI macOS 应用与 SwiftPM package。它的目标不是图谱编辑器，也不是 LLM SDK 外壳，而是一个本地优先的 **memory-os-native Agent OS**。

核心产品判断：**记忆系统是后台认知基础设施，不是普通用户的前台图谱编辑器。** 用户面对的是会话、数据源、技能、自动化、浏览器、附件、任务和设置；Memory OS 在后台提供连续性、可追溯性、证据化工作记忆、可复用知识层和稳定实体/概念图谱。

---

## 1. 产品边界

Connor 当前坚持以下主权边界：

- **Session OS** 负责会话、run、journal、审批、分支、恢复快照和 Session Capsule。
- **Policy Engine** 负责权限、审批、审计和执行门禁。
- **Memory OS** 负责记忆摄取、验证、投影、检索和 current-view 推导。
- **Source Platform** 负责数据源注册表、就绪状态、凭证、策略和摄取规则。
- **Swift Native Shell** 负责 macOS 原生 UI；不要引入 Electron/Web UI，也不要 fork Craft UI。
- **Task Management Stack** 负责定时/事件任务生命周期、run history 和本地管理界面。
- **Attachment Store** 负责导入文件、manifest、派生物、解析状态和证据候选。
- **Native runtimes** 负责 Mail / RSS / 人际关系 / Calendar 的本地账号边界、同步状态和缓存。Apple `Contacts` 只是底层系统框架/适配器边界，不是产品概念本身。

明确不做的事情：

```text
公开 API
远程 daemon / 云同步
OAuth server / 团队认证 / 多用户权限
Craft UI fork
Electron/Web UI
Craft-style 多工作区
CLI/API 直接写图谱
MCP server 持有产品状态
外部模型提供方持有 Connor 会话状态
LLM 直接访问 IMAP / SMTP / OAuth / 人际关系数据源凭证
未经批准发送邮件
未经验证就把外部来源事实自动投影为 Memory OS truth records
执行 feed HTML JavaScript 或自动加载远程追踪资源
```

---

## 2. 包与构建目标

```text
Package: ConnorGraphAgentMac
Swift tools: 6.0
Platform: macOS 14+
Default localization: zh-Hans
Dependencies: Vendor/MailCoreSPM
Linked: sqlite3, Security, EventKit, Contacts, WebKit, AVFoundation, Speech, CoreLocation
Rust sidecar: SearchKernel（Tantivy 嵌入式搜索内核，进程内编译/调用）
```

说明：这里的 `Contacts` 指 Apple 系统框架。产品侧领域是 **People & Relationships / 人际关系**，包括人物档案、联系方式、组织归属、关系线索和显式结构化关系。

Products：

```text
Libraries:
- ConnorGraphCore
- ConnorGraphMemory
- ConnorGraphStore
- ConnorGraphSearch
- ConnorGraphAgent
- ConnorGraphAppSupport

Executables:
- connor-graph-agent-mac          SwiftUI macOS shell
- connor                          本地 CLI
- ConnorFoundationKGSeedBuilder   Foundation Knowledge Graph seed tool
```

主要 targets：

```text
Sources/ConnorGraphCore                 领域模型与治理基础类型
Sources/ConnorGraphMemory               Memory OS 摄取、处理、验证与投影
Sources/ConnorGraphStore                Memory OS、会话、审计、数据源的 SQLite 持久化
Sources/ConnorGraphSearch               图谱/混合检索与评估
Sources/ConnorGraphAgent                Agent loop、工具、模型提供方和策略边界
Sources/ConnorGraphAppSupport           App services、repositories、原生 runtime bridge、MCP
Sources/ConnorGraphAgentMac             SwiftUI/AppKit macOS shell、浏览器工作区、chat viewport
Sources/ConnorCLI                       本地 CLI 控制面
Sources/ConnorFoundationKGSeedBuilder   Foundation KG seed data builder
```

测试：7 个 test target，覆盖核心库模块和 app shell。

---

## 3. 总体架构

```text
SwiftUI Native Shell（聊天、侧边栏、浏览器、设置、审批）
  ↓
ConnorGraphAppSupport（app services、MCP runtime、原生数据源 bridge）
  ↓
Session OS / Source Platform / Skill Runtime / Task Surface / Readiness Gate
  ↓
ConnorGraphAgent + Native Model Providers
  ↓
Memory OS Runtime Contract
  ↓
L0 Provenance → L1 Cache Buffer → L2 Operational Facts → L3 Knowledge → L4 Stable Entities
```

Target 职责：

- **ConnorGraphCore**：Memory OS、会话、策略、附件、原生数据源、技能、任务和自动化的稳定领域模型。
- **ConnorGraphMemory**：预摄取、L0/L1 捕获决策、处理产物、验证器、L2 entity memory、L3 beliefs、L4 entity projection 和受控类型规范化。
- **ConnorGraphStore**：SQLite schema、repository、FTS/search 表、legacy graph import、session/run/audit 持久化。
- **ConnorGraphSearch**：检索 contract、混合检索抽象、评估用例和 embedding seam。
- **ConnorGraphAgent**：Agent 编排、流式模型 provider、工具执行、审批、prompt assembly、压缩和本地工具策略检查。
- **ConnorGraphAppSupport**：Session Capsule 持久化、LLM 设置、MCP runtime、附件服务、原生 Mail/RSS/人际关系/Calendar 适配器、浏览器上下文、技能和任务。
- **ConnorGraphAgentMac**：原生 app shell、chat viewport、composer、审批、浏览器工作区、附件、设置和原生数据源界面。
- **ConnorCLI**：本地可编程控制面；必须尊重 Connor 自有 repository 和策略边界。
- **ConnorFoundationKGSeedBuilder**：从结构化来源构建 Foundation Knowledge Graph seed databases。

Memory OS 不应被设计成普通用户可见的导航主界面。App 可以触发摄取、调度和工具执行，但不应该暴露 Memory OS dashboard 或直接图谱编辑器。

---

## 4. 运行时布局

运行时路径由 `AppStoragePaths` 解析，位于用户 Application Support 下的 `Connor` 目录。

```text
Connor/
├── config/
├── sessions/
├── sources/
├── skills/
├── tasks/
├── labels/
├── statuses/
├── artifacts/
├── search/
│   └── native-source-index.json
├── graph/
│   ├── connor.sqlite
│   ├── indexes/
│   ├── search-index/
│   │   └── memory-os-tantivy/
│   ├── exports/
│   ├── snapshots/
│   └── evaluations/
└── logs/
    ├── audit/
    └── runtime/
```

Session Capsule：

```text
sessions/{sessionID}/
├── manifest.json
├── state/
├── browser/
├── plans/
├── data/
├── attachments/
├── exports/
└── logs/
```

关键状态文件包括：

```text
config/session-governance.json
config/product-os-registry.json
config/runtime-settings.json
config/llm-settings.json
tasks/task-definitions.json
tasks/task-run-history.jsonl
tasks/task-event-log.jsonl
tasks/task-deletion-log.jsonl
labels/labels.json
statuses/statuses.json
graph/evaluations/retrieval-evaluation-cases.json
graph/evaluations/reports/*.json
```

凭证和 API Key 不得存储在 JSON 设置文件中。应使用 Connor 的本地加密凭证库，并确保 secrets 不进入明文设置、项目文件、日志或 Git。

---

## 5. 当前能力域

### 5.1 Session OS

- Note Session（`kind = .note`）：笔记是普通 chat session 的一种，通过 `kind` flag 与普通会话区分。
- 首条消息发送前，composer 进入全屏模式，并显示 Markdown 格式工具栏。
- 笔记模式禁用附件 paperclip 按钮，但允许图片插入。
- 文本文件可以拖入 composer，并把内容直接提取到输入区。
- 第一条消息发送时，会注入系统笔记指令，引导 LLM 总结、识别领域、映射关系并提出扩展方向。
- 首次回复后，session 回到普通聊天模式。
- 笔记会话在 session list 中显示“📝 笔记”徽标；kind tag 是系统保护字段，不允许用户编辑。
- 支持 session list、active state、软删除、run/event/audit 持久化。
- 支持 session-local workspace roots 和 primary root。
- 支持 per-session model override。
- JSONL records 支持 best-effort recovery。
- Browser state 和 approvals 保存在 Session Capsule 内。

### 5.2 本地工具与工作区策略

- 每个 session 有 primary root，也可以有额外 allowed roots。
- App Support 内有隐藏 root，用于 Connor 配置、技能和数据源。
- 文件/shell 操作必须先通过 Connor policy checks 才能执行。

### 5.3 原生模型提供方

- OpenAI Responses-native path。
- OpenAI-compatible Chat Completions fallback。
- Anthropic Messages-native path。
- DeepSeek / MiMo / GitHub Copilot / local-model 设置界面。
- 流式 typed provider events。
- 在模型支持时处理 function/tool continuation、reasoning metadata、health checks 和 per-connection settings。
- Provider 不拥有 Connor session state、工具执行、审批、审计或 memory projection gates。

### 5.4 Agent 运行时约定

每个用户任务应按以下顺序建立上下文：

1. 获取当前时间。
2. 在相关时检索内部上下文和当前用户画像。
3. 当任务依赖新鲜事实或外部信息时，搜索/抓取当前网页信息。
4. 考虑已安装技能。
5. 再决定回答、计划、编辑、调试、研究或提出澄清问题。

System prompt 故意保持最小：只注入上下文检索和用户画像工具。Memory OS 写工具不注入 system prompt；LLM 需要时通过普通 tool definition 访问。

### 5.5 MCP Source Platform

- Source registry 和 runtime repository。
- HTTP 与 stdio transport。
- Tool discovery 和 definition-change checks。
- Credential materialization 不允许 query-string secrets。
- Readiness 和 release-gate checks。

### 5.6 Attachment OS

- 附件 local-first 导入 Session Capsule。
- 支持 text/code/markdown/json/csv/xml/yaml/log/image/document allowlist。
- 对可选择文本的 PDF 使用 PDFKit extraction。
- Office/iWork/presentation/spreadsheet extraction 通过 sidecar best-effort paths。
- 支持 Quick Look / PDFKit native preview。

### 5.7 Browser Workspace

- 浏览器 tab 和 state 绑定到 session。
- WebKit browsing surface。
- 支持 history、bookmarks、selection/page prompt folding 和 shortcut resolution。

### 5.8 Mail / RSS / 人际关系 / Calendar

- 原生数据源 domain 和 app-support repositories。
- Mail draft/send governance：AI 可以创建草稿并请求发送；真实 SMTP 发送必须在同一个 run 中获得人工批准。
- Mail approval integrity：approval payload 保存 envelope hash；如果草稿在审批后发生变化，SMTP send 会被阻止。
- Sent-message closure：sent cache、audit、receipt、index writeback，以及可选 outbound Memory OS evidence。
- Governed outbound attachments：multipart composer support、filename injection checks 和 descriptor-only sent cache metadata。
- RSS registry/cache/read-state 边界。
- 人际关系与 Calendar adapter seams。
- 人际关系 domain 包含 `PersonProfile`、人物档案编辑、结构化 `PersonRelationship` 记录、关系展示，以及 `@` 人物提及解析。
- `ContactID`、`AgentContactRuntime`、`ContactsReadTool`、`ContactsWriteTool`、`readContacts`、`mutateContacts` 等 legacy/internal names 是兼容/API/权限命名。除非特指 Apple Contacts 集成或既有权限标识，不要把它们作为用户侧产品概念使用。
- Native Source Indexed Retrieval 支持 time-aware search filters。
- Calendar search 默认应使用 event interval overlap。
- Calendar detail reads 会作为 memory evidence 捕获；只读 title 的查询不会。

### 5.9 Skills、Tasks 与 Automation

- Skill package scanning、lifecycle 和 prompt augmentation。
- Task origins：`system`、`user`、`ai`。
- Trigger modes：`scheduled`、`eventTriggered`。
- 当前 user/AI templates：
  - 当某个 session 到达特定 status 时，向该 session 发送消息。
  - 在指定时间或 recurrence 创建 session 并发送消息。
- AI task tools：
  - `tasks_list`
  - `tasks_create_scheduled_session_message`
  - `tasks_create_session_status_message`
- System tasks 包括 Memory OS daily sweeps、10 分钟 Mail/Calendar refresh 和 per-source RSS refresh。
- missed recurring schedules 会补跑一次，然后推进到下一个未来 anchor。

---

## 6. Memory OS

Memory OS 是 Connor 的后台认知基础设施。它**不是**图谱编辑器、dashboard 或直接 LLM-write surface。

完整独立说明见 [MemoryOS_Architecture_and_Usage.md](MemoryOS_Architecture_and_Usage.md)。

### 6.1 层级架构

| Layer | 名称 | 职责 | 可变性 | 数据模型 |
|-------|------|------|--------|----------|
| **L0** | Provenance Vault | 原始证据对象和 span | **不可变** | `MemoryOSProvenanceObject`, `MemoryOSProvenanceSpan` |
| **L1** | Cache Buffer | 累积事件直到阈值，触发 L2/L3/L4 统一更新 | 已处理事件在 accepted projection 后删除；L0 保留证据 | `MemoryOSCaptureEvent`, `MemoryOSQueueItem` |
| **L2** | Operational Memory | 从验证证据中提取的实体中心工作记忆 | append-only statements | `MemoryOSNode`, `MemoryOSStatement` |
| **L3** | Knowledge Layer | 可复用理论、主张、框架、模式、标准、SOP、决策基础 | LLM 可直接写入 | `MemoryOSBelief` |
| **L4** | Stable Entity / Concept | 人、项目、组织、工作对象和概念的稳定锚点 | upsert + time-versioning | `MemoryOSEntity`, `MemoryOSEntityStatement` |

L4 使用受控实体类型词汇表（`MemoryOSEntityType`）；不支持的 LLM 原始标签会规范化为 `unknown`，而不是临时扩展 schema。

读取语义：**query-time current view derivation**。历史语义记录 append-only；当前性通过 newer validAt → newer committedAt → deterministic id 推导。

### 6.2 LLM 工具接口

LLM-facing Memory OS tools 注册在 `AppMemoryOSAgentTools.swift`。

读取工具包括：

- `memory_os_context`
- `memory_os_search`
- `memory_os_read_record`
- `memory_os_read_provenance`
- `memory_os_get_current_user_profile`
- `memory_os_l2_find_entities`
- `memory_os_l2_find_statements`
- `memory_os_l3_expand_belief`
- `memory_os_l3_list_domains`
- `memory_os_l4_find_entity`
- `memory_os_l4_neighbors`
- `memory_os_l4_instances`
- `memory_os_expand_l4`

写入工具包括：

- `memory_os_l2_update_entities`
- `memory_os_update_current_user_profile`
- `memory_os_l3_update_beliefs`
- `memory_os_l4_update_entities`

### 6.3 写入路径规则

- 双写路径：
  - LLM 在实时对话中通过工具直接写入 L2/L3/L4。
  - L1 cache buffer 累积事件，并在达到阈值后触发后台 unified projection。
- L1 cache 生命周期：
  - 事件从所有来源累积。
  - 达到阈值后触发 batch projection。
  - LLM 生成 structured artifact。
  - artifact 经过验证。
  - accepted projection 写入 L2/L3/L4。
  - 已处理 L1 events 被物理删除；L0 保留永久证据。
- 仅凭高置信度不会把 L2 facts 自动晋升到 L3。
- L4 会把 LLM 原始 entity type labels 规范化为受控词汇；不支持的标签变成 `unknown`。
- L4 relation validation 保留结构性检查：subject/object 是否存在、predicate 是否已知、拒绝 self-loop、endpoint type sanity。
- L4 expansion scoring 使用 predicate weight 和 graph depth decay，而不是 LLM 提供的 confidence。
- 历史语义记录 append-only；当前性由 query/current-view logic 推导。
- L2 statements 不要求 evidence span IDs；L1→L2 prompt 强调 fact-first extraction、entity names 和 relation types。

### 6.4 检索与上下文系统

Tool result delivery contract：

- Memory OS 读取工具把 LLM 实际可见的数据放在 `contentText`。
- `contentJSON` 保留完整结构化 payload，供 UI、debug 或程序消费者使用。
- `AgentToolResultGate.gatedContent()` 会在 `contentText` 非空时优先选择它。
- 工具不能假设 `contentJSON` 会被 LLM 看到。

Context building pipeline：

1. Multi-layer retrieval 从 L0–L4 收集相关 records。
2. Context builder 组装 blocks、entity cards、relation cards 和 evidence snippets。
3. 按配置预算进行裁剪。
4. 渲染为 `MemoryOSContextPackage`。

`MemoryOSContextPackage` 包含 executive summary、context text、blocks、entity cards、relation cards、evidence cards、diagnostics、raw retrieval trace、suggested next actions、budget report 和 quality signals。

### 6.5 ObserveLog

`ObserveLog.swift` 是轻量短期 buffer，用于保存可能值得吸收到 Memory OS 的观察。

- Kinds：`operation`、`tool_event`、`insight`、`fragment`、`observation`、`candidate_fact`、`decision_hint`、`user_preference`。
- Sources：`user`、`agent`、`tool`、`import`、`search`、`system`。
- Statuses：`active`、`promoted`、`dismissed`、`expired`。
- Retention：默认 30 天。
- Expiring-soon window：过期前 3 天。
- System task：每日清理 expired entries。
- Promotion path：entry 可以通过 `promoted(toNodeID:)` 晋升到 Memory OS node。

### 6.6 后台管线

触发条件（`MemoryOSL1ProcessingTriggerPolicy`）：

- pending capture events ≥ 100（`pendingCountThreshold`），或
- 最老 pending event age ≥ 24h（`pendingAgeThreshold`），或
- 通过 CLI 手动触发。

Job types（`MemoryOSBackgroundJobKind`）：

- `memory.l1.unified_projection`：聚合 pending L1 captures，并把 operational facts 投影到 L2，把 stable entity/concept facts 投影到 L4。
- `memory.l1.synthesize_knowledge`：从 L2 candidates 合成 L3 beliefs。

Execution tracking 使用 `MemoryOSBackgroundRunDomain.swift`：记录每个 run 的完整 message/tool-call history，支持 idempotency keys、最多 3 次 retry 和 dead-letter queue。

---

## 7. Search Kernel

Rust/Tantivy 嵌入式搜索内核位于 `SearchKernel/`，通过进程内 C ABI sidecar 编译和调用。它不是 server、daemon 或 HTTP service。

职责：

- 通过 Jieba/CJK tokenization 做中文/全文候选检索。
- 维护 Tantivy index schema 和 query execution。
- 为 Swift 提供进程内 C ABI。

非职责，这些由 Swift/SQLite Graph Retrieval Kernel 负责：

- L1/L2/L3/L4 graph traversal。
- Evidence trace。
- Instance enumeration。
- Timeline aggregation。

构建脚本：

- `Scripts/package-search-kernel.sh`：编译并打包 Rust sidecar。
- `Scripts/verify-memory-os-release.sh`：验证 Memory OS release readiness。

---

## 8. UI 指南

Connor 是原生 macOS app。

1. 优先使用 SwiftUI/AppKit/macOS-native 组件，而不是自定义 web UI。
2. 纯图标按钮需要可见 label 或 `.accessibilityLabel(...)`；必要时添加 `.help(...)`。
3. `NSViewRepresentable` / WebKit / PDFKit bridges 应保留平台 accessibility semantics。
4. 避免 sidebar、detail 和 settings navigation 出现重复 source of truth。
5. 添加临时颜色或尺寸前，优先使用 `AgentChatDesignSystem` / `AppShellDesignSystem` 中已有 design tokens。
6. Chat scrolling、pagination、unread markers 和 date sections 应留在 commercial Chat Viewport infrastructure 中；修改前先看 `Sources/ConnorGraphAgentMac/ChatViewport/`。
7. 避免 nested navigation titles 泄漏到 macOS window/menu state。
8. destructive 或 governance actions 必须打开 review surfaces；快捷键不得绕过 Connor policy/review gates。

用户可见文案应使用“康纳同学”的语气：温暖、准确、本地优先、行动导向。避免在终端用户界面出现泛泛的 `Something went wrong`、`No data` 或只有 raw error code 的文案。

---

## 9. 开发命令

从仓库根目录运行：

```bash
swift build
swift test
swift test --filter Browser
swift run connor --help
```

Search Kernel：

```bash
cd SearchKernel
cargo build
```

诊断命令：

```bash
git status --short
swift --version
find Sources Tests -name '*.swift' | wc -l
```

---

## 10. 代码质量检查清单

在声称修改完成前：

- 优先运行最小相关测试；可行时在最终交付前运行完整 `swift test`。
- Provider、sidecar 和 source adapters 必须位于 Connor 自有 policy 和 audit 边界之后。
- 凭证不得进入 JSON、prompt context、audit payload、README examples 或 source cache records。
- Memory OS 写入必须经过 provenance capture、artifact validation、audit logging 和 projection gates。
- 附件 source of truth 必须保留在 Session Capsule / Attachment Store。
- 原生数据源发生变更后，要更新或显式 invalidation native source search indexes。
- Mail/RSS/Calendar search results 必须保留 temporal metadata。
- 邮件发送绝不能信任模型提供的 approval flags；只有 `AgentToolExecutionContext.approvedCapabilities(.sendMail)` 中的人工审批才能授权 SMTP send。
- 纯图标控件需要添加 accessibility labels。
- 优先使用 structured errors，避免 force unwraps 或 force casts。
- L4 entity type labels 必须经过 `MemoryOSEntityType.normalizeRawType()`；不要把 LLM 原始标签直接传给 storage。
- L2 entity operations 必须经过 `MemoryOSL2EntityMemoryService`；不要绕过 name-splitting、dedup 或 upsert 逻辑。
- README 应保持简洁且面向用户；架构细节、设计说明和 changelog 放到本文件、专门设计文档或 issue 中。

---

## 11. 暂缓事项 / 非目标

- 远程 daemon 或云同步。
- 公开 API server。
- 团队/多用户权限模型。
- 完整 OAuth server ownership。
- CLI/API 直接写图谱。
- 外部 MCP/source 持有 Connor 产品状态。
- Provider-native file API 作为 source of truth。
- 扫描版 PDF OCR。
- 完整 XLSX/PPT 结构化抽取模型。
- 企业审计 mirror。
- 绕过用户干预的 CAPTCHA/login/security flows 浏览器自动化。

---

## 12. License

See [LICENSE](LICENSE).
