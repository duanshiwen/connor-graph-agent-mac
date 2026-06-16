# Connor Graph Agent Mac

文档更新时间：2026-06-17 00:01 GMT+8  
当前代码基线:`feature/apple-iwork-attachment-support`,在已合入的浏览器 / Session Capsule / Native UI / Local Automation Surface / session-scoped multi-root project workspace / Connor-owned Scientific Compute Runtime skeleton / 商用级 Document Attachment OS / WKWebView-backed `web_fetch(js)` 基础上,继续收紧 Apple 原生 UI 边界:PDF/Word/Excel/PowerPoint 与 Apple iWork（Pages/Numbers/Keynote）一等附件仍由 Connor Session Capsule 和 Attachment Store 管理;PDF selectable text 抽取和多页原文预览继续使用 PDFKit;Office/iWork/Presentation/Spreadsheet 抽取继续通过 MarkItDown/Docling sidecar best-effort 编排与 hardening;Office/iWork/Presentation/Spreadsheet 原文件预览优先交给 macOS Quick Look / QuickLookUI,Connor 自有 UI 只负责 manifest、extraction status、retry、omitted attachment summary 和治理证据;AI 设置页 Add Connection 前置 DeepSeek、Xiaomi MiMo 和中国常用模型入口,在 OpenAI Compatible 统一底座上支持 MiMo 官方 `api-key` 认证头。

Connor Graph Agent Mac 是一个 Swift / SwiftUI macOS 应用和 SwiftPM package,目标是把 Connor 建成 **graph-memory-native Agent OS**:它不是"图谱编辑器",也不是"Claude SDK 外壳",而是以 Session OS、Policy Engine、Graph Memory、Source/MCP Platform、Native UI 和 Local Automation Surface 共同构成的本地 Agent 操作系统。

核心产品判断:**图谱是后台记忆基础设施,不是前台主导航概念。** 普通用户面对的是会话、数据源、技能、自动化、设置和本地 CLI/API 控制面;Graph Memory 在后台提供连续性、精确性、可追溯性和治理证据。

---

## Product Boundaries

Connor 当前坚持以下主权边界:

- **Session sovereignty belongs to Connor Session OS**:会话、run、journal、pending plan、branch、restore snapshot 由 Connor 持久化与恢复。
- **Permission sovereignty belongs to Connor Policy Engine**:Claude SDK sidecar 和 MCP servers 都不能绕过 Connor 审批、审计和执行门禁。
- **Memory sovereignty belongs to Connor Graph Memory**:对话 LLM 不直接写图谱;Graph Memory 写入走 staging、distillation、candidate review、admission policy 与 SQLite temporal graph。
- **Source sovereignty belongs to Connor Source Platform**:MCP servers 是外部能力提供者,不拥有 Connor source registry、permission policy、audit、graph ingestion policy 或 readiness state。
- **UI sovereignty belongs to Swift Native Shell**:不 fork Craft UI,不引入 Electron/Web UI,不引入 Craft-style multi-workspace。对于文件预览、设置窗口、inspector、文件/目录选择、菜单命令等 Apple 已有稳定语义的能力,优先使用 macOS / SwiftUI / AppKit 原生实现;Connor 自定义 UI 只承载 Agent OS 特有状态和治理工作流。
- **Automation sovereignty belongs to Connor Local Automation Surface**:CLI/API 只能通过本地、可审计、可 dry-run、可 review 的 contract 调用 Connor runtime。
- **Attachment sovereignty belongs to Connor Session OS / Attachment Store**:用户文件先进入本地 Session Capsule,原文件、manifest、派生抽取文本和 message refs 由 Connor 管理;OpenAI/Claude/Gemini 等 provider-native file API 未来只能作为可治理的投递/缓存策略,不能成为 source of truth。

明确不做:

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
Unreviewed automation execution bypass
```

---

## Package Information

```text
Package name: ConnorGraphAgentMac
Swift tools version: 6.0
Platform: macOS 14+
System libraries/frameworks: sqlite3, Security, WebKit, PDFKit, QuickLookUI
```

Products:

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

Source targets:

```text
Sources/ConnorGraphCore
Sources/ConnorGraphMemory
Sources/ConnorGraphStore
Sources/ConnorGraphSearch
Sources/ConnorGraphAgent
Sources/ConnorGraphAppSupport
Sources/ConnorGraphAgentMac
Sources/ConnorCLI
```

Test targets:

```text
Tests/ConnorGraphCoreTests
Tests/ConnorGraphMemoryTests
Tests/ConnorGraphStoreTests
Tests/ConnorGraphSearchTests
Tests/ConnorGraphAgentTests
Tests/ConnorGraphAppSupportTests
```

Sidecar directory:

```text
sidecars/claude-agent-engine
```

---

## Runtime Storage Layout

运行时根目录由 `AppStoragePaths` 解析到用户 Application Support 下的 `Connor` 目录。当前实现使用单一 Home / Runtime Root。

```text
Connor/
├── config/
├── sessions/
├── sources/
├── skills/
├── automations/
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

Session Capsule / artifact directories:

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
│   │   ├── fts/
│   │   │   └── {attachmentID}.json
│   │   └── embedding-index.json
│   ├── provider-cache/
│   │   ├── openAI/
│   │   ├── claude/
│   │   └── gemini/
│   └── {attachmentID}/
│       ├── manifest.json
│       ├── original/
│       │   └── {safeOriginalFilename}
│       ├── derivatives/
│       │   ├── current/
│       │   │   └── extracted.md
│       │   ├── runs/{runID}/
│       │   │   └── extracted.md
│       │   ├── structured.json
│       │   ├── pages.jsonl
│       │   ├── media-transcript.md
│       │   └── extraction-report.json
│       └── lineage/
│           └── extraction-events.jsonl
├── exports/
└── logs/
```

Connor 的会话持久化边界是完整 Session Capsule:SQLite 仍承担 session / run / event / graph 查询存储,但 session-local 的 UI/workspace 状态、记录流、附件、plans、data、logs 与 browser 子状态都归属于 `sessions/{sessionID}/`。`session-state.json` 可保存 `workspace` 引用和 `llmOverride`(per-session 模型覆盖),用于记录当前会话绑定的 project working directory 来源与路径以及独立的模型选择;`records.jsonl` 使用单行 JSONL 追加保存,读取时可跳过坏行,避免 10+ 条记录因一次异常写入或重启退化成 1 条。会话删除采用 soft delete:SQLite `agent_sessions.deleted_at` 标记会话已从普通列表/界面移除,但不删除 session row、run/event/background task 记录,也不删除 `sessions/{sessionID}/` 下的 Session Capsule 文件、附件、records、browser、plans、data、logs。

Attachment OS 当前遵循本地优先:被允许的附件会复制到 `attachments/{attachmentID}/original/`,写入 `manifest.json` 和 `attachment-manifest.jsonl`;文本/代码/Markdown/JSON/CSV/XML/YAML/日志会立即生成 `derivatives/current/extracted.md`,并在 `derivatives/runs/{runID}/extracted.md` 保留本次抽取产物以避免文件名冲突。PDF、Word、Excel、PowerPoint 和 Apple iWork（Pages/Numbers/Keynote）会先以 `extractionStatus = pending` 保存原件和 manifest,再写入 `extraction-jobs.jsonl` 等待文档抽取 worker/processor 处理;成功后同样写入 current/runs extracted markdown,失败或 unsupported 时保留原件、report、warnings/errors 和可重试的 job 记录。iWork package 目录按 regular files 递归计算大小与稳定 digest,并整体复制进 Session Capsule。

当前 Document Attachment OS 使用显式 allowlist:支持 `.txt`, `.md`, `.markdown`, `.log`, `.json`, `.jsonl`, `.csv`, `.tsv`, `.xml`, `.yaml`, `.yml`、常见代码扩展、常见图片（PNG/JPEG/GIF/WebP/HEIC/BMP/ICO/TIFF）,以及 `.pdf`, `.doc`, `.docx`, `.rtf`, `.xls`, `.xlsx`, `.ppt`, `.pptx`, `.pages`, `.numbers`, `.keynote`。文本类默认 512 KB 上限,图片默认 10 MB 上限,文档类默认 25 MB 上限。HTML/HTM、音频、视频、压缩包、SVG/AVIF、数据库、可执行/安装包/二进制和未知扩展仍在导入时拒绝;被拒绝文件不复制进 Session Capsule、不写 manifest、不生成 message ref、不进入 composer、不进入 prompt,并通过聊天上下文反馈导入状态和拒绝原因。

文档抽取策略遵循可降级商用路径:PDF 优先使用 PDFKit 抽取 selectable text;如果 PDF 没有文本层,会返回 unsupported warning 并保留后续 OCR/sidecar 入口。Office/iWork/Presentation/Spreadsheet 文档走 MarkItDown、Docling 等命令型 sidecar best-effort;sidecar 通过 `Process.arguments` 调用,带 timeout、stdout 大小限制、stderr 捕获和结构化 failed report。发送消息时,AppViewModel 只把已成功抽取且在预算内的 current extracted text 注入 `## User Attachments` prompt section;pending/unsupported/failed/skippedOversize 附件不会静默忽略,会作为 omitted attachment summary 说明其状态。composer pending attachment chip 和 transcript attachment chip 仍打开现有纯阅读预览弹窗,但弹窗内容区会按类型分流:PDF 原文件使用 PDFKit `PDFView` 单页连续纵向滚动预览,避免嵌入式 Quick Look 只显示第一页;Office、iWork、Presentation、Spreadsheet 和图片原文件继续使用 macOS Quick Look / QuickLookUI 原生预览。Connor 自有预览内容保留用于 extracted markdown、manifest、等待解析、无法解析、解析失败和 retry 等 Attachment OS 状态。

商业闭环骨架仍保留以下未来扩展入口:OCR 扫描 PDF、XLSX 多 sheet 结构化 JSON、PPT slide-level JSONL、OpenAI/Claude/Gemini provider-native file API、remote upload/purge、attachment search/embedding index、Graph Memory evidence candidate、enterprise audit mirror 和 full attachment inspector。这些能力必须继续围绕同一 Attachment Store 工作,不能绕过 Connor Session OS。

主要状态文件:

```text
config/session-governance.json
config/product-os-registry.json
config/runtime-settings.json
config/llm-settings.json
automations/automations.json
automations/automation-trigger-log.json
automations/automation-execution-history.json
labels/labels.json
statuses/statuses.json
graph/evaluations/retrieval-evaluation-cases.json
graph/evaluations/reports/*.json
```

预制会话治理项使用稳定英文 ID + 中文显示名,避免破坏自动化、CLI、存储和已有引用:

```text
Statuses:
- todo → 待办
- in_progress → 进行中
- waiting → 等待中
- needs_review → 待审阅
- blocked → 受阻
- done → 已完成
- archived → 已归档

Labels:
- important → 重要
- research → 研究
- priority → 优先级
- due → 截止日期
- project → 项目
```

标签就是标签:每个标签只有系统生成的稳定 UID、显示名和颜色,不再承载 value type、日期/数字/link 解析或 graph binding。创建标签时用户只输入显示名和选择颜色,不需要提供英文 ID;系统自动生成不重复的 `label_<uuid>`。

`config/session-governance.json` 首次创建时写入上述中文默认显示名;若本地已有旧版英文内置项,启动读取配置时会按内置 ID 将这些预制项迁移为中文显示名,自定义状态/标签不被覆盖。

`runtime-settings.json` 保存应用、外观、输入、权限、UI、用户偏好和轻量 MRU 历史类设置。项目工作目录不再作为设置页里的全局主状态;每个会话在自己的 Session Capsule 中保存 `workspace` 引用和 roots。会话页 composer 底部的 folder badge 是当前工作目录的高频入口,可快速切换 primary root、通过"历史打开列表"二级菜单恢复最近打开目录、选择新目录或重置为默认;顶部 Workspace 详情用于 multi-root 管理。`runtime-settings.workspace.defaultWorkingDirectoryPath` / `runtime-settings.workspace.roots` / `llm.sidecar.workingDirectoryPath` 仅保留为 legacy fallback / 新会话初始模板兼容层;`runtime-settings.workspace.recentWorkspacePaths` 保存跨会话最近打开目录列表。Native local tools 使用当前 session 的 multi-root allowed roots;Claude Sidecar 使用当前 session primary root 作为单一 cwd。`llm-settings.json` 保存模型提供方、Base URL、模型名和 Claude Sidecar 配置。API Key 不写入 JSON,由本地 Keychain 凭据仓库管理。

---

## Architecture Overview

```text
SwiftUI Native Shell
  ↓
ConnorGraphAppSupport
  ↓
Session OS / Source Platform / Skill Runtime / Automation Surface / Readiness Gate
  ↓
ConnorGraphAgent + Claude SDK Sidecar Boundary
  ↓
Graph Memory Runtime Contract
  ↓
SQLite Temporal Graph + Hybrid Retrieval + Memory Governance
```

### ConnorGraphCore

领域模型 target。包含:

- Temporal graph domain
- Agent conversation domain
- Agent permission domain
- Agent runtime event domain
- Session OS domain
- Session governance model
- Product OS registry model
- Product OS automation model
- Graph extraction domain
- Structured extraction domain
- Graph write candidate domain
- Optimistic write domain
- Self-healing domain

关键文件:

```text
Sources/ConnorGraphCore/AgentConversation.swift
Sources/ConnorGraphCore/AgentPermissionDomain.swift
Sources/ConnorGraphCore/AgentRuntimeDomain.swift
Sources/ConnorGraphCore/SessionOSDomain.swift
Sources/ConnorGraphCore/AgentSessionGovernance.swift
Sources/ConnorGraphCore/ProductOSRegistry.swift
Sources/ConnorGraphCore/ProductOSAutomation.swift
Sources/ConnorGraphCore/GraphExtractionDomain.swift
Sources/ConnorGraphCore/GraphStructuredExtraction.swift
Sources/ConnorGraphCore/GraphWriteCandidate.swift
Sources/ConnorGraphCore/GraphOptimisticWriteDomain.swift
Sources/ConnorGraphCore/GraphSelfHealingDomain.swift
```

### ConnorGraphMemory

记忆管线 target。包含:

- Observe log
- Memory ingestion
- Memory staging buffer
- Memory distillation
- LLM-backed memory distillation interface
- Promotion candidate model
- Constraint validation
- Contradiction detection

关键文件:

```text
Sources/ConnorGraphMemory/MemoryIngestionService.swift
Sources/ConnorGraphMemory/MemoryStaging.swift
Sources/ConnorGraphMemory/MemoryDistillation.swift
Sources/ConnorGraphMemory/MemoryDistillationService.swift
Sources/ConnorGraphMemory/LLMMemoryDistiller.swift
Sources/ConnorGraphMemory/MemoryPromotion.swift
Sources/ConnorGraphMemory/GraphConstraintValidator.swift
Sources/ConnorGraphMemory/GraphContradictionDetector.swift
```

### ConnorGraphStore

SQLite 持久化和后台 worker target。包含:

- SQLite graph kernel store
- SQLite temporal graph store
- Session OS persistence tables
- Agent runtime persistence
- Chat session persistence
- Audit persistence
- Entity resolver and resolution plan
- Conflict preview
- Extraction prompt builder
- LLM graph extractor
- Extraction trace persistence and replay
- Graph write admission policy
- Optimistic write service
- Background job runner
- Extraction / index refresh / grounding workers
- Memory change log
- Admission hold queue
- SQLite hybrid search service

关键文件:

```text
Sources/ConnorGraphStore/SQLiteGraphKernelStore.swift
Sources/ConnorGraphStore/SQLiteGraphStore.swift
Sources/ConnorGraphStore/SQLiteGraphHybridSearchService.swift
Sources/ConnorGraphStore/SQLiteGraphEntityResolver.swift
Sources/ConnorGraphStore/GraphEntityResolutionPlan.swift
Sources/ConnorGraphStore/GraphExtractionConflictPreview.swift
Sources/ConnorGraphStore/GraphExtractionPromptBuilder.swift
Sources/ConnorGraphStore/LLMGraphExtractor.swift
Sources/ConnorGraphStore/GraphExtractionWorker.swift
Sources/ConnorGraphStore/GraphWriteAdmissionPolicy.swift
Sources/ConnorGraphStore/GraphOptimisticWriteService.swift
Sources/ConnorGraphStore/GraphGroundingCheckWorker.swift
Sources/ConnorGraphStore/GraphMemoryChangeLog.swift
Sources/ConnorGraphStore/GraphAdmissionHoldQueue.swift
```

### ConnorGraphSearch

图谱检索和检索评估 target。包含:

- Graph search query / hit / response types
- Hybrid graph search service protocol
- Reranking config
- Embedding provider protocol
- Retrieval evaluation cases, judgments, hits, metrics and reports
- Retrieval evaluation harness

关键文件:

```text
Sources/ConnorGraphSearch/GraphSearch.swift
Sources/ConnorGraphSearch/GraphHybridSearch.swift
Sources/ConnorGraphSearch/EmbeddingProvider.swift
Sources/ConnorGraphSearch/GraphRetrievalEvaluation.swift
```

### ConnorGraphAgent

Agent runtime target。包含:

- Agent backend abstraction
- Type-erased backend
- Model provider abstraction
- OpenAI-compatible provider
- Tool-calling loop
- Graph read tools
- Graph write tools
- Web/search tools
- Native local workspace tools
- Scientific Compute Runtime tools
- Permission policy
- Prompt budget estimation and inspection
- Session summary strategy
- Agent event recorder and replayer
- Text delta buffering
- Runtime usage tracking
- Graph Memory core runtime contract

关键文件:

```text
Sources/ConnorGraphAgent/GraphAgentBackend.swift
Sources/ConnorGraphAgent/AnyAgentBackend.swift
Sources/ConnorGraphAgent/AgentLoopController.swift
Sources/ConnorGraphAgent/GraphMemoryCoreRuntime.swift
Sources/ConnorGraphAgent/AgentTool.swift
Sources/ConnorGraphAgent/GraphReadTools.swift
Sources/ConnorGraphAgent/GraphWriteTools.swift
Sources/ConnorGraphAgent/LocalWorkspacePolicy.swift
Sources/ConnorGraphAgent/LocalWorkspaceTools.swift
Sources/ConnorGraphAgent/ScientificComputeRuntime.swift
Sources/ConnorGraphAgent/AgentPermission.swift
Sources/ConnorGraphAgent/AgentEvent.swift
Sources/ConnorGraphAgent/AgentEventRecorder.swift
Sources/ConnorGraphAgent/AgentEventReplayer.swift
Sources/ConnorGraphAgent/AgentTextDeltaBuffer.swift
Sources/ConnorGraphAgent/AgentRuntimeUsageTracker.swift
Sources/ConnorGraphAgent/OpenAICompatibleProvider.swift
Sources/ConnorGraphAgent/AnthropicCompatibleProvider.swift
Sources/ConnorGraphAgent/AnthropicStreaming.swift
```

### ConnorGraphAppSupport

App repositories、runtime factory、runtime integration、commercial readiness 和 SwiftUI presentation model target。包含:

- App storage path resolution
- SQLite bootstrap
- Graph repository
- Chat session repository
- Session governance config repository
- Runtime settings repository
- Session artifact manager
- Product OS registry repository
- Source runtime repository
- Skill runtime repository
- Automation repository
- Automation engine and execution history
- Local API / CLI / Automation Surface contract
- Retrieval evaluation repository
- LLM settings repository
- LLM provider health checker
- Keychain credential store
- Agent runtime factory
- Governed Claude SDK sidecar runtime
- Claude SDK sidecar backend
- Claude SDK sidecar runtime store
- Native session manager
- Pending approval repository
- Audit log repository
- App memory staging and distillation workers
- MCP JSON-RPC client
- MCP source runtime
- Skill runtime
- Graph Memory Productization Center
- Native shell presentation
- Runtime/readiness presentation models
- Source / skill / automation UI presentation
- Command palette presentation
- Deep-link navigation resolver

关键文件:

```text
Sources/ConnorGraphAppSupport/AppStoragePaths.swift
Sources/ConnorGraphAppSupport/AppGraphBootstrapper.swift
Sources/ConnorGraphAppSupport/AppChatSessionRepository.swift
Sources/ConnorGraphAppSupport/AppRuntimeSettingsRepository.swift
Sources/ConnorGraphAppSupport/AppSessionArtifactManager.swift
Sources/ConnorGraphAppSupport/AppProductOSRegistryRepository.swift
Sources/ConnorGraphAppSupport/AppMCPSourceRuntimeRepository.swift
Sources/ConnorGraphAppSupport/AppSkillRuntimeRepository.swift
Sources/ConnorGraphAppSupport/AppProductOSAutomationRepository.swift
Sources/ConnorGraphAppSupport/AutomationEngine.swift
Sources/ConnorGraphAppSupport/ConnorLocalAutomationSurface.swift
Sources/ConnorGraphAppSupport/AppGraphRetrievalEvaluationRepository.swift
Sources/ConnorGraphAppSupport/AppLLMSettingsRepository.swift
Sources/ConnorGraphAppSupport/AppLLMProviderHealthChecker.swift
Sources/ConnorGraphAppSupport/AppGraphAgentRuntimeFactory.swift
Sources/ConnorGraphAppSupport/GovernedClaudeSDKSidecarRuntime.swift
Sources/ConnorGraphAppSupport/ClaudeSDKSidecarBackend.swift
Sources/ConnorGraphAppSupport/AppClaudeSDKSidecarRuntimeStore.swift
Sources/ConnorGraphAppSupport/NativeSessionManager.swift
Sources/ConnorGraphAppSupport/AppAgentPendingApprovalRepository.swift
Sources/ConnorGraphAppSupport/SQLiteAgentAuditLog.swift
Sources/ConnorGraphAppSupport/MCPJSONRPCClient.swift
Sources/ConnorGraphAppSupport/MCPSourceRuntime.swift
Sources/ConnorGraphAppSupport/SkillRuntime.swift
Sources/ConnorGraphAppSupport/GraphMemoryProductizationCenter.swift
Sources/ConnorGraphAppSupport/ConnorNativeCommercialUIPresentation.swift
Sources/ConnorGraphAppSupport/ConnorNativeShellPresentation.swift
Sources/ConnorGraphAppSupport/SourceSkillAutomationUIPresentation.swift
Sources/ConnorGraphAppSupport/ConnorDeepLinkNavigator.swift
Sources/ConnorGraphAppSupport/CommercialReadinessGate.swift
```

### ConnorGraphAgentMac

SwiftUI macOS executable target。当前前台体验采用 Native Agent OS shell:Sessions 默认入口,左侧产品导航,中间列表/分类,右侧详情工作区。

包含:

- App entry point
- Native product sidebar navigation
- Three-column session shell
- Conversation list with status / labels
- Agent chat workbench
- Floating session info panel
- Composer-level permission picker
- Composer-level model picker(per-session model override:会话可独立选择模型,切换会话自动恢复;composer 底部蓝色圆点标识当前会话使用自定义模型,菜单内提供"恢复全局默认模型"选项)
- Settings center
- Source runtime panel
- Skill runtime panel
- Automation runtime panel
- Local API / CLI surface entry
- Browser workspace view

关键文件:

```text
Sources/ConnorGraphAgentMac/ConnorGraphAgentMacApp.swift
Sources/ConnorGraphAgentMac/SourceSkillAutomationRuntimeViews.swift
Sources/ConnorGraphAgentMac/AgentChatView.swift
Sources/ConnorGraphAgentMac/BrowserWorkspaceView.swift
Sources/ConnorGraphAgentMac/EmptyGraphHybridSearchService.swift
```

### ConnorCLI

SwiftPM CLI executable target。当前是 local-only programmable control plane 的最小入口,不依赖远程 daemon。

关键文件:

```text
Sources/ConnorCLI/main.swift
```

当前命令:

```bash
swift run connor commands
swift run connor readiness
swift run connor automations evaluate --trigger sessionStatusChanged --session demo --status needs_review --dry-run
```

---

## Session OS

Commercial Train 1 将 `NativeSessionManager` 从 turn executor 推进为持久化 Session OS runtime。

当前能力:

- Durable run lifecycle:queued、running、completed、failed、cancelled、waitingForApproval
- Session journal
- Pending approvals restore
- Pending plans
- Branch records
- Restore snapshot
- Status / label / archive / restore governance fanout
- Runtime state metadata

关键持久化表:

```text
session_pending_plans
session_branch_records
```

关键类型:

```text
SessionOSJournalPayload
SessionPendingPlanStatus
SessionPendingPlan
SessionBranchRecord
SessionOSRestoreSnapshot
SessionLLMOverride
```

Session OS 的边界:Claude SDK sidecar、MCP server、CLI/API 都不拥有 Connor session state。

---

## Claude SDK Sidecar Runtime

Commercial Train 2 将 Claude SDK 作为外部执行引擎接入,但不让它成为产品状态 owner。

当前 sidecar 目录:

```text
sidecars/claude-agent-engine/claude-sidecar.mjs
```

Swift 侧关键文件:

```text
Sources/ConnorGraphAppSupport/GovernedClaudeSDKSidecarRuntime.swift
Sources/ConnorGraphAppSupport/ClaudeSDKSidecarBackend.swift
Sources/ConnorGraphAppSupport/AppClaudeSDKSidecarRuntimeStore.swift
Sources/ConnorGraphAppSupport/AppGraphAgentRuntimeFactory.swift
```

当前实现包含:

- `sdkSessionID` persistence
- Sidecar runtime record
- Sidecar runtime diagnostics
- Sidecar heartbeat / health decoding
- Cancel command envelope
- Approval resolution command mapping
- Persistent process transport
- Factory wiring through app storage paths
- Guardrail against routing governed Claude Sidecar mode through legacy direct model provider paths
- `bypassPermissions` 仅用于让 Connor Policy Engine 成为唯一审批/审计层,不表示 unrestricted product authority
- Sidecar `tool_result` 事件进入 Connor 时必须归一化为 `toolUseCompleted`:字符串正文进入 `contentText`;对象/数组等结构化内容会稳定序列化为 `contentText`,并同时保留 `contentJSON`;解析 fallback 顺序为 `content` → `text` → `result`。这条边界只转换 SDK 事件,不让 Claude SDK 拥有 Connor session / permission / audit / graph state。

---

## Source / MCP Platform

Commercial Train 3 将 MCP Source 从 config/call helper 升级为 Connor-owned source platform object。

关键文件:

```text
Sources/ConnorGraphAppSupport/AppMCPSourceRuntimeRepository.swift
Sources/ConnorGraphAppSupport/MCPJSONRPCClient.swift
Sources/ConnorGraphAppSupport/MCPSourceRuntime.swift
Sources/ConnorGraphAppSupport/SourceSkillAutomationUIPresentation.swift
```

当前能力:

- Source runtime registry persistence
- Stdio / HTTP transport configuration shape
- Source ID validation
- Tool name prefix validation
- Unsafe graph write policy rejection
- MCP JSON-RPC lifecycle:initialize、notifications/initialized、tools/list、tools/call、shutdown
- Server error mapping
- Source-prefixed tool catalog
- Disabled-source gate
- MCP tool call event bridge
- Product OS registry sync event
- Health status / lifecycle state
- Capability snapshot
- Health record
- Audit record
- Discovery snapshot
- Per-source `health.json`、`catalog.json`、`audit.jsonl`

边界:MCP servers 是能力提供者;Connor 拥有 registry、lifecycle、health、permission policy、graph ingestion policy、audit 与 readiness。

---

## Graph Memory Kernel

Commercial Train 4 将 Graph Memory 从后处理能力升级为 Agent runtime 核心能力。

当前图谱记忆相关类型包括:

```text
GraphEntity
GraphStatement
GraphEpisodeV3
GraphObservation
GraphExtractionDraft
GraphExtractionTrace
GraphMemoryChangeLog
GraphAdmissionHoldQueue
AgentGraphMemoryUsePolicy
AgentGraphMemoryContextItem
AgentGraphMemoryContextContract
AgentGraphMemoryFeedbackSignal
AgentGraphMemoryRuntimeSnapshot
```

当前写入路径:

```text
Input / Artifact / Message
→ Memory Staging
→ Memory Distillation
→ GraphEpisodeV3
→ GraphExtractionDraft
→ Entity Resolution
→ Conflict Preview
→ Constraint Validation
→ Admission Policy
→ Optimistic Write
→ SQLite Temporal Graph
→ FTS / Index Refresh
→ Memory Change Log
```

Agent context 注入路径:

```text
User message
→ AgentContextBuilder
→ GraphHybridSearchService
→ AgentGraphMemoryContextContract
→ AgentLoopController system memory context
→ Model response with citations/context snapshot
→ Memory feedback signals
→ Session OS journal
```

Graph write candidate 或 extraction draft 可进入 admission hold queue。Review Center 通过 `GraphMemoryProductizationCenter` 聚合 context use、feedback signal、distillation candidate、hold queue 和 change log,并提供 review evidence。

边界:对话 LLM 不直接写图谱;Graph Memory 继续作为 Connor-owned background memory substrate 服务通用助手。

---

## Automation Engine and Local Automation Surface

Automation Engine 文件:

```text
Sources/ConnorGraphCore/ProductOSAutomation.swift
Sources/ConnorGraphAppSupport/AppProductOSAutomationRepository.swift
Sources/ConnorGraphAppSupport/AutomationEngine.swift
```

Automation Engine 当前能力:

- Automation rule persistence
- Trigger log persistence
- Status trigger matching
- Label trigger matching
- Governed planning layer
- Safe action execution
- Pending-review action skip
- Execution history persistence
- AgentEvent audit bridge
- Repeated-trigger rate limiting

执行历史路径:

```text
automations/automation-execution-history.json
```

Commercial Train 6 新增 Local API / CLI / Automation Surface:

```text
Sources/ConnorGraphAppSupport/ConnorLocalAutomationSurface.swift
Sources/ConnorCLI/main.swift
```

当前 Local API route catalog:

```text
GET  /v1/readiness
GET  /v1/automation/rules
POST /v1/automation/evaluate
POST /v1/automation/execute-reviewed
GET  /v1/commands
```

当前 CLI catalog:

```text
connor commands
connor readiness
connor automations list
connor automations evaluate --trigger <kind> --session <id> --status <status> --dry-run
connor automations execute-reviewed --review-token <token>
```

其中当前 smoke-tested commands:

```text
connor commands
connor readiness
connor automations evaluate --trigger sessionStatusChanged --session demo --status needs_review --dry-run
```

Automation Surface readiness evidence:

```text
endpointCount
cliCommandCount
automationTriggerCount
dryRunEvaluationReady
reviewedExecutionGateReady
auditSurfaceReady
localOnlySafetyReady
```

安全边界:

- Local API 是 contract/router,不默认启动长期 server。
- CLI/API 不直接写图谱。
- State-changing automation 必须经过 reviewed execution gate。
- Dry-run evaluation 输出 matched rules、action plans、ready/pending/blocked counts 和 audit summary。
- Unsafe 或 pending-review actions 不会被未审查执行。

---

## Native UI

Commercial Train 5 将 Native UI 从功能入口集合升级为商业级 Agent OS 控制台。Native UI 的实现边界遵循 Apple-owned UI first:PDF 原件多页预览和文本抽取使用 PDFKit,Office/iWork/Presentation/Spreadsheet 原件预览使用 Quick Look / QuickLookUI,系统级设置、inspector、文件选择和命令尽量沿用 macOS/SwiftUI/AppKit 原生语义;Connor 自定义视图只负责会话、权限、附件解析状态、Graph Memory、Source/Skill/Automation 等 Agent OS 特有控制面。

当前 shell 信息架构:

```text
Home
Work
Memory
Governance
Extensions
System
```

当前主入口:

```text
Sessions
```

当前 sidebar destinations:

```text
New Session
All Sessions
Labels
Data Sources
Skills
Automations
Settings
```

当前 native panels / views:

```text
CraftPrimarySidebarView
CraftListPaneView
CraftSessionListPane
CraftDetailPaneView
AgentChatView
AgentChatComposerView
AgentChatInspectorView
AgentToolInvocationDetailOverlay
AgentToolOutputRenderers
WorkspaceRootsSettingsContent
WorkspaceRootRow
ConnorSettingsDetailView
SourceRuntimePanelView
SkillRuntimePanelView
AutomationRuntimePanelView
BrowserWorkspaceView
```

### Keyboard Shortcuts

Connor 的快捷键策略应遵循 Apple-owned UI first:优先沿用 macOS 用户已熟悉的菜单语义,高频 Agent OS 动作用 `⌘` 组合键,局部浮层和编辑弹窗使用 `Esc` / Return 等系统默认行为。当前代码中快捷键来源主要有三类:

- App menu commands:`Sources/ConnorGraphAgentMac/ConnorGraphAgentMacApp.swift`
- Native shell command catalog:`Sources/ConnorGraphAppSupport/ConnorNativeShellPresentation.swift`
- 局部视图快捷键:Browser Workspace、Attachment/Tool/Inspector overlays、Settings editor dialogs

当前设置页可修改且真实可用的快捷键:

| 区域 | 默认快捷键 | 动作 | 生效方式 | 代码入口 |
| --- | --- | --- | --- | --- |
| 全局菜单 | `⌘N` | 新建会话并进入聊天 | App menu command 读取 `runtime-settings.json` | `AppViewModel.performShortcutAction(.newSession)` |
| 全局菜单 / Composer | `⌘B` | 显示 / 隐藏 Browser Workspace | App menu command 读取 `runtime-settings.json` | `AppViewModel.performShortcutAction(.toggleBrowser)` |
| 全局菜单 | `⌘F` | 聚焦应用顶部搜索 | App menu command 读取 `runtime-settings.json` 并触发 `FocusState` | `AppShellView.isTopSearchFocused` |
| 全局菜单 | `⌘,` | 打开 Settings | App menu command 读取 `runtime-settings.json` | `AppViewModel.performShortcutAction(.openSettings)` |
| Browser Workspace | `⌘L` | 聚焦地址栏 | Browser 局部 key monitor 读取 `runtime-settings.json` | `BrowserKeyboardShortcutResolver.focusAddress` |
| Browser Workspace | `⌘T` | 新建浏览器标签页并聚焦地址栏 | Browser 局部 key monitor 读取 `runtime-settings.json` | `BrowserKeyboardShortcutResolver.newTab` |
| Browser Workspace | `⌘W` | 关闭当前浏览器标签页,不是关闭 macOS 窗口 | Browser 局部 key monitor 读取 `runtime-settings.json` | `BrowserKeyboardShortcutResolver.closeSelectedTab` |
| Browser Workspace | `⌘[` | 后退 | Browser 局部 key monitor 读取 `runtime-settings.json` | `BrowserKeyboardShortcutResolver.goBack` |
| Browser Workspace | `⌘]` | 前进 | Browser 局部 key monitor 读取 `runtime-settings.json` | `BrowserKeyboardShortcutResolver.goForward` |
| Browser Workspace | `⌘⇧B` | 打开 / 关闭书签面板 | Browser 局部 key monitor 读取 `runtime-settings.json` | `BrowserKeyboardShortcutResolver.toggleBookmarks` |
| Browser Workspace | `⌘Y` | 打开 / 关闭历史面板 | Browser 局部 key monitor 读取 `runtime-settings.json` | `BrowserKeyboardShortcutResolver.toggleHistory` |
| Browser Workspace | `Esc` | 关闭网页选区 / 整页提问浮窗,并保留草稿 | 固定局部快捷键,不进入设置页 | `BrowserKeyboardShortcutResolver.closeSelectionPopover` |
| 附件预览 / 后台任务 / Inspector / Tool Overlay | `Esc` | 关闭当前 overlay / panel | 固定 SwiftUI `.keyboardShortcut` | `AgentChatView`, `AgentChatActivityViews`, `AgentToolInvocationDetailOverlay` |
| 标签 / 状态编辑弹窗 | Return | 保存 | 固定 default action | `SettingsLabelEditorSheet`, `SettingsStatusEditorSheet`, sidebar editor sheets |

快捷键修改能力已经落地到 `SettingsShortcutsSection`:用户点击“修改”后进入原生 recorder sheet,按下新组合键即可保存;配置写入 `runtime-settings.json` 的 `shortcuts.bindings`,并由菜单命令或 Browser Workspace key monitor 直接读取。低频治理/扩展入口（Graph Memory、Approvals、Data Sources、Skills、Automations、Local API / CLI、Commercial Readiness）不在快捷键设置页暴露,避免占用过多 `⌘` 数字键和高频键位。

实现注意事项:

- 不要只在 `SettingsShortcutsSection` 展示快捷键;必须同时在 `ConnorGraphAgentMacApp.commands`、局部 key monitor 或 SwiftUI `.keyboardShortcut` 中绑定,否则会形成“文档/设置页承诺但实际不可用”的商业体验缺口。
- `AgentRuntimeShortcutSettings` 是当前快捷键单一配置源;全局菜单和 Browser Workspace resolver 都应从它读取。
- Browser Workspace 的 `⌘W` 当前是局部 key monitor,需要继续保证只在 Browser Workspace 可见时拦截,避免破坏系统窗口关闭行为。
- 对 destructive / governance 动作不要设计单键直达执行;快捷键最多打开 review surface,实际执行仍由 Connor Policy Engine / reviewed gate 控制。

Session Workspace 当前支持:

- 每个 Connor Session 都可以拥有自己的 project workspace roots,随 Session Capsule 持久化,而不是依赖全局设置页里的单一工作目录。
- 一个会话可同时绑定多个 root:一个 `primary root` 作为相对路径基准和 Claude Sidecar cwd,其他 roots 作为 Connor Native local tools 的 additional allowed roots。
- 会话顶部的"当前会话 Workspace"区域支持查看 roots 摘要、输入路径、选择多个文件夹、添加 root、设为主目录和移除 root。
- composer 底部 folder badge 是高频入口:弹出列表直接展示当前 session roots,每个 root 都以 folder 图标呈现并限制最大宽度,过长路径用省略号截断,不使用 checkmark 制造单选列表错觉。
- 当前 roots 保持原先的"点击目录项即切换到该目录"交互,每行右侧额外提供一个小叉用于取消此工作目录;若取消的是当前 primary root,剩余的第一个辅助 root 会自动升级为 primary root。
- folder badge 的"历史打开列表"区域展示跨会话最近目录 MRU,每个历史项都以历史图标呈现并限制最大宽度;选择历史项会加入当前 session roots 并设为 primary,适合在相关项目之间快速切换。
- folder badge 还支持"选择文件夹..."和"重置为默认",用于从 Finder 添加新目录或回退到 legacy / fallback 默认工作目录。
- composer paperclip 现在导入 Session Capsule 附件;附件 chips 展示在现有 composer 文本框内部上半部分,文本框整体尺寸不变,composer 的尺寸、位置和外部布局不变。附件多时在文本框内部横向滚动,不在 composer 上方新增 shelf,也不推动底部按钮栏。点击附件 chip 主体会打开现有纯阅读预览弹窗;弹窗外层布局保持不变,内部对 PDF 使用 PDFKit 多页连续滚动原文件预览,对 Office/iWork/Presentation/Spreadsheet 和图片使用 macOS Quick Look / QuickLookUI 原生预览原文件,同时保留 Connor 的解析状态、manifest 路径和 retry 入口;点击 `xmark.circle.fill` 只移除附件。
- 多工作目录能力只作用于 project workspace / allowed roots;Connor 仍保持单一 Home / Runtime Root,不引入 Craft-style multi-workspace。

Agent tool invocation detail 当前支持:

- 对同一个 `callID` 下的 `toolRequested` / `toolApproved` / `toolStarted` / `toolFinished` / `toolFailed` 事件进行 Connor-owned 聚合,形成 `AgentToolInvocationPresentation`,避免点击工具活动时只打开最早的 `Tool requested` 事件。
- 工具活动行点击打开 Native SwiftUI `AgentToolInvocationDetailOverlay`,而底层事件列表仍保留原有 `AgentActivityDetailOverlay`,用于审计与调试。
- 详情面板分为 Summary、Input、Output、Metadata、Raw Event Index,可复制 input/output/callID,并显示 runID、sessionID、semantic kind、artifact/truncation metadata。
- Bash / swift build / swift test / git / python / node / package manager 等 shell-like 工具使用 terminal-style renderer,优先从 result JSON 展示 stdout、stderr、exitCode,否则回退到纯文本解析。
- Edit/Write 等文件变更类工具使用 `AgentToolChangePresentation` 提取 result JSON / arguments JSON / outputText 中的 unified diff、patch、oldText/newText,并由 SwiftUI 原生 diff renderer 高亮新增、删除和 hunk 行。
- MCP、Browser、Read/Grep/List 和未知工具使用原生 input/output card 与 JSON/text renderer;这是参考 Craft activity overlay 的信息架构,不是 Craft UI fork,也不引入 Electron/Web UI。
- `web_fetch` 的 `http/auto` 模式继续通过 search-engine-mcp 获取 cleaned Markdown/text;`js` 模式在 Connor App runtime 中优先走 Connor-owned WKWebView background runner,从渲染后的 DOM 抽取 title、final URL 与正文内容返回给 Agent,以保持 Native Shell 浏览器能力和 Agent 工具调用的一致治理边界;无 App UI handler 的 CLI/测试环境继续回退到 search-engine-mcp 的 JS 渲染路径。
- 大输出通过 `AgentToolOutputDisplayPolicy` 先做 preview/truncation 治理;当前不强制把超大 stdout/stderr 落 Session Capsule artifact,后续若需要再以独立 artifact policy 接入。

Browser Workspace 当前支持:

- SwiftUI + WKWebView 内置网页工作区
- 轻量多标签页标签栏;标签过多时先自动缩窄每个标签,达到最小宽度后再横向滚动
- 每个 Connor Session 拥有独立的浏览器标签页栈、选中文本浮窗、网页选择 mini-thread 记录和上次离开时的浏览器/对话视图模式
- 浏览器状态是 Session Capsule 的子状态,持久化到 `sessions/{sessionID}/browser/browser-state.json`
- 网页选择提问会同时追加到 `sessions/{sessionID}/state/records.jsonl`,作为会话记录流的一部分
- 每个标签页独立保留 URL、标题、加载状态和前进/后退 metadata;运行期 WKWebView 缓存在 UI 层,不跨重启持久化
- 地址栏输入 URL、域名或搜索词,按 Return 打开
- target=_blank / 新窗口导航自动打开为新标签页
- Browser Workspace 可见时,按 ⌘W 关闭当前选中的浏览器标签页,而不是关闭整个 macOS 窗口
- 从对话 transcript 中打开链接时,会写入当前会话的浏览器状态,追加并选中新标签页,同时更新地址栏目标
- 内置搜索服务需要浏览器时,可先通过隐藏的 Browser Background Task Runner 使用同一应用级 WebKit 存储在后台加载搜索页;若流程未遇到验证/安全挑战,则后台完成不切换用户界面;若检测到 CAPTCHA、人机验证、Cloudflare challenge 等卡点,则标记为 awaiting user intervention,并显式切换到对应浏览器标签页请用户处理
- `web_fetch(render_mode: "js")` 在 Connor App runtime 中优先使用内置 WKWebView background runner 加载 JavaScript 页面,并从渲染后的 DOM 抽取 title、final URL 与正文内容返回给 Agent;遇到 CAPTCHA、人机验证、Cloudflare challenge、登录或浏览器安全挑战时,会切换到对应内置浏览器标签页请求用户介入;无 App UI handler 的 CLI/测试环境继续回退到 search-engine-mcp 的 JS 渲染路径
- 地址栏右侧提供"问一问 AI"按钮,可基于当前网页全文打开与选区浮窗一致的整页 mini-thread 提问浮窗
- 用户在网页中选中文本后自动显示跟随选区的浮动窗口
- 浮窗会根据 Browser Workspace 可视区域自动翻转、平移并限制最大高度,避免在窗口边缘、小窗口或长 mini-thread 场景下显示不全
- 浮窗可基于选中文本提问、插入主对话输入框或保存为 Graph Evidence episode
- 浮窗打开时按 Esc 可关闭浮窗并保留当前输入草稿,便于稍后重新打开继续编辑
- 浮窗发送按钮复用主对话 composer 的原型发送按钮样式
- 发送给 LLM 后浮窗保持打开,局部 mini-thread 显示 loading 状态、用户提问与 assistant Markdown 回复
- 同一次网页选区提问也会同步进入主会话 transcript:主会话显示简洁可读的"网页选区提问",LLM 实际接收完整网页上下文

Command Palette 当前支持:

- command / destination entries
- group metadata
- risk badge
- primary action marker
- shortcut search
- keyword search
- empty state

当前 command examples:

```text
Open Home
New Session
Open Automations
Open Local API / CLI
Open Sources
Open Skills
Open Browser Workspace
Open Settings
```

Deep-link resolver 文件:

```text
Sources/ConnorGraphAppSupport/ConnorDeepLinkNavigator.swift
```

支持 URL 形态:

```text
connor://open/{destination}
connor://open/{destination}?focus={focusID}
```

示例:

```text
connor://open/home
connor://open/sources
connor://open/automation?focus=history
connor://open/browserWorkspace
```

---

## Settings Center

设置入口位于 System / Settings。设置中心由中间栏分类列表和右侧设置详情组成,不包含项目工作目录编辑器:Workspace Roots 属于每个会话,在会话界面顶部的"当前会话 Workspace"中设置。Connor 仍是单一 Home / Runtime Root,不引入 Craft-style multi-workspace。AI 配置采用 Craft-style 多连接模型:Settings Center 中的 AI 设置保存多个 `llmConnections`,每个连接有自己的名称、协议类型、模型列表、endpoint / sidecar 配置和凭据;全局 `defaultConnectionID` 作为新会话默认连接。每个会话仍可通过 composer 底部的模型选择器覆盖为某个具体连接里的某个模型;切换会话时自动恢复该会话的模型配置。API Key 始终存储在本地加密凭据仓库/Keychain 等 credential store 中,不写入 JSON 设置文件。

当前设置分类:

```text
应用
AI
外观
输入
权限
标签
状态
快捷键
偏好
```

权限设置页必须贴合当前 Connor 真实运行边界,不要把它设计成系统隐私权限页、团队权限页或完整安全策略编辑器。当前 `SettingsPermissionsSection` 的真实职责是 **新会话默认 Policy Engine 模式 + 真实生效边界说明**;会话运行中的权限调整仍在 composer 底部权限 badge 完成;每个会话的 Workspace Roots 仍在会话界面设置,不回流到 Settings Center。

权限设置页采用三块信息结构:

1. **新会话默认权限**
   - 主控件:`新会话权限` picker / segmented control,只展示 `只读`、`询问`、`执行`,继续隐藏 `allowAll`。
   - 文案说明:该设置写入 `runtime-settings.json` → `loop.permissionMode`,用于创建或重建新会话的 `NativeSessionManager` 默认权限;当前正在运行的会话可以通过 composer 权限 badge 临时调整。
   - 三种模式需要用用户语言解释:
     - `只读`:允许读取图谱、会话、workspace 文件、搜索文件、只读 shell、模型调用和本地科学计算;拒绝写入、删除、外部网络和危险 shell。
     - `询问`:读取、普通模型调用、graph write proposal、外部网络默认允许;文件写入/编辑/删除、graph commit/删除、昂贵模型调用、workspace/network/destructive shell 进入审批。
     - `执行`:文件写入/编辑、graph commit、workspace shell 可自动通过;图谱删除、文件删除、network shell、destructive shell 和昂贵模型调用仍需审批。
2. **当前真实生效**
   - 不展示 `网络访问需要审批` / `Shell 写入需要审批` toggle,因为这两个字段目前只是历史持久化字段,不是完整接入 Policy Engine 的真实开关。
   - 网络访问默认不单独审批:`AgentRuntimePermissionSettings.requireApprovalForNetwork` 默认值为 `false`;在 `询问` / `执行` 模式下,`externalNetwork` 当前由 `AgentPolicyEngine` 默认通过;在 `只读` 模式下仍会拒绝。
   - Shell 不用全局 toggle 控制,而是由 `LocalShellCommandPolicy` 分类为 readOnly / workspaceWrite / network / destructive / unknown 后映射到 capability,再交给 `AgentPolicyEngine` 决策。
3. **不可在设置页放开的安全边界**
   - 不提供 `全部允许 / allowAll` 开关。Claude SDK sidecar 的 `bypassPermissions` 只是让 Connor Policy Engine 成为唯一审批层,不代表产品层无限制授权。
   - 不在权限页管理 Workspace Roots。用户必须到会话顶部的"当前会话 Workspace"配置 primary root / additional roots;Settings Center 只提示这个入口。
   - 不在权限页编辑 protected paths、MCP per-tool policy、graph admission policy 或 automation reviewed gate。这些属于后续高级治理页或各自领域页面。
   - 不做团队成员/组织角色权限。Connor 当前是本地单用户 Home / Runtime Root,明确不做 multi-user permissions。

界面布局已按当前 Settings Center 卡片风格落地:顶部标题"权限"居中;内容最大宽度 760;`SettingsPermissionsSection` 先展示页面说明,再用 `新会话默认权限` 卡片承载权限模式 picker 和当前模式摘要,用 `当前真实生效` 卡片说明权限模式、网络和 Shell 的实际决策来源,用 `安全边界` 卡片说明不开放 allowAll、Workspace 属于会话、本地单用户边界。能力矩阵说明放入可折叠的"查看当前策略说明" disclosure,默认不展示工程化 capability 表,以符合 Apple 设置页只暴露必要选项的原则。

会话侧栏的"所有会话"状态列表和"标签"列表支持 macOS 右键菜单:状态项可"编辑状态…"或"创建状态…",标签项可"编辑标签…"或"创建标签…"。状态创建/编辑只面向显示名和图标;UID 是系统主键,创建时自动生成不重复的 `status_<uuid>`,编辑时只读展示、不可修改;排序和终态不暴露在弹窗中。状态图标使用常用 SF Symbol 菜单选择器。标签创建/编辑只面向显示名和颜色;UID 是系统主键,创建时自动生成不重复的 `label_<uuid>`。标签色彩选择使用 SwiftUI 原生 `ColorPicker("颜色", selection:..., supportsOpacity: false)`,保存时兼容旧命名色并可写入十六进制颜色。以上操作写入 `config/session-governance.json`,并立即刷新当前 AppViewModel、会话标签菜单、侧栏筛选计数和 automation governance mirror。当前底层会话状态仍由内置 `AgentSessionStatus` 枚举约束;因此自定义状态定义先作为治理配置维护能力落地,真正把任意自定义状态用于会话状态切换需要后续将 session status storage 从 enum 升级为 string-backed status ID。

核心视图:

```text
ConnorSettingsDetailView
SettingsAppSection
SettingsAISection
SettingsAppearanceSection
SettingsInputSection
SettingsPermissionsSection
SettingsLabelsSection
SettingsShortcutsSection
SettingsPreferencesSection
```

设置持久化文件:

```text
Sources/ConnorGraphAppSupport/AppRuntimeSettingsRepository.swift
Sources/ConnorGraphAppSupport/AppLLMSettingsRepository.swift
```

`AgentRuntimeSettings` 当前包含:

```text
schemaVersion
loop
ui
app
appearance
input
permissions
workspace
preferences
updatedAt
```

Agent loop 默认运行边界:

```text
maxToolIterations: 64
maxToolCallsPerIteration: 4
maxRunDurationSeconds: 180
maxToolResultBytes: 32768
allowParallelToolCalls: false
```

因此单轮 agent run 默认最多允许 64 个 tool iteration;每个 iteration 最多消费 4 个 tool calls,理论工具调用上限为 256 次。模型提前给出 final answer 时会提前结束;达到最大 iteration 后 run 会以 `maxToolIterationsReached` 失败。

### Native Local Workspace Tools

Connor 原生 AgentLoop 注册一组由 Connor 自己治理的本地 workspace 工具,而不是依赖 Claude SDK sidecar 才能读写文件。这使 OpenAI-compatible / 国产模型 / 私有模型也能在 Connor Policy Engine 下理解和修改本地项目。

```text
Read       readWorkspaceFile       读取 workspace 内文本文件,支持 offset/limit 和大文件限制
LS         listWorkspaceFiles      列出 workspace 内目录,目录以 / 结尾
Glob       listWorkspaceFiles      在 workspace 内执行 glob 文件发现,默认跳过 .git/node_modules/.build 等噪音目录
Grep       searchWorkspaceFiles    在 workspace 内执行 literal/regex 搜索,支持 context 和结果截断
Write      writeWorkspaceFile      创建或覆盖 workspace 内文本文件,受 protected path 和大小限制保护
Edit       editWorkspaceFile       对唯一 old_text 做精确替换;缺失或多重匹配会失败
MultiEdit  editWorkspaceFile       对单文件执行原子多重替换;任一 edit 无效则不写入
Bash       dynamic shell capability 在 workspace 内执行非交互命令,按命令风险追加评估 shell capability
```

本地 workspace 安全边界由 `LocalWorkspacePolicy` 负责。Project workspace 由 `AppProjectWorkingDirectoryResolver` 统一解析:Native AgentLoop 本地工具使用 primary root 作为相对路径基准,并把其他可见 roots 作为 additional allowed roots;同时运行时会额外注入一个不出现在用户界面上的 hidden allowed root:Connor 自己的 `AppStoragePaths.applicationSupportDirectory`。这个隐藏根目录允许用户通过和 AI 对话来添加 / 修改 skills、MCP sources、automations、labels、statuses 和配置文件,但不会污染会话顶部的 Workspace Roots UI。Governed Claude Sidecar 仍使用同一个 primary root 作为单一 cwd。

```text
1. Session Capsule workspace roots / session override
2. runtime-settings.json workspace.roots primary root
3. legacy runtime-settings.json workspace.defaultWorkingDirectoryPath + additionalAllowedDirectoryPaths
4. legacy llm-settings sidecarWorkingDirectoryPath
5. process currentDirectoryPath fallback
```

- 默认项目目录推荐写入当前会话的 `sessions/{sessionID}/state/session-state.json` → `workspace.roots`;每个 root 包含 `id`、`displayName`、`path`、`role` 和 `isPrimary`。
- `runtime-settings.json` 中的 `workspace.defaultWorkingDirectoryPath`、`workspace.additionalAllowedDirectoryPaths`、`workspace.roots` 保留为旧配置兼容 fallback / 新会话初始模板,不再是 UI 主设置;`workspace.recentWorkspacePaths` 仅保存跨会话最近打开目录 MRU 列表,默认最多 8 个。
- 会话界面的"当前会话 Workspace"控件支持选择多个目录、添加路径、设为主目录、移除 root;composer folder badge 额外提供当前 roots 快速列表、行内小叉取消入口和"历史打开列表"区域,点击历史项会加入当前 session roots 并设为 primary。
- Claude Sidecar 的 cwd 仍只能是一个目录,因此使用 primary root;其他可见 roots 是 Connor Native tools 的允许根。
- Connor Native tools 还拥有隐藏的 Connor 数据存储允许根,指向 `~/Library/Application Support/Connor` 或测试/自定义环境中的 `AppStoragePaths.applicationSupportDirectory`;它不参与 UI 展示、不成为 primary root,仅用于 AI 对话式维护 Connor 自身数据。
- `llm.sidecar.workingDirectoryPath` 保留为旧配置兼容 fallback,不再是唯一 Sidecar cwd 来源。
- 所有路径会做标准化和 symlink resolving,防止 workspace 内 symlink 逃逸到系统目录。
- 默认拒绝 workspace 外路径、`.git/objects` / `.git/index` 写入、`.env*` 写入、`~/.ssh` / `~/.gnupg` / `~/.aws` 等敏感路径。
- 文件读取、写入、搜索和工具输出都有大小/数量上限,避免大结果污染模型上下文。
- 工具结果回灌给下一轮模型时遵循正文优先规则:`AgentToolResult.contentText` 是 LLM 主要可读结果,例如 Bash 的 `stdout`/`stderr`、Read 的文件内容、Grep 的匹配行;`contentJSON` 是审计/结构化 metadata,只有当 `contentText` 为空时才作为 fallback,不能覆盖真实工具输出。
- `Edit` 要求 `old_text` 在原始文件中唯一匹配;`MultiEdit` 先完整验证全部 edits,再一次性写入,避免部分修改。
- `Bash` 使用保守命令分类:`readOnly`、`workspaceWrite`、`network`、`destructive`、`unknown`。明确 destructive 命令直接拒绝;其他风险类型映射到对应 shell capability,由 `AgentPolicyEngine` 按 permission mode 决策。

新增本地 workspace 权限 capability:

```text
readWorkspaceFile
listWorkspaceFiles
searchWorkspaceFiles
writeWorkspaceFile
editWorkspaceFile
deleteWorkspaceFile
runReadOnlyShellCommand
runWorkspaceShellCommand
runNetworkShellCommand
runDestructiveShellCommand
computeScientific
```

### Scientific Compute Runtime

Connor 原生 AgentLoop 现在有一个商用级 Scientific Compute Runtime 骨架,而不是把模型暴露给任意 eval / shell / Python 代码。模型只能通过声明式 operation JSON 调用白名单计算能力;结果带 `engine`、`method`、`tolerance`、`warnings`、`elapsedMilliseconds` 等 diagnostics,便于审计、复现和后续多引擎路由。

当前注册工具:

```text
science_compute        computeScientific    通用科学计算入口:算术、比较、单位、统计、小型线代
science_units          computeScientific    单位换算与量纲校验入口,当前委托 Native runtime
science_stats          computeScientific    统计入口,当前委托 Native runtime
science_linalg         computeScientific    线性代数入口,当前委托 Native runtime
science_symbolic       computeScientific    符号数学入口;等待 Python/SymPy sidecar engine
science_optimize       computeScientific    优化入口;等待 SciPy/Accelerate engine
science_table_compute  computeScientific    表格科学计算入口;等待 DataFrame/table engine
```

当前 Native Swift engine 是 always-on reliability core,覆盖:

```text
add / subtract / multiply / divide
compare / equal / not_equal / greater_than / less_than / greater_than_or_equal / less_than_or_equal
approximate equality via absolute_tolerance / relative_tolerance
summary statistics: count / sum / mean / median / min / max / sample_standard_deviation
unit_convert: m / cm / km / s / min / h / m/s / km/h
solve_linear_system for small square systems via Gaussian elimination with pivoting
```

比较大小是一级能力,不允许把浮点 `==` 静默伪装成可靠事实。若浮点相等/compare 没有显式 tolerance,Native engine 会在 diagnostics warnings 中记录 `Floating equality used without explicit tolerance policy.`。带单位比较和更完整单位制、符号正负判断、高精度 decimal/rational、概率分布、优化、积分、ODE、SVD/eigen 等属于后续 Python Scientific Sidecar / Accelerate engine 扩展范围。

`computeScientific` 是纯本地确定性计算 capability,在 read-only / ask-to-write / trusted-write / allow-all 下默认批准;它不读写 workspace、不访问网络、不 shell out。

AI 设置页支持:

- 多个 AI 连接,而不是把 AI 设置硬编码成两类全局源
- 每个连接都有稳定 provider kind:`openAICompatible`、`claudeSidecar`、`chatGPTCodex`、`githubCopilot`、`anthropicCompatible`;旧设置若没有 provider kind,会按 `providerMode` 兼容迁移为 OpenAI Compatible 或 Claude Sidecar
- Add Connection 现在走 Connor 原生 `AppLLMConnectionSetupService`:先校验 provider-specific input,再执行真实 health check / sidecar validation,成功后才保存 metadata 和 credential;失败不会追加假连接,也不会污染 credential store
- OpenAI Compatible / 本地模型走 Connor 原生 `OpenAICompatibleProvider`;用户填写 Base URL、模型和 API Key,本地 localhost 模型可使用本地占位 token,但仍会发起真实 health check;OpenAI-compatible 认证头支持默认 `Authorization: Bearer` 和部分国内服务商需要的 `api-key` 模式
- Anthropic Compatible 走 Connor 原生 `AnthropicCompatibleProvider`:使用 Anthropic Messages API `/v1/messages`,支持官方 `x-api-key` 认证和 OpenRouter / Vercel 等代理常见的 Bearer 认证;文本回复、`tool_use` / `tool_result` 映射、health check、SSE streaming、extended thinking request options、prompt cache request options、server tool request schema、fine-grained tool streaming 的 partial JSON 累积与容错均在 Swift HTTP/SSE provider 内完成;它面向 API Key / Endpoint 服务商,不复用 Claude SDK sidecar 的账号登录 runtime
- Claude 连接走 Claude SDK sidecar:验证 sidecar executable 存在且可执行,禁止 `allowAll`;OAuth token 保存到 credential store,运行 sidecar 时通过 `CLAUDE_CODE_OAUTH_TOKEN` / refresh token 环境变量注入,不让 Claude SDK 拥有 Connor session / permission / audit / graph state
- Codex · ChatGPT Plus 连接走 ChatGPT/Codex OAuth:浏览器回调拿到 OAuth tokens,再用 `id_token` token-exchange 派生 OpenAI API key,随后复用 Connor 原生 OpenAI-Compatible runtime 做真实 health check;OAuth tokens 和派生 API key 都只进 credential store
- GitHub Copilot 连接走 GitHub device flow:拿到 Copilot token 后构造 Connor 原生 HTTP runtime config,补充 Copilot integration headers,并用 chat/completions health check 验证后才保存
- DeepSeek 和 Xiaomi MiMo 作为 Add Connection 一等入口:DeepSeek 默认 `https://api.deepseek.com`,可在 `deepseek-v4-flash` / `deepseek-v4-pro` 中选择模型;Xiaomi MiMo 默认 `https://api.xiaomimimo.com/v1`,可在 `mimo-v2.5-pro` / `mimo-v2.5` / `mimo-v2-omni` / `mimo-v2-flash` 中选择文本生成模型,并按官方 OpenAI 示例使用 `api-key` 请求头;这些特定入口隐藏连接名、Endpoint 和 raw model 输入,只让用户选择模型并填写 API Key
- "中国常用模型"入口使用 curated provider 表单,内置阿里百炼/Qwen、火山方舟/豆包、Moonshot/Kimi、智谱 GLM、MiniMax、阶跃星辰等国内 OpenAI-compatible 服务商;用户选择服务商与模型并填写 API Key,Endpoint 和认证头由 preset 管理;只有"使用其他提供商"保留 Endpoint、Protocol 和 raw model 高级自定义字段
- 每个连接拥有独立名称、模型列表、selected model、Base URL / Sidecar 配置;API Key / OAuth token 不会明文写入 JSON 设置文件
- 全局默认连接用于新聊天;composer 模型选择器可把单个会话覆盖到某个具体连接的某个模型
- 默认权限、外观、输入和用户偏好
- 当前会话 Workspace 在会话界面内设置,不在 Settings Center 中设置

注意:部分设置已完成本地持久化,但尚未全部接入实际运行时行为,例如桌面通知、保持屏幕常亮、外观模式实时切换、输入框拼写检查和网络 / Shell 审批细粒度 enforcement。

---

## Hybrid Graph Retrieval and Evaluation

统一检索接口:

```text
GraphHybridSearchService
```

SQLite 实现:

```text
SQLiteGraphHybridSearchService
```

当前检索组成:

- Entity FTS
- Statement FTS
- Episode FTS
- Source episode expansion
- Bounded multi-hop graph expansion
- Candidate pool multiplier
- Local lexical overlap reranking
- Statement endpoint context boost
- Statement confidence boost
- Episode mention boost
- Optional MMR diversity reranking
- Retrieval pipeline metadata
- Matched terms metadata
- Rerank reasons metadata
- Graph hop metadata
- Graph context entity IDs metadata

Retrieval evaluation 持久化路径:

```text
graph/evaluations/retrieval-evaluation-cases.json
graph/evaluations/reports/*.json
```

支持指标:

```text
Precision@k
Recall@k
HitRate@k
Mean Reciprocal Rank
Average Precision
nDCG@k
RequiredHitRate@k
```

---

## Commercial Readiness Gate

Commercial Readiness 当前覆盖 6 个 phase:

```text
Phase 1 · Session OS / Governance
Phase 2 · Claude SDK Sidecar Runtime
Phase 3 · Source / MCP Platform
Phase 4 · Graph Memory Core Capability
Phase 5 · Native Commercial UI
Phase 6 · Local API / CLI / Automation Surface
```

Readiness Gate 聚合:

- Session runs / journal / pending plan / branch / restore snapshot evidence
- Claude sidecar runtime / diagnostics / permission sovereignty evidence
- Source health / discovery / tool catalog / audit / graph write policy evidence
- Graph Memory context / ingestion / distillation / review evidence
- Native UI home / runtime center / command palette / settings evidence
- Local API / CLI endpoint / command / dry-run / reviewed gate / audit / local-only evidence

关键文件:

```text
Sources/ConnorGraphAppSupport/CommercialReadinessGate.swift
Sources/ConnorGraphAppSupport/ConnorNativeCommercialUIPresentation.swift
```

---

## Build, Test and CLI Smoke

Build:

```bash
cd /Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac
swift build
```

Product builds:

```bash
swift build --product connor-graph-agent-mac
swift build --product connor
```

Test:

```bash
swift test
```

CLI smoke:

```bash
swift run connor commands
swift run connor readiness
swift run connor automations evaluate --trigger sessionStatusChanged --session demo --status needs_review --dry-run
```

最近验证结果:

```text
Project Working Directory Runtime targeted tests passed (2026-06-14 01:00 GMT+8):
- swift test --filter runtimeSettingsRepositoryPersistsWorkspaceRoots
- swift test --filter AppProjectWorkingDirectoryResolverTests
- swift test --filter sessionStatePreservesWorkspaceReference
- swift test --filter sessionStatePreservesWorkspaceRootReferences
- swift test --filter appGraphAgentRuntimeFactoryConfiguredSidecarUsesRuntimeWorkspaceBeforeLegacySidecarWorkspace
- swift test --filter agentLoopRuntimeFactoryNativeReadUsesRuntimeWorkspace
- swift test --filter agentLoopRuntimeFactoryNativeReadAllowsAdditionalWorkspaceRoot
- swift test --filter LocalWorkspacePolicyTests
- swift test --filter LocalWorkspaceToolsTests

Native local workspace tool targeted tests passed (2026-06-13 23:31 GMT+8):
- swift test --filter LocalWorkspacePolicyTests
- swift test --filter LocalWorkspaceToolsTests
- swift test --filter LocalShellCommandPolicyTests
- swift test --filter AppGraphAgentRuntimeFactoryLocalToolsTests
- swift test --filter CommercialReadinessReleaseGateTests

Scientific Compute Runtime targeted tests passed (2026-06-14 01:26 GMT+8):
- swift test --filter ScientificComputeRuntimeTests
- swift test --filter agentLoopRunsScientificToolThenFinalAnswer
- swift test --filter agentLoopRuntimeFactoryRegistersScientificComputingTools

Targeted regression status on optimize/chat-ui-first-pass after first-pass cleanup (2026-06-14 13:35 GMT+8):
- swift test --filter AgentChatPresentationTests: passed.
- swift test --filter ClaudeSDKSidecarBackendTests: passed.
- swift test --filter PhaseGCraftGradeNativeUITests: passed.
- swift test --filter NativeSessionManagerTests: passed.
- The previous UI copy expectation mismatch has been resolved by aligning the native shell title expectation with the localized product name `康纳同学`.

P1/P2 combined optimization final targeted regression status (2026-06-14 14:10 GMT+8):
- swift test --filter AgentChatPresentationTests: passed, 12 tests.
- swift test --filter ClaudeSDKSidecarBackendTests: passed, 22 tests.
- swift test --filter NativeSessionManagerTests: passed, 11 tests.
- swift test --filter PhaseGCraftGradeNativeUITests: passed, 3 tests.
- swift test --filter CommercialReadinessReleaseGateTests: passed, 4 tests.
- SwiftPM `Assets.xcassets` unhandled-file warning is resolved by declaring `.process("Assets.xcassets")` on the mac app executable target.

Settings labels/statuses redesign regression (2026-06-16 19:01 GMT+8):
- 设置导航新增“状态”页面;“标签”和“状态”现在分别作为低频全局治理配置入口,符合 Apple HIG settings guidance:减少设置数量、按相关项分组、只暴露用户需要调整的选项。
- 设置 → 标签已重写为纯标签管理:列表行显示颜色、图标、显示名和使用数量;新建/编辑 sheet 只允许修改显示名、图标和颜色;不暴露 ID、value type、value、graph binding 或校验字段。
- 设置 → 状态新增完整管理页:列表行显示图标、显示名和使用数量;新建/编辑 sheet 只允许修改显示名和图标;不暴露 ID、sort order 或 terminal-state。
- 页面采用 Apple HIG layout/buttons 要点:相关项分组、顶部主操作、44×44 pt 图标/删除按钮命中区域、主要操作 prominent、破坏性操作 destructive、打开编辑视图的按钮使用省略号。
- 删除行为复用治理层规则:删除标签会从所有会话移除;删除状态会在最后一个状态或仍有会话使用时被阻止。
- swift build: passed.
- swift test --filter ProductOSPhase1Tests: passed, 5 tests.

Session title / deletion guard regression (2026-06-16 18:49 GMT+8):
- 首轮发送后的自动标题生成从 `onRunStarted` 调整为 submit 成功、首条用户消息已持久化后触发,避免标题任务读取到空会话或旧会话导致不稳定。
- `renameChatSession` 在 repository rename 后立即同步 `chatSessions`、`allChatSessions`、`fallbackChatSession` 和 `nativeSessionManager`,再 reload,保证会话列表和详情页标题同步。
- 会话存在 queued/running 后台任务时不允许删除;列表 swipe/context menu 删除入口禁用,`deleteChatSession` 删除前也重新读取持久化后台任务做强制兜底。
- swift build: passed.
- swift test --filter NativeSessionManagerSessionOSTests / ProductOSPhase1Tests: app target compiled, but package test linking failed with pre-existing undefined symbols for `AgentModelUsage.init` / `AgentModelResponse.init` in broader test bundle.

Status / label context menu targeted regression (2026-06-16 17:33 GMT+8):
- 状态创建/编辑不再要求用户提供英文 ID;侧栏创建入口自动生成不重复 `status_<uuid>`,保存层对空/重复新状态 ID 也有 UID 兜底。
- 状态弹窗只保留显示名和图标;排序、终态不再暴露,图标由常用 SF Symbol 菜单选择器提供。
- 标签模型已收敛为纯标签:系统生成 UID、显示名、颜色;删除 value type、标签值校验、graph binding 以及 UI 中的值类型/图谱绑定编辑入口。
- 创建标签不再要求用户提供英文 ID;侧栏创建入口自动生成不重复 `label_<uuid>`,保存层对空/重复新标签 ID 也有 UID 兜底。
- 标签颜色编辑使用 SwiftUI 原生 `ColorPicker("颜色", selection: ..., supportsOpacity: false)`,兼容旧 named colors,保存新选择为十六进制颜色。
- swift test --filter ProductOSPhase1Tests: passed, 5 tests.
- swift test --filter NativeSessionManagerSessionOSTests: passed, 8 tests.
- SwiftPM debug build completed while compiling `AgentSessionGovernance.swift`, `AppSessionGovernanceConfigRepository.swift`, `AppShellViews.swift`, `ConnorGraphAgentMacApp.swift`, `ConnorSettingsViews.swift`, `ProductOSRegistryViews.swift`, and `AgentChatView.swift`.
```

---

## Test Coverage Highlights

重要商业化测试:

```text
Tests/ConnorGraphAppSupportTests/NativeSessionManagerSessionOSTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain2ClaudeSDKSidecarTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain3SourceMCPPlatformTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain4GraphMemoryCoreTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain5NativeUICommercializationTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain6LocalAPICLIAutomationSurfaceTests.swift
```

其他关键测试:

```text
Tests/ConnorGraphAgentTests/AgentLoopControllerTests.swift
Tests/ConnorGraphAgentTests/AgentContextBuilderSQLiteSearchTests.swift
Tests/ConnorGraphAgentTests/LocalWorkspacePolicyTests.swift
Tests/ConnorGraphAgentTests/LocalWorkspaceToolsTests.swift
Tests/ConnorGraphAgentTests/LocalShellCommandPolicyTests.swift
Tests/ConnorGraphAgentTests/ScientificComputeRuntimeTests.swift
Tests/ConnorGraphAppSupportTests/AppGraphAgentRuntimeFactoryLocalToolsTests.swift
Tests/ConnorGraphAppSupportTests/AppGraphAgentRuntimeFactoryNativeSessionManagerTests.swift
Tests/ConnorGraphAppSupportTests/NativeSessionManagerBackendTests.swift
Tests/ConnorGraphAppSupportTests/CommercialReadinessGateTests.swift
Tests/ConnorGraphAppSupportTests/CommercialReadinessRuntimeCenterTests.swift
Tests/ConnorGraphAppSupportTests/CommercialReadinessSnapshotBuilderTests.swift
Tests/ConnorGraphAppSupportTests/CommercialReadinessReleaseGateTests.swift
Tests/ConnorGraphAppSupportTests/PhaseGCraftGradeNativeUITests.swift
```

---

## Historical Phase Ledger

早期阶段性增量:

```text
Phase A: Runtime Foundation Hardening
Phase B: Claude SDK Production Sidecar
Phase C: MCP / Source Runtime
Phase D: Skills Runtime
Phase E: Automation Engine
Phase F: Graph Memory Productization
Phase G: Craft-grade Native UI
Phase H: Source / Skill / Automation UI Integration
Phase I: Command Palette / Deep-link Navigation / Runtime Click-through
```

商业化列车:

```text
Commercial Train 1: Session OS Maturation
Commercial Train 2: Claude SDK Sidecar Productionization
Commercial Train 3: Source / MCP Platformization
Commercial Train 4: Graph Memory as Agent Core Capability
Commercial Train 5: Native UI Commercialization
Commercial Train 6: Local API / CLI / Automation Surface
```

已知合并/阶段提交:

```text
Phase A: e0b6f27
Phase B: ad18b8f
Phase C: fa72f43
Phase D: 23f5776
Phase E: 829d130
Phase F: 9c77c85
Phase G: 0f9c99e
Phase I: 7d17ef8
Commercial Train 1 merge: df44381
Commercial Train 2 merge: ef876c6
Commercial Train 3 merge: c82db5a
Commercial Train 4 merge: c3265d1
Commercial Train 5 merge: 492ea1f
Commercial Train 6 branch commit: 9a3945a
Agent loop depth tuning: 9c938d6
Native local workspace tools Phase 1: 1492295
Native local workspace tools Phase 2: ee20c7e
Native local workspace tools Phase 3: 524d1c6
Native local workspace tools Phase 4: 47200e3
Native local workspace tools Phase 5: 6890998
```

Phase H 在 main 历史中体现为:

```text
05457b3 Phase H add source runtime UI presentation
b011671 Phase H add skill runtime UI presentation
84271e6 Phase H wire automation source and skill UI panels
```

---

## Deferred Scope

当前仍刻意延后:

- Public remote API
- Remote daemon / cloud sync
- OAuth server / team auth / multi-user permissions
- Full REST framework or default long-running local server
- Real macOS Shortcuts app integration
- App Store packaging / notarization / Sparkle updater
- Team billing / remote collaboration
- Full onboarding walkthrough
- Full theme editor / design system rewrite
- External Graphiti / Neo4j / Mem0 / Letta integrations
- Autonomous unreviewed graph writes
- Complex temporal conflict resolution UI
- Multi-agent shared memory protocol
- Multi-workspace runtime

---

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE) for details.
