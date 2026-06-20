# Connor Graph Agent Mac

文档更新时间：2026-06-21 00:17 GMT+8  
当前分支目标：收紧代码质量、简化文档、保持 Connor 的原生 Agent OS 边界，并为内置浏览器媒体本地转写系统建立可恢复、可治理的地基。

Connor Graph Agent Mac 是一个 Swift / SwiftUI macOS 应用和 SwiftPM package。它的目标不是做“图谱编辑器”或“Claude SDK 外壳”，而是构建一个本地优先的 **graph-memory-native Agent OS**：以 Session OS、Policy Engine、Graph Memory、Source/MCP Platform、Native UI、Task Management Stack 和 Attachment Store 共同组成可治理的本地智能工作台。

核心判断：**图谱是后台记忆基础设施，不是普通用户的前台主导航概念。** 普通用户面对的是会话、数据源、技能、自动化、浏览器、附件、任务和设置；Graph Memory 在后台提供连续性、精确性、可追溯性与治理证据。

---

## 1. Product Boundaries

Connor 当前坚持以下主权边界：

- **Session sovereignty belongs to Connor Session OS**：会话、run、journal、pending approval、branch、restore snapshot 和 Session Capsule 由 Connor 持久化与恢复。
- **Permission sovereignty belongs to Connor Policy Engine**：Claude SDK sidecar、MCP server、local tools 和 native runtimes 都不能绕过 Connor 审批、审计和执行门禁。
- **Memory sovereignty belongs to Connor Graph Memory**：LLM 不直接写图谱；图谱写入走 staging、distillation、candidate review、admission policy 与 SQLite temporal graph。
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
Claude SDK owning Connor session state
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
Sources/ConnorGraphMemory      Memory staging, distillation, validation
Sources/ConnorGraphStore       SQLite graph/session/audit persistence
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
ConnorGraphAgent + Model Providers + Claude SDK Sidecar Boundary
  ↓
Graph Memory Runtime Contract
  ↓
SQLite Temporal Graph + Hybrid Retrieval + Memory Governance
```

### 3.1 ConnorGraphCore

Core domain target. It contains stable data structures and enums for：

- Temporal graph entities, edges, observations and evidence
- Session OS state and attention models
- Permission and policy domain
- Attachment domain
- Mail/RSS/Calendar/Contacts source domains
- Skill, task, product registry and automation domains
- Graph extraction, write candidates and governance states

### 3.2 ConnorGraphMemory

Memory governance layer. It is responsible for：

- Observe logs and staged memory records
- LLM memory distillation contracts
- Constraint validation and contradiction detection
- Promotion/admission-oriented memory workflows

### 3.3 ConnorGraphStore

SQLite-backed persistence layer. It owns：

- Temporal graph kernel store
- Graph traversal and hybrid retrieval persistence
- Agent session/run/event/audit persistence
- Graph extraction traces, hold queues, replay, grounding checks and self-healing support

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
- Graph candidate review and diagnostics views

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

旧全局 RSS 任务 `system.rss.check-every-30-minutes` 会被保留但标记为 stopped/deprecated，用于保留历史并避免和 per-source RSS 任务重复同步。
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
- Claude Sidecar uses the primary root as single cwd; Connor native tools can use multiple allowed roots

### 5.3 Model Providers and Sidecar Boundary

- OpenAI-compatible provider path
- Anthropic-compatible provider path
- OpenAI-compatible and Anthropic-compatible agent completions support SSE streaming through Connor's model-provider abstraction
- OpenAI-compatible chat completion requests use an explicit 180-second default request timeout instead of relying on `URLSession.shared` defaults
- Anthropic-compatible Messages API requests use the same explicit 180-second default request timeout for streaming, non-streaming and health-check paths
- Non-streaming completion and provider health-check paths remain available as fallbacks
- Claude SDK sidecar boundary
- Persistent Claude SDK sidecar sessions stream stdout JSONL events and use Connor-owned cancel commands for session shutdown
- Non-persistent Claude SDK sidecar process transport uses a 300-second watchdog timeout to prevent stuck child processes from blocking indefinitely
- Per-connection settings and per-session model override
- Provider health checks and credential boundary
- Guardrails to avoid routing governed sidecar mode through legacy direct provider paths

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

### 5.8 Graph Memory

- Staging, distillation, candidate review and admission policy
- SQLite temporal graph storage
- Graph extraction traces and replay support
- Grounding checks, hold queues and self-healing services
- Hybrid retrieval and retrieval evaluation

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
- Source sync policy boundary：source config 是同步策略事实来源，TaskDefinition 是 materialized projection。RSS 当前由 `SourceRefreshTaskMaterializer` 根据 `RSSSource.fetchPolicy.intervalMinutes` 生成/更新 `system.rss.source.{rssSourceID}.refresh`；当 RSS source 删除后，对应 task 会 stopped/deprecated 而不是直接删除。
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
