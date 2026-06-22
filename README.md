# Connor Graph Agent Mac

文档更新时间：2026-06-22 21:58 GMT+8  
当前分支目标：将过旧 Graph Memory 主链路硬切换为商用稳定版 **Connor Memory OS L0-L4**；只移植旧 SQLite temporal graph kernel 的存储能力作为 L2/L4 底层 adapter，删除 staging / distillation / extraction / admission / candidate review / self-healing 等旧结构，避免长期技术债务。

Connor Graph Agent Mac 是一个 Swift / SwiftUI macOS 应用和 SwiftPM package。它的目标不是做“图谱编辑器”或“LLM SDK 外壳”，而是构建一个本地优先的 **memory-os-native Agent OS**：以 Session OS、Policy Engine、Memory OS、Source/MCP Platform、Native UI、Task Management Stack 和 Attachment Store 共同组成可治理的本地智能工作台。

核心判断：**记忆系统是后台认知基础设施，不是普通用户的前台图谱编辑器。** 普通用户面对的是会话、数据源、技能、自动化、浏览器、附件、任务和设置；Memory OS 在后台提供连续性、精确性、可追溯性、证据化工作记忆、可复用知识层和稳定实体/概念图谱。

---

## 1. Product Boundaries

Connor 当前坚持以下主权边界：

- **Session sovereignty belongs to Connor Session OS**：会话、run、journal、pending approval、branch、restore snapshot 和 Session Capsule 由 Connor 持久化与恢复。
- **Permission sovereignty belongs to Connor Policy Engine**：OpenAI / Anthropic 模型提供方、MCP server、local tools 和 native runtimes 都不能绕过 Connor 审批、审计和执行门禁。
- **Memory sovereignty belongs to Connor Memory OS**：LLM 不直接写 L2/L3/L4；所有记忆写入必须经过 L0 provenance、L1 capture/queue、processing artifact、schema/evidence validators、temporal current-view derivation 与 SQLite Memory OS repository。旧 Graph Memory 主链路不再作为商用架构保留；只移植 SQLite temporal graph kernel 的存储能力到 L2/L4。
- **Source sovereignty belongs to Connor Source Platform**：MCP servers 是能力提供者，不拥有 Connor source registry、permission policy、audit、readiness state 或 graph ingestion policy。
- **UI sovereignty belongs to Swift Native Shell**：不引入 Electron/Web UI，不 fork Craft UI。文件预览、设置、菜单、快捷键、选择器等优先使用 macOS / SwiftUI / AppKit 原生语义。
- **Task sovereignty belongs to Connor Task Management Stack**：任务栈负责统一生命周期、运行历史、恢复意图和本地 CLI/API 管理面；不承载具体 runtime 实现，也不承担审批 gate。浏览器媒体转写也是 `media.transcription.run` target，不建立第二套媒体专用全局队列。
- **Attachment sovereignty belongs to Connor Session OS / Attachment Store**：用户文件先进入本地 Session Capsule；原文件、manifest、派生抽取文本、message refs 和治理证据由 Connor 管理。媒体转写全文作为附件/derivative 写入 Session Capsule，不塞进 chat body。
- **Mail/RSS/Contacts/Calendar sovereignty belongs to Connor native runtimes**：账号、凭据边界、同步游标、source cache、草稿/读取状态、审计和 Graph evidence policy 由 Connor 拥有。

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
Auto-writing external-source facts into Graph Memory
Executing feed HTML JavaScript or auto-loading remote tracking resources
```

---

## 2. Package Information

```text
Package name: ConnorGraphAgentMac
Swift tools version: 6.0
Platform: macOS 14+
Current local toolchain used in this review: Apple Swift 6.3.2
System frameworks: sqlite3, Security, EventKit, Contacts, WebKit, PDFKit, QuickLookUI
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

Test targets cover all major modules, including Agent loop, Graph Memory, Store, Search, AppSupport, UI presentation policies, browser, attachments, mail/RSS, skills, tasks, and settings.

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

### 3.7 Browser Media Transcription Foundation

Connor 的内置浏览器媒体本地转写系统遵守“browser detects, task stack executes, attachment store owns output”的边界：

```text
WKWebView Browser Media Detection
  ↓
BrowserMediaSourceSnapshot
  ↓
MediaTranscriptionTaskCreationService
  ↓
Connor Task Management Stack target: media.transcription.run
  ↓
MediaTranscriptionTaskHandler + MediaRuntimeSupervisor
  ↓
Session-owned media job manifest / events / progress / diagnostics / checkpoints
  ↓
MediaTranscriptionAttachmentWriter
  ↓
Session Attachment Store + follow-up prompt
```

当前代码层已建立：

- `BrowserMediaTranscriptionDomain.swift`：job、state machine、runtime snapshot、progress、artifact refs；多段媒体选择会先拆成多个单源 snapshot，确保每个 `media.transcription.run` job 只对应一个媒体源。
- `MediaTranscriptionJobStore.swift`：`sessions/{sessionID}/data/media-jobs/{jobID}/` 下的 durable manifest、event log、progress、diagnostics 与 checkpoints。
- `MediaRuntimeSupervisor.swift`：Python / yt-dlp / FFmpeg / WhisperKit sidecar health snapshot；真实 runtime 必须通过 checksum、license manifest 与 Application Support sidecar 目录治理。
- `WhisperKitMediaLocalTranscriber.swift`：默认本地 ASR provider，使用 Argmax `WhisperKit` Swift SDK 加载 app-managed `openai_whisper-medium`（balanced/default）模型；媒体转写不使用 macOS Speech 作为默认路径。
- `MediaTranscriptionTaskHandler.swift`：复用现有 `TaskTargetRunner` 的 `media.transcription.run` 分支；不新增独立 queue。
- `TaskManagementUIPresentation.swift`：浏览器媒体转写属于可恢复后台任务，不进入系统定时任务列表；用户在会话 background task surface 中查看进度。
- `MediaTranscriptionAttachmentWriter.swift`：将 transcript/segments/diagnostics 写入 Session Attachment Store derivatives；完成后的 follow-up message 必须携带当前 job 最新 transcript attachment ref，让模型通过附件上下文读取全文，而不是只在 prompt 中写附件 ID。
- `BrowserWebViewRepresentable.swift`：注入媒体检测 JS，识别 `<video>` / `<audio>` / OpenGraph media，不 hook DRM、不抓 cookie、不绕过站点权限。

Runtime 合规边界：

- yt-dlp：采用受治理 Python source/wheelhouse 路线，不使用官方 PyInstaller binary 作为默认分发物；禁止 `--update`、`--exec`、任意 cookie、任意外部 downloader 和未确认 playlist 批量处理。
- FFmpeg：只允许 LGPL build；不得启用 GPL/nonfree parts；必须记录 configure flags、checksum、source offer / license notice。
- WhisperKit / SpeakerKit / models：必须记录 SDK 与模型 license、version、checksum；模型按需下载或受治理物化。
- Python runtime：只作为 yt-dlp sidecar 能力，不作为通用 Python 执行器暴露。

### 3.8 ConnorGraphAgentMac

SwiftUI macOS application target. It owns：

- Native app shell and sidebar/detail layout
- Chat transcript, composer, tool details and approval surfaces
- Browser workspace with WebKit bridge
- Attachment preview and inspector UI
- Settings center
- Mail/RSS/Calendar/Contacts native surfaces
- Memory OS dashboard, health and provenance surfaces

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
│   ├── exports/
│   ├── snapshots/
│   └── evaluations/
├── logs/
│   ├── audit/
│   └── runtime/
└── sidecars/
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

内置系统任务会在启动时自动补齐到 `task-definitions.json`。Mail / Calendar 当前仍保留 source-type level protected tasks；RSS 已迁移到 source-instance level materialized tasks：

```text
system.mail.check-every-10-minutes            source.runtime:mail.refresh
system.calendar.check-every-10-minutes        source.runtime:calendar.refresh
system.rss.source.{rssSourceID}.refresh       source.runtime:rss.refresh(sourceInstanceID={rssSourceID})
```

RSS 不再存在全局 source-type refresh task；开发期本地遗留的无 `sourceInstanceID` RSS refresh task 会在 reconcile 时从 task definitions 中物理清除。
labels/labels.json
statuses/statuses.json
graph/evaluations/retrieval-evaluation-cases.json
graph/evaluations/reports/*.json
```

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
- Connor owns sessions, tool execution, pending approvals, audit events and graph-memory writes; model providers never own Connor product state

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
- Mail draft/send governance boundaries
- RSS feed registry/cache/read-state boundaries
- Contacts and Calendar system adapter seams
- Credential and permission boundaries separate from LLM/provider access
- Native Source Indexed Retrieval for Mail/RSS/Calendar through a unified time-aware search domain and service
- Incremental index maintenance on source cache mutations such as mail message save/read-state updates and RSS item upsert/state/delete paths
- Time-aware search filters using structured `startDate` / `endDate` / `timePreset` arguments rather than vague text-only freshness assumptions
- Search results preserve source time information: Mail sent/received time, RSS published/fetched time, and Calendar event start/end/timezone/all-day fields
- Agent-callable search remains concise: `mail_search_messages`, `rss_search_items`, and `calendar_read` with operation `search_events`; duplicate semantic search tools are intentionally avoided

### 5.8 Memory OS / Temporal Graph Kernel

Connor Memory OS is the production memory boundary for the app. It is not a graph editor and it is not a direct LLM-write surface. The system uses a five-layer architecture with a strict semantic split:

- **L0 Provenance Vault** stores raw evidence objects and evidence spans.
- **L1 Capture Ledger / Processing Queue** records durable capture events and operational queue state.
- **L2 Operational Memory** stores append-only temporal **facts** extracted from validated evidence: preferences, project state, observed events, working context and other operational statements. High confidence alone never promotes an L2 fact to L3.
- **L3 Knowledge Layer** stores reusable knowledge records: theories, claims, frameworks, patterns, standards, processes, SOPs and decision bases. L3 is not a high-confidence duplicate of L2; it is gated by knowledge promotion policy.
- **L4 Stable Entity / Concept Layer** stores stable anchors for people, projects, organizations, work objects and concept entities such as theories, parameters, frameworks, standards, processes and metrics. L3 knowledge records link to L4 concepts and relations.

L2/L3/L4 records do not use semantic lifecycle states such as confirmed, conflicted, deprecated, superseded, or user-confirmed. Historical semantic records are never mutated to express currentness; new evidence appends new temporal records, and the current memory surface is derived by query/current-view logic using temporal ordering, confidence, provenance and evidence joins. Ambiguity is represented as diagnostic output, not as a persisted semantic conflict state.

The write path is deliberately controlled: chat messages, browser selections and native-session evidence enter through `AppMemoryOSFacade`, are preserved as L0/L1 records, and only validated structured artifacts may project into L2/L3/L4. LLMs may propose structured artifacts, but the repository only accepts them after durable artifact preservation, schema validation, evidence validation, audit logging and transactional projection. `GraphStructuredExtractionOutput` projects evidence-backed operational facts into L2 and stable entity facts into L4. `MemoryOSKnowledgeExtractionOutput` projects accepted knowledge candidates into L3 and concept entities/relations into L4. Rejected artifacts remain operational validation outcomes and never become memory truth records.

The background pipeline has two AI job types. `memory.l1.process_block_to_l2` is planned by `MemoryOSL1ToL2JobPlanner`: pending L1 captures are grouped by threshold/token policy, wrapped with a prompt contract, and queued to produce `GraphStructuredExtractionOutput`. `memory.l2.synthesize_knowledge` is planned by `MemoryOSL2ToKnowledgeJobPlanner`: pending L2 statement processing states are grouped into synthesis blocks, wrapped with the four-filter knowledge prompt, and queued to produce `MemoryOSKnowledgeExtractionOutput`. `MemoryOSBackgroundJobWorker` and `AppMemoryOSFacade.runBackgroundAIQueueOnce(...)` execute those jobs through a `MemoryOSBackgroundModelExecutor`, then hand the returned artifact JSON to the existing validation/projection gate. Program code plans jobs and validates artifacts; the LLM does the semantic judgment in prompt space.

L1 is an active memory sequence, not the durable source of truth. L0 keeps the raw provenance object/span. Therefore, after an accepted L1→L2 projection, Connor physically deletes the processed `memory_l1_capture_events`. If the executor fails, the artifact is rejected, or the job dead-letters, L1 remains available for retry.

`SQLiteMemoryOSUnifiedRetrievalService` is the native retrieval surface for AI background jobs and agent tools. It searches L0/L1/L2/L3/L4 and returns layer-aware hits with evidence, provenance and entity refs. L4 supports `depth` expansion through `expandL4(entityID:depth:limit:)`, exposed to agents as `memory_os_expand_l4`. The general `memory_os_search` tool returns summaries first; hits are context, not truth.

L2 organization state is tracked outside the immutable fact row through `memory_l2_statement_processing_state`. This lets Connor select unorganized L2 facts for knowledge synthesis without overwriting historical statements. Improvements to L2 should append refined statements and connect them through metadata/projection state rather than mutating old facts in place.

Native source ingestion is normalized through `AppMemoryOSNativeSourceEventBridge`, which adapts Mail, Calendar, RSS, browser history, attachment text and media transcripts into `ingestSourceEvent(...)`. Task scheduling reaches the pipeline through `memory_os.pipeline` targets such as `plan_l1_to_l2_jobs` and `plan_l2_to_knowledge_jobs`.

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
  - `system`：Connor protected tasks，用户可查看、暂停和恢复，不可删除；当前包括 10 分钟邮件刷新、10 分钟日历刷新，以及由每个 RSS source 的 `fetchPolicy.intervalMinutes` 派生出的 per-source RSS refresh tasks
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
- Task runtime execution：`TaskSchedulerService` 计算 due tasks，`TaskSchedulerRunnerService` 记录 run history 并调用 `TaskTargetRunner`，真实分发到 Native Mail / Calendar / RSS runtimes、Session OS message flow 或浏览器媒体转写 handler。`source.runtime` refresh targets 现在通过 `SourceRefreshTaskRequest` 传递 `sourceKind`、`sourceInstanceID` 和 `runID`；RSS source-instance task 会只刷新对应 RSS source，而不是刷新所有 RSS sources。
- Source sync policy boundary：source config 是同步策略事实来源，TaskDefinition 是 materialized projection。RSS 当前由 `SourceRefreshTaskMaterializer` 根据 `RSSSource.fetchPolicy.intervalMinutes` 生成/更新 `system.rss.source.{rssSourceID}.refresh`；当 RSS source 删除后，对应 task definition 会被物理清除，避免开发阶段保留无效结构。
- Missed recurring schedule semantics：应用启动和 60 秒轮询都会扫描 due tasks；如果每日/每周/每月重复任务在应用未运行期间错过至少一次，Connor 下次启动/轮询时会立即补执行一次，并把 `nextRunAt` 推进到原始 `runAt` 锚点之后的下一个未来计划点；不会对错过的每一个周期批量补跑，避免会话消息或 source refresh 噪音。Source refresh 同步同样采用 catch up once 语义：恢复后运行一次以追平 source cursor，而不是按错过 interval 批量 replay。
- 浏览器媒体转写任务使用 Task Stack 获得 recoverable run/history 能力，但不作为“系统定时任务”卡片显示；它的用户可见面在对应会话的 background task surface。若用户一次选择多段媒体，App 会拆成多个单源 job/task；每个完成后的 follow-up chat 只携带该 job 最新 transcript 附件 ref，避免跨视频提交错附件。
- Session-scoped background task adapter remains for recoverable per-session runtime intents

---

## 6. UI and Accessibility Guidelines for This Codebase

Connor is a native macOS app. UI changes should follow these rules：

1. Prefer SwiftUI/AppKit/macOS-native components over custom web UI.
2. Pure icon buttons need either a visible label or `.accessibilityLabel(...)`; `.help(...)` should be added for toolbar-like controls where useful.
3. `NSViewRepresentable` / WebKit / PDFKit bridges should preserve platform accessibility semantics or expose explicit labels when the wrapped control does not.
4. Avoid duplicate sources of truth for sidebar selection, detail selection and settings navigation.
5. Use design-system tokens already present in `AgentChatDesignSystem` / `AppShellDesignSystem` instead of ad-hoc colors and dimensions where possible.
6. Avoid nested navigation titles that can leak into macOS window/menu state.
7. Do not make destructive or governance actions one-key direct execution; shortcuts may open review surfaces, but execution must still go through Connor policy/review gates.

---

## 7. Development Commands

From the repository root：

```bash
swift test
swift test --filter ScientificComputeRuntimeTests
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

Current review baseline：

```text
swift test
→ Test run with 866 tests in 77 suites passed.
```

---

## 8. Code Quality Checklist

Before claiming a change is complete：

- Run the smallest relevant tests first.
- Run full `swift test` before final handoff.
- Keep provider/sidecar/source adapters behind Connor-owned policy and audit boundaries.
- Keep credentials out of JSON config files.
- Keep Graph Memory writes staged and reviewable.
- Keep attachment source of truth in Session Capsule / Attachment Store.
- Any native source mutation must update, invalidate, or explicitly fallback around the Native Source Search index.
- Any Mail/RSS/Calendar search result must preserve temporal metadata; time-sensitive queries should use structured `timePreset` or `startDate`/`endDate` filters.
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
