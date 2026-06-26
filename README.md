# Connor Graph Agent Mac

文档更新时间：2026-06-24 11:21 GMT+8  
当前文档基线：`remove-browser-media-transcription` 之后的当前工作树；README 只记录当前真实架构、配置和开发约束，不作为历史 changelog。过旧 Graph Memory 主链路已切换为商用稳定版 **Connor Memory OS L0-L4**；旧 SQLite temporal graph kernel 仅作为 L2/L4 底层存储 / retrieval adapter 保留。

Connor Graph Agent Mac 是一个 Swift / SwiftUI macOS 应用和 SwiftPM package。它的目标不是做“图谱编辑器”或“LLM SDK 外壳”，而是构建一个本地优先的 **memory-os-native Agent OS**：以 Session OS、Policy Engine、Memory OS、Source/MCP Platform、Native UI、Task Management Stack 和 Attachment Store 共同组成可治理的本地智能工作台。

核心判断：**记忆系统是后台认知基础设施，不是普通用户的前台图谱编辑器。** 普通用户面对的是会话、数据源、技能、自动化、浏览器、附件、任务和设置；Memory OS 在后台提供连续性、精确性、可追溯性、证据化工作记忆、可复用知识层和稳定实体/概念图谱。

---

## 1. Product Boundaries

Connor 当前坚持以下主权边界：

- **Session sovereignty belongs to Connor Session OS**：会话、run、journal、pending approval、branch、restore snapshot 和 Session Capsule 由 Connor 持久化与恢复。
- **Permission sovereignty belongs to Connor Policy Engine**：OpenAI / Anthropic 模型提供方、MCP server、local tools 和 native runtimes 都不能绕过 Connor 审批、审计和执行门禁。
- **Memory sovereignty belongs to Connor Memory OS**：LLM 不直接写 L2/L3/L4；所有记忆写入必须经过 L0 provenance、L1 capture/queue、processing artifact、schema/evidence validators、temporal current-view derivation 与 SQLite Memory OS repository。旧 Graph Memory 主链路不再作为商用架构保留；只移植 SQLite temporal graph kernel 的存储能力到 L2/L4。Memory OS 是隐藏后台基础设施：主侧边栏、detail pane 和 agent tool registry 不暴露 `Memory OS` dashboard / `memory_os_dashboard_summary`。
- **Source sovereignty belongs to Connor Source Platform**：MCP servers 是能力提供者，不拥有 Connor source registry、permission policy、audit、readiness state 或 graph ingestion policy。
- **UI sovereignty belongs to Swift Native Shell**：不引入 Electron/Web UI，不 fork Craft UI。文件预览、设置、菜单、快捷键、选择器等优先使用 macOS / SwiftUI / AppKit 原生语义。
- **Task sovereignty belongs to Connor Task Management Stack**：任务栈负责统一生命周期、运行历史、恢复意图和本地 CLI/API 管理面；不承载具体 runtime 实现，也不承担审批 gate。
- **Attachment sovereignty belongs to Connor Session OS / Attachment Store**：用户文件先进入本地 Session Capsule；原文件、manifest、派生抽取文本、message refs 和治理证据由 Connor 管理。
- **Mail/RSS/Contacts/Calendar sovereignty belongs to Connor native runtimes**：账号、凭据边界、同步游标、source cache、草稿/读取状态、审计和 Memory OS evidence policy 由 Connor 拥有。

明确不做：

```text
公网 API
远程 daemon / cloud sync
OAuth server / team auth / multi-user permissions
Craft UI fork
Electron/Web UI
Craft-style multi-workspace
CLI/API direct graph write
MCP server owning product state
External model provider owning Connor session state
Direct LLM access to IMAP / SMTP / OAuth / Contacts credentials
Unapproved email sending
Auto-projecting external-source facts into Memory OS truth records without validation
Executing feed HTML JavaScript or auto-loading remote tracking resources
```

---

## 2. Package Information

```text
Package name: ConnorGraphAgentMac
Swift tools version: 6.0
Platform: macOS 14+
External SwiftPM package dependencies: none
Explicit linker settings: sqlite3, Security, EventKit, Contacts, WebKit, AVFoundation, Speech, CoreLocation
Source-level Apple framework imports include: PDFKit and QuickLookUI for attachment preview/extraction surfaces
```

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
- connor-graph-agent-mac
- connor
```

Main source targets：

```text
Sources/ConnorGraphCore        Domain models and governance primitives
Sources/ConnorGraphMemory      Memory OS ingestion, processing, validation, projection, knowledge/entity services
Sources/ConnorGraphStore       SQLite Memory OS, session and audit persistence
Sources/ConnorGraphSearch      Hybrid graph retrieval and evaluation
Sources/ConnorGraphAgent       Agent loop, tools, model providers, policy boundary
Sources/ConnorGraphAppSupport  App services, repositories, native runtimes
Sources/ConnorGraphAgentMac    SwiftUI/AppKit macOS application shell
Sources/ConnorCLI              Local-only CLI control surface
```

Test targets cover all major modules, including Agent loop, Memory OS / temporal graph kernel, Store, Search, AppSupport, UI presentation policies, browser, attachments, mail/RSS, skills, tasks, and settings.

---

## 3. Architecture Overview

```text
SwiftUI Native Shell
  ↓
ConnorGraphAppSupport
  ↓
Session OS / Source Platform / Skill Runtime / Task Surface / Readiness Gate
  ↓
ConnorGraphAgent + Native Model Providers（OpenAI Responses / Anthropic Messages）
  ↓
Memory OS Runtime Contract
  ↓
L0 Provenance + L1 Capture Queue + L2 Operational Facts + L3 Knowledge Records + L4 Stable Entities / Concepts
```

### 3.1 ConnorGraphCore

Core domain target. It contains stable data structures and enums for：

- Memory OS L0-L4 domain models：provenance, capture, operational fact statements, knowledge records, stable entities/concepts, health and validation
- Temporal entity kernel primitives migrated into Memory OS semantics
- Session OS state and attention models
- Permission and policy domain
- Attachment domain
- Mail/RSS/Calendar/Contacts source domains
- Skill, task, product registry and automation domains

### 3.2 ConnorGraphMemory

Memory OS service layer. It is responsible for：

- Pre-ingestion filtering and L0/L1 ingestion decisions
- Adaptive time block building and processing preparation
- Statement, evidence and knowledge validators
- L2 fact projection service
- L3 knowledge promotion policy and synthesis boundary
- L4 entity/concept disambiguation and archive boundary
- Queue recovery and production processing policy

### 3.3 ConnorGraphStore

SQLite-backed persistence layer. It owns：

- `SQLiteMemoryOSStore` production schema, PRAGMA configuration, health report and FTS tables
- L0 provenance vault repositories
- L1 capture ledger and durable processing queue repositories
- L2 operational memory repositories
- L3 knowledge repositories（currently persisted through the compatible `memory_l3_beliefs` tables）
- L4 stable entity repositories and temporal entity kernel adapter
- Legacy importer for existing `graph_entities`, `graph_statements` and `graph_episodes_v3`
- Agent session/run/event/audit persistence

### 3.4 ConnorGraphSearch

Retrieval layer. It provides：

- Graph search query contracts
- Hybrid search service abstractions
- Retrieval evaluation cases and reports
- Embedding provider abstractions

### 3.5 ConnorGraphAgent

Agent runtime layer. It provides：

- Agent loop orchestration
- Streaming model provider abstraction
- OpenAI-compatible / Anthropic-compatible providers with streaming agent completion paths and explicit LLM request timeouts
- Tool registration, tool execution and tool result gating
- Local workspace tools and policy checks
- Mail/RSS/Calendar/Contacts/scientific compute tool boundaries
- Prompt assembly, budget estimation, summarization and context compression contracts

### 3.6 ConnorGraphAppSupport

Application service layer. It contains repositories, adapters and native runtime bridges for：

- Session Capsule persistence
- NativeSessionManager
- LLM settings, OAuth and credential storage
- MCP source registry/runtime/transport
- Attachment import, extraction, preview and commercial services
- Mail/RSS/Contacts/Calendar native runtimes
- Browser bookmarks/history/context builders
- Skills, automation, task management and product readiness

### 3.7 ConnorGraphAgentMac

SwiftUI macOS application target. It owns：

- Native app shell and sidebar/detail layout
- Chat transcript, composer, tool details and approval surfaces
- Browser workspace with WebKit bridge
- Attachment preview and inspector UI
- Settings center
- Mail/RSS/Calendar/Contacts native surfaces

Memory OS 不属于 `ConnorGraphAgentMac` 的用户可见 navigation surface。SwiftUI shell 可以触发后台 ingestion、pipeline scheduling 和 agent tool execution，但不拥有 Memory OS dashboard、layer count panel 或 provenance browser。

`AppViewModel` remains the main in-target state object for the macOS app. UI files are split by feature area, but product state ownership stays in Connor-owned services and repositories.

### 3.8 ConnorCLI

Local-only programmable control plane. It does not introduce a remote daemon and must respect Connor-owned repositories and policy boundaries.

---

## 4. Runtime Storage Layout

Runtime paths are resolved by `AppStoragePaths` under the user Application Support `Connor` directory. Connor currently uses a single local Home / Runtime Root.

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

Sidecar-related directories are only materialized when a governed runtime explicitly owns them.
```

Session Capsule layout：

```text
sessions/{sessionID}/
├── manifest.json
├── state/
│   ├── session-state.json
│   └── records.jsonl
├── browser/
│   └── browser-state.json
├── plans/
├── data/
├── attachments/
│   ├── attachment-manifest.jsonl
│   ├── extraction-jobs.jsonl
│   ├── audit.jsonl
│   ├── purge-ledger.jsonl
│   ├── evidence-candidates.jsonl
│   ├── index/
│   ├── provider-cache/
│   └── {attachmentID}/
│       ├── manifest.json
│       ├── original/
│       ├── derivatives/
│       └── lineage/
├── exports/
└── logs/
```

Key state files：

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

内置系统任务会在启动时自动补齐到 `task-definitions.json`。当前 protected system tasks 包括：

```text
system.memory-os.plan-l1-unified-projection                memory_os.pipeline:default.plan_l1_unified_projection_jobs     interval 86400s daily sweep
system.memory-os.plan-l2-to-knowledge         memory_os.pipeline:default.plan_l2_to_knowledge_jobs interval 86400s daily sweep
system.mail.check-every-10-minutes            source.runtime:mail.refresh
system.calendar.check-every-10-minutes        source.runtime:calendar.refresh
system.rss.source.{rssSourceID}.refresh       source.runtime:rss.refresh(sourceInstanceID={rssSourceID})
```

RSS 不再存在全局 source-type refresh task；开发期本地遗留的无 `sourceInstanceID` RSS refresh task 会在 reconcile 时从 task definitions 中物理清除。

API keys and provider credentials must not be stored in JSON settings files. They belong in local credential stores / Keychain-backed repositories.

---

## 5. Current Capability Areas

### 5.1 Session OS

- Session list, active session state and soft deletion
- Session-local workspace roots and primary root
- Session-local model override
- JSONL records with best-effort recovery from bad lines
- Browser state under Session Capsule
- Pending approval and run/event persistence

### 5.2 Workspace and Local Tools

- Session-scoped primary root and additional allowed roots
- Hidden app-support root for Connor configuration/skills/source management
- Local workspace policy checks before file/shell operations
- Connor native tools can use session-scoped primary roots plus additional allowed roots; model providers do not own workspace cwd policy

### 5.3 Native Model Providers

- OpenAI Responses-native provider path for official OpenAI `/v1/responses`
- OpenAI-compatible Chat Completions path remains available for compatible endpoints that do not support Responses
- Anthropic / Claude native Messages API provider path
- OpenAI Responses and Anthropic Messages streaming use typed provider events through Connor's model-provider abstraction
- OpenAI Responses supports typed output items, function_call / function_call_output continuation, `store: false`, reasoning effort, and typed SSE events
- Anthropic Messages supports tool_use / tool_result blocks, thinking metadata, beta headers, and fine-grained tool input streaming
- Non-streaming completion and provider health-check paths remain available as fallbacks
- Per-connection settings and per-session model override
- Provider health checks and credential boundary
- Connor owns sessions, tool execution, pending approvals, audit events and Memory OS projection gates; model providers never own Connor product state

#### 5.3.1 Agent Prompt Runtime Contract

Connor's default system prompt includes a task bootstrap workflow for every user task:

1. Call `get_current_time` first and use that result as the only current date/time anchor for the turn.
2. Retrieve internal context before external context: prefer `memory_os_get_current_user_profile`, then search relevant Memory OS L0/L1/L2/L3/L4 records with `memory_os_search`, deepening with `memory_os_read_record`, `memory_os_expand_l4`, or `memory_os_read_provenance` when evidence or identity matters.
3. Search current web information with `web_search` when external grounding, freshness, documentation, facts, or best practices could affect the answer, and use `web_fetch` to read original pages before relying on snippets.
4. Consider installed Connor skills before choosing the final strategy; when a request maps to a skill domain, load it through `connor_skill_activate`. Hidden built-in skills are used silently and are not exposed to users.
5. Only after current time, internal memory, external evidence, and relevant skill instructions have been considered should the agent decide whether to answer, plan, edit, debug, research, or ask a clarification.

### 5.4 MCP Source Platform

- Source registry and runtime repository
- HTTP and stdio transport support
- Tool discovery, definition change checks and governance bridge
- Credential materialization without exposing secrets to query strings
- Source readiness and commercial release-gate checks

### 5.5 Attachment OS

- Local-first attachment import into Session Capsule
- Allowlisted text/code/markdown/json/csv/xml/yaml/log/image/document formats
- PDF selectable text extraction through PDFKit
- Office/iWork/presentation/spreadsheet extraction through command sidecar best-effort paths
- Quick Look / PDFKit based native preview path
- Omitted attachment summaries for pending/failed/unsupported/oversize files

### 5.6 Native Browser Workspace

- Session-bound browser tabs and browser state
- WebKit-backed browsing surface
- Browser history and bookmarks
- Search/fetch assisted browser task planning
- Selection/page prompt folding for Agent questions
- Local keyboard shortcut resolver for browser-specific actions

### 5.7 Native Mail / RSS / Contacts / Calendar

- Native source domains and app-support repositories
- Presentation models for settings and browsing surfaces
- Mail draft/send governance boundaries：AI 可创建持久草稿、请求发送，但真实 SMTP 发送必须通过 `sendMail` 权限审批；用户点击 Allow 后同一个 Agent run 才会 resume 并发送。
- Native Mail send pipeline：`mail_create_draft` 写入 Connor-owned draft store；`mail_send_draft` 生成邮件审批 payload（收件人、主题、正文预览、envelope hash），通过 Composer/permission surface 审批后由 native runtime 从 Keychain-backed credential boundary 读取凭据、构造 RFC 5322/MIME 消息并调用 SMTP client。
- Sent-message closure：发送成功会记录 send attempt/receipt/audit，并写入本地 Sent mailbox/source cache，使 `mail_search_messages` 可检索已发送邮件；失败会保留 failed attempt 和 draft error。
- RSS feed registry/cache/read-state boundaries
- Contacts and Calendar system adapter seams
- Credential and permission boundaries separate from LLM/provider access
- Native Source Indexed Retrieval for Mail/RSS/Calendar through a unified time-aware search domain and service
- Incremental index maintenance on source cache mutations such as mail message save/read-state updates and RSS item upsert/state/delete paths
- Time-aware search filters using structured `startDate` / `endDate` / `timePreset` arguments rather than vague text-only freshness assumptions
- Search results preserve source time information: Mail sent/received time, RSS published/fetched time, and Calendar event start/end/timezone/all-day fields
- Agent-callable search remains concise: `mail_search_messages`, `rss_search_items`, and `calendar_read` with operation `search_events`; duplicate semantic search tools are intentionally avoided

### 5.8 Memory OS / Temporal Graph Kernel

Connor Memory OS is the production memory boundary for the app. It is not a graph editor, not a user-facing dashboard, and not a direct LLM-write surface. The system uses a five-layer architecture with a strict semantic split:

- **L0 Provenance Vault** stores raw evidence objects and evidence spans.
- **L1 Capture Ledger / Processing Queue** records durable capture events and operational queue state.
- **L2 Operational Memory** stores append-only temporal **facts** extracted from validated evidence: preferences, project state, observed events, working context and other operational statements. High confidence alone never promotes an L2 fact to L3.
- **L3 Knowledge Layer** stores reusable knowledge records: theories, claims, frameworks, patterns, standards, processes, SOPs and decision bases. L3 is not a high-confidence duplicate of L2; it is gated by knowledge promotion policy.
- **L4 Stable Entity / Concept Layer** stores stable anchors for people, projects, organizations, work objects and concept entities such as theories, parameters, frameworks, standards, processes and metrics. L3 knowledge records link to L4 concepts and relations.

L2/L3/L4 records do not use semantic lifecycle states such as confirmed, conflicted, deprecated, superseded, or user-confirmed. Historical semantic records are never mutated to express currentness; new evidence appends new temporal records, and the current memory surface is derived by query/current-view logic using temporal ordering, confidence, provenance and evidence joins. Ambiguity is represented as diagnostic output, not as a persisted semantic conflict state.

The write path is deliberately controlled: chat messages, browser selections and native-session evidence enter through `AppMemoryOSFacade`, are preserved as L0/L1 records, and only validated structured artifacts may project into L2/L3/L4. LLMs may propose structured artifacts, but the repository only accepts them after durable artifact preservation, schema validation, evidence validation, audit logging and transactional projection. `MemoryOSL1UnifiedProjectionOutput` projects evidence-backed operational facts into L2 and stable entity facts into L4. `MemoryOSKnowledgeExtractionOutput` projects accepted knowledge candidates into L3 and concept entities/relations into L4. Rejected artifacts remain operational validation outcomes and never become memory truth records.

The background pipeline has two AI job types. `memory.l1.unified_projection` is planned by `MemoryOSL1UnifiedProjectionJobPlanner`: pending L1 captures are grouped by threshold/token policy, wrapped as an ordered JSON `l1_capture_events` packet, and queued to produce `MemoryOSL1UnifiedProjectionOutput`. L1 unified projection planning is event-driven when pending L1 captures reach 100, and the daily system sweep also triggers it when the oldest pending L1 capture is at least 24 hours old. `memory.l2.synthesize_knowledge` is planned by `MemoryOSL2ToKnowledgeJobPlanner`: pending L2 statement processing states are grouped into ordered JSON `l2_statements` synthesis packets, wrapped with the four-filter knowledge prompt, and queued to produce `MemoryOSKnowledgeExtractionOutput`. L2→Knowledge planning is event-driven when pending knowledge-synthesis statements reach 100, and the daily system sweep also triggers it when the oldest pending statement is at least 24 hours old. `MemoryOSBackgroundJobWorker` and `AppMemoryOSFacade.runBackgroundAIQueueOnce(...)` execute those jobs through a `MemoryOSBackgroundModelExecutor`, then hand the returned artifact JSON to the existing validation/projection gate. Program code plans jobs and validates artifacts; the LLM does the semantic judgment in prompt space.

The background prompt contract is now explicit rather than a loose manifest. L1 unified projection prompts identify L0 as durable evidence, L1 as the active ordered buffer, and L2 as operational facts; they require chronological per-event extraction, noise rejection, duplicate consolidation, evidence refs, and conservative L3/L4 candidate creation only through the unified projection contract and promotion filters. L2→Knowledge prompts are conservative reviewers: most L2 facts should not become L3, high confidence alone is insufficient, all four filters must pass, and accepted knowledge candidates must include explicit `signal_quality`, `reuse_scope`, `novelty`, and `structurability` AI judgment fields.

Person memory follows a single Person model with role metadata. The current user is the human operating this Connor installation/session and is represented as a person with `person_role = current_user`; named collaborators, contacts, family members and other durable people use `person_role = other_person`. Current-user preferences, habits, goals, stable traits, knowledge background and communication preferences are L2 `profile_preference` facts by default. Other-person profile facts remain separate and must not be merged into the current user. Ordinary person facts do not become L3 knowledge unless they are abstracted into reusable principles, standards, processes, frameworks or decision bases.

L1 is an active memory sequence, not the durable source of truth. L0 keeps the raw provenance object/span. Therefore, after an accepted L1 unified projection, Connor physically deletes the processed `memory_l1_capture_events`. If the executor fails, the artifact is rejected, or the job dead-letters, L1 remains available for retry.

`SQLiteMemoryOSUnifiedRetrievalService` is the native retrieval surface for AI background jobs and agent tools. It searches L0/L1/L2/L3/L4 and returns layer-aware hits with evidence, provenance and entity refs. L4 supports `depth` expansion through `expandL4(entityID:depth:limit:)`, exposed to agents as `memory_os_expand_l4`. The general `memory_os_search` tool returns summaries first; hits are context, not truth. `memory_os_read_record` reads full L0/L1/L2/L3/L4 records after a search hit, and `memory_os_read_provenance` reads exact L0 provenance object/span content when raw evidence is required. Background model requests carry provider-agnostic tool descriptors for these tools; a future provider adapter may run a full tool-calling loop, while the current executor can still operate from the structured prompt packet. There is intentionally no `memory_os_dashboard_summary` agent tool; operational counts remain internal backend state exposed through `AppMemoryOSFacade.operationalSummary(...)` for tests, health checks and queue recovery logic, not for end-user UI.

L2 organization state is tracked outside the immutable fact row through `memory_l2_statement_processing_state`. This lets Connor select unorganized L2 facts for knowledge synthesis without overwriting historical statements. Improvements to L2 should append refined statements and connect them through metadata/projection state rather than mutating old facts in place.

Native source ingestion is normalized through `AppMemoryOSNativeSourceEventBridge`, which adapts Mail, Calendar, RSS, browser history and attachment text into `ingestSourceEvent(...)`. Capture ingestion immediately checks the L1 count threshold; accepted L1 unified projections immediately check the L2 pending-statement count threshold. Task scheduling reaches the pipeline through `memory_os.pipeline` targets such as `plan_l1_unified_projection_jobs` and `plan_l2_to_knowledge_jobs`, but those protected system tasks are daily age/fallback sweeps rather than 5-minute polling loops.

L3 promotion is governed by four knowledge filters:

| Filter | Question | Acceptance signal |
|---|---|---|
| Signal quality | Is this knowledge rather than noise? | Actionable insight, framework, pattern, standard, process or decision basis |
| Reuse scope | Will this be reused? | General reuse, or reuse for a work object / internal process |
| Novelty | Is it new or a material addition? | New record, or significant enrichment of an existing record |
| Structurability | Can it live in the right structure? | Maps to category, knowledge type, scope, domain, work object/person and L4 concepts |

Example boundary: “张三喜欢吃杨梅” is an L2 operational fact even at 0.99 confidence. It should not enter L3. A reusable economics claim such as “under specific constraints, supply-demand elasticity space varies with a parameter” can enter L3 as a knowledge record when it passes the four filters, and it should link to L4 concept entities such as “供需弹性” and the relevant parameter.

The old Graph Memory workflow has been removed from production architecture: staging buffers, distillation jobs, GraphExtraction traces, admission-hold queues, graph-write candidates, change logs and self-healing workflows are not retained as parallel systems. The retained SQLite temporal graph kernel is infrastructure only: it provides durable storage/search/indexing capabilities and temporal entity kernel adaptation for L2/L4, while Memory OS owns the semantic contract. Hybrid retrieval and retrieval evaluation remain available over retained graph/search infrastructure, but all product-facing memory ingestion, dashboard, background jobs and agent tools route through Memory OS.

### 5.9 Skills, Tasks and Automation

- Skill package scanning, lifecycle and invocation parsing
- Skill prompt augmentation
- Product OS automation legacy repositories remain for compatibility, but new background work is owned by Task Management Stack
- Three task origins：
  - `system`：Connor protected tasks，用户可查看、暂停和恢复，不可删除；当前包括 Memory OS L1 unified projection / L2→Knowledge 每日 age/fallback sweep 任务、10 分钟邮件刷新、10 分钟日历刷新，以及由每个 RSS source 的 `fetchPolicy.intervalMinutes` 派生出的 per-source RSS refresh tasks
  - `user`：用户创建的任务，可编辑/删除；当前受模板约束
  - `ai`：AI 通过受治理工具创建的任务，可被用户编辑/删除；当前受模板约束
- Two trigger modes：
  - `scheduled`：指定时间或周期触发，支持一次性、每日、每周、每月，以及系统 interval 任务
  - `eventTriggered`：事件触发；当前用户/AI 可创建的事件任务仅限 `session.status.changed`
- Current user/AI task templates：
  - 当某个会话状态变为特定状态后，向该会话的 AI 发送特定内容
  - 在某个特定时间，或每日/每周/每月周期，新建会话并向 AI 发送特定内容
- AI task tools：
  - `tasks_list`
  - `tasks_create_scheduled_session_message`
  - `tasks_create_session_status_message`
- Task runtime execution：`TaskSchedulerService` 计算 due tasks，`TaskSchedulerRunnerService` 记录 run history 并调用 `TaskTargetRunner`，真实分发到 Native Mail / Calendar / RSS runtimes 或 Session OS message flow。`source.runtime` refresh targets 现在通过 `SourceRefreshTaskRequest` 传递 `sourceKind`、`sourceInstanceID` 和 `runID`；RSS source-instance task 会只刷新对应 RSS source，而不是刷新所有 RSS sources。
- Source sync policy boundary：source config 是同步策略事实来源，TaskDefinition 是 materialized projection。RSS 当前由 `SourceRefreshTaskMaterializer` 根据 `RSSSource.fetchPolicy.intervalMinutes` 生成/更新 `system.rss.source.{rssSourceID}.refresh`；当 RSS source 删除后，对应 task definition 会被物理清除，避免开发阶段保留无效结构。
- Missed recurring schedule semantics：应用启动和 60 秒轮询都会扫描 due tasks；如果每日/每周/每月重复任务在应用未运行期间错过至少一次，Connor 下次启动/轮询时会立即补执行一次，并把 `nextRunAt` 推进到原始 `runAt` 锚点之后的下一个未来计划点；不会对错过的每一个周期批量补跑，避免会话消息或 source refresh 噪音。Source refresh 同步同样采用 catch up once 语义：恢复后运行一次以追平 source cursor，而不是按错过 interval 批量 replay。
- Session-scoped background task adapter remains for recoverable per-session runtime intents

---

## 6. UI and Accessibility Guidelines for This Codebase

Connor is a native macOS app. UI changes should follow these rules：

1. Prefer SwiftUI/AppKit/macOS-native components over custom web UI.
2. Pure icon buttons need either a visible label or `.accessibilityLabel(...)`; `.help(...)` should be added for toolbar-like controls where useful.
3. `NSViewRepresentable` / WebKit / PDFKit bridges should preserve platform accessibility semantics or expose explicit labels when the wrapped control does not.
4. Avoid duplicate sources of truth for sidebar selection, detail selection and settings navigation.
5. Use design-system tokens already present in `AgentChatDesignSystem` / `AppShellDesignSystem` instead of ad-hoc colors and dimensions where possible.
6. Keep chat scrolling, prepend pagination, unread markers and date sections inside the commercial Chat Viewport infrastructure; see `Docs/commercial-chat-viewport-architecture.md` before changing message list, jump-to-latest, pagination or future social-chat behavior.
7. Avoid nested navigation titles that can leak into macOS window/menu state.
7. Do not make destructive or governance actions one-key direct execution; shortcuts may open review surfaces, but execution must still go through Connor policy/review gates.

---

## 7. Development Commands

From the repository root：

```bash
swift test
swift test --filter Browser
swift build
swift run connor --help
```

Useful diagnostics：

```bash
git status --short
swift --version
find Sources Tests -name '*.swift' | wc -l
```

Current local scan baseline：

```text
branch: remove-browser-media-transcription
source files: 345 Swift files under Sources
test files: 254 Swift files under Tests
total: 599 Swift files
```

---

## 8. Code Quality Checklist

Before claiming a change is complete：

- Run the smallest relevant tests first.
- Run full `swift test` before final handoff.
- Keep provider/sidecar/source adapters behind Connor-owned policy and audit boundaries.
- Keep credentials out of JSON config files.
- Keep Memory OS writes behind provenance capture, artifact validation, audit logging and projection gates.
- Keep attachment source of truth in Session Capsule / Attachment Store.
- Any native source mutation must update, invalidate, or explicitly fallback around the Native Source Search index.
- Any Mail/RSS/Calendar search result must preserve temporal metadata; time-sensitive queries should use structured `timePreset` or `startDate`/`endDate` filters.
- Mail sending must never trust model-supplied `approved` flags. The only send authorization source is the human approval resolution carried by `AgentToolExecutionContext.approvedCapabilities(.sendMail)` after Composer/permission UI Allow.
- Mail credentials must never appear in tool JSON, prompt context, audit payloads, README examples, or source cache records; only native runtime credential stores may materialize secrets immediately before SMTP transport.
- Mail send readiness requires: registered native mail tools, persistent draft store, SMTP send adapter boundary, approval UI, send attempts/audit, and Sent cache/index writeback.
- Calendar time filtering should use event interval overlap by default so cross-day and all-day events are not omitted.
- Keep Agent tool names unique and avoid duplicate semantic search tools when an existing native source search tool covers the task.
- Add accessibility labels for pure icon controls.
- Prefer structured errors over force unwraps or force casts.
- Keep README as architecture documentation, not a chronological changelog.

---

## 9. Deferred / Non-goals

The following remain intentional non-goals or future extension points：

- Remote daemon or cloud sync
- Public API server
- Team/multi-user permission model
- Full OAuth server ownership
- Direct CLI/API graph writes
- External MCP/source owning Connor product state
- Provider-native file API as source of truth
- OCR for scanned PDFs
- Full XLSX/PPT structured extraction model
- Enterprise audit mirror
- Browser automation that bypasses user intervention for CAPTCHA/login/security flows

Future work should be added as focused design docs or tracked issues, not by expanding README into a running changelog.

---

## 10. License

See [LICENSE](LICENSE).
