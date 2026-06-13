# Connor Graph Agent Mac

文档更新时间：2026-06-13 13:53 GMT+8  
当前代码基线：`feature/browser-tabs`，基于 `main` 继续演进 Session Capsule 持久化、内置浏览器多标签页与网页选区浮窗能力。

Connor Graph Agent Mac 是一个 Swift / SwiftUI macOS 应用和 SwiftPM package，目标是把 Connor 建成 **graph-memory-native Agent OS**：它不是“图谱编辑器”，也不是“Claude SDK 外壳”，而是以 Session OS、Policy Engine、Graph Memory、Source/MCP Platform、Native UI 和 Local Automation Surface 共同构成的本地 Agent 操作系统。

核心产品判断：**图谱是后台记忆基础设施，不是前台主导航概念。** 普通用户面对的是会话、数据源、技能、自动化、设置和本地 CLI/API 控制面；Graph Memory 在后台提供连续性、精确性、可追溯性和治理证据。

---

## Product Boundaries

Connor 当前坚持以下主权边界：

- **Session sovereignty belongs to Connor Session OS**：会话、run、journal、pending plan、branch、restore snapshot 由 Connor 持久化与恢复。
- **Permission sovereignty belongs to Connor Policy Engine**：Claude SDK sidecar 和 MCP servers 都不能绕过 Connor 审批、审计和执行门禁。
- **Memory sovereignty belongs to Connor Graph Memory**：对话 LLM 不直接写图谱；Graph Memory 写入走 staging、distillation、candidate review、admission policy 与 SQLite temporal graph。
- **Source sovereignty belongs to Connor Source Platform**：MCP servers 是外部能力提供者，不拥有 Connor source registry、permission policy、audit、graph ingestion policy 或 readiness state。
- **UI sovereignty belongs to Swift Native Shell**：不 fork Craft UI，不引入 Electron/Web UI，不引入 Craft-style multi-workspace。
- **Automation sovereignty belongs to Connor Local Automation Surface**：CLI/API 只能通过本地、可审计、可 dry-run、可 review 的 contract 调用 Connor runtime。

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
Unreviewed automation execution bypass
```

---

## Package Information

```text
Package name: ConnorGraphAgentMac
Swift tools version: 6.0
Platform: macOS 14+
System libraries/frameworks: sqlite3, Security, WebKit
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

Source targets：

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

Test targets：

```text
Tests/ConnorGraphCoreTests
Tests/ConnorGraphMemoryTests
Tests/ConnorGraphStoreTests
Tests/ConnorGraphSearchTests
Tests/ConnorGraphAgentTests
Tests/ConnorGraphAppSupportTests
```

Sidecar directory：

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

Session Capsule / artifact directories：

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
├── exports/
└── logs/
```

Connor 的会话持久化边界是完整 Session Capsule：SQLite 仍承担 session / run / event / graph 查询存储，但 session-local 的 UI/workspace 状态、记录流、附件、plans、data、logs 与 browser 子状态都归属于 `sessions/{sessionID}/`。`records.jsonl` 使用单行 JSONL 追加保存，读取时可跳过坏行，避免 10+ 条记录因一次异常写入或重启退化成 1 条。

主要状态文件：

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

`runtime-settings.json` 保存应用、外观、输入、权限、UI 和用户偏好类设置；`llm-settings.json` 保存模型提供方、Base URL、模型名和 Claude Sidecar 配置。API Key 不写入 JSON，由本地 Keychain 凭据仓库管理。

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

领域模型 target。包含：

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

关键文件：

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

记忆管线 target。包含：

- Observe log
- Memory ingestion
- Memory staging buffer
- Memory distillation
- LLM-backed memory distillation interface
- Promotion candidate model
- Constraint validation
- Contradiction detection

关键文件：

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

SQLite 持久化和后台 worker target。包含：

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

关键文件：

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

图谱检索和检索评估 target。包含：

- Graph search query / hit / response types
- Hybrid graph search service protocol
- Reranking config
- Embedding provider protocol
- Retrieval evaluation cases, judgments, hits, metrics and reports
- Retrieval evaluation harness

关键文件：

```text
Sources/ConnorGraphSearch/GraphSearch.swift
Sources/ConnorGraphSearch/GraphHybridSearch.swift
Sources/ConnorGraphSearch/EmbeddingProvider.swift
Sources/ConnorGraphSearch/GraphRetrievalEvaluation.swift
```

### ConnorGraphAgent

Agent runtime target。包含：

- Agent backend abstraction
- Type-erased backend
- Model provider abstraction
- OpenAI-compatible provider
- Tool-calling loop
- Graph read tools
- Graph write tools
- Web/search tools
- Permission policy
- Prompt budget estimation and inspection
- Session summary strategy
- Agent event recorder and replayer
- Text delta buffering
- Runtime usage tracking
- Graph Memory core runtime contract

关键文件：

```text
Sources/ConnorGraphAgent/GraphAgentBackend.swift
Sources/ConnorGraphAgent/AnyAgentBackend.swift
Sources/ConnorGraphAgent/AgentLoopController.swift
Sources/ConnorGraphAgent/GraphMemoryCoreRuntime.swift
Sources/ConnorGraphAgent/AgentTool.swift
Sources/ConnorGraphAgent/GraphReadTools.swift
Sources/ConnorGraphAgent/GraphWriteTools.swift
Sources/ConnorGraphAgent/AgentPermission.swift
Sources/ConnorGraphAgent/AgentEvent.swift
Sources/ConnorGraphAgent/AgentEventRecorder.swift
Sources/ConnorGraphAgent/AgentEventReplayer.swift
Sources/ConnorGraphAgent/AgentTextDeltaBuffer.swift
Sources/ConnorGraphAgent/AgentRuntimeUsageTracker.swift
Sources/ConnorGraphAgent/OpenAICompatibleProvider.swift
```

### ConnorGraphAppSupport

App repositories、runtime factory、runtime integration、commercial readiness 和 SwiftUI presentation model target。包含：

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

关键文件：

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
Sources/ConnorGraphAppSupport/ConnorCommandPalettePresentation.swift
Sources/ConnorGraphAppSupport/ConnorDeepLinkNavigator.swift
Sources/ConnorGraphAppSupport/CommercialReadinessGate.swift
```

### ConnorGraphAgentMac

SwiftUI macOS executable target。当前前台体验采用 Native Agent OS shell：Sessions 默认入口，左侧产品导航，中间列表/分类，右侧详情工作区。

包含：

- App entry point
- Native product sidebar navigation
- Three-column session shell
- Conversation list with status / labels
- Agent chat workbench
- Floating session info panel
- Composer-level permission picker
- Composer-level model picker
- Settings center
- Source runtime panel
- Skill runtime panel
- Automation runtime panel
- Local API / CLI surface entry
- Command Palette view
- Browser workspace view

关键文件：

```text
Sources/ConnorGraphAgentMac/ConnorGraphAgentMacApp.swift
Sources/ConnorGraphAgentMac/ConnorCommandPaletteView.swift
Sources/ConnorGraphAgentMac/SourceSkillAutomationRuntimeViews.swift
Sources/ConnorGraphAgentMac/AgentChatView.swift
Sources/ConnorGraphAgentMac/BrowserWorkspaceView.swift
Sources/ConnorGraphAgentMac/EmptyGraphHybridSearchService.swift
```

### ConnorCLI

SwiftPM CLI executable target。当前是 local-only programmable control plane 的最小入口，不依赖远程 daemon。

关键文件：

```text
Sources/ConnorCLI/main.swift
```

当前命令：

```bash
swift run connor commands
swift run connor readiness
swift run connor automations evaluate --trigger sessionStatusChanged --session demo --status needs_review --dry-run
```

---

## Session OS

Commercial Train 1 将 `NativeSessionManager` 从 turn executor 推进为持久化 Session OS runtime。

当前能力：

- Durable run lifecycle：queued、running、completed、failed、cancelled、waitingForApproval
- Session journal
- Pending approvals restore
- Pending plans
- Branch records
- Restore snapshot
- Status / label / archive / restore governance fanout
- Runtime state metadata

关键持久化表：

```text
session_pending_plans
session_branch_records
```

关键类型：

```text
SessionOSJournalPayload
SessionPendingPlanStatus
SessionPendingPlan
SessionBranchRecord
SessionOSRestoreSnapshot
```

Session OS 的边界：Claude SDK sidecar、MCP server、CLI/API 都不拥有 Connor session state。

---

## Claude SDK Sidecar Runtime

Commercial Train 2 将 Claude SDK 作为外部执行引擎接入，但不让它成为产品状态 owner。

当前 sidecar 目录：

```text
sidecars/claude-agent-engine/claude-sidecar.mjs
```

Swift 侧关键文件：

```text
Sources/ConnorGraphAppSupport/GovernedClaudeSDKSidecarRuntime.swift
Sources/ConnorGraphAppSupport/ClaudeSDKSidecarBackend.swift
Sources/ConnorGraphAppSupport/AppClaudeSDKSidecarRuntimeStore.swift
Sources/ConnorGraphAppSupport/AppGraphAgentRuntimeFactory.swift
```

当前实现包含：

- `sdkSessionID` persistence
- Sidecar runtime record
- Sidecar runtime diagnostics
- Sidecar heartbeat / health decoding
- Cancel command envelope
- Approval resolution command mapping
- Persistent process transport
- Factory wiring through app storage paths
- Guardrail against routing governed Claude Sidecar mode through legacy direct model provider paths
- `bypassPermissions` 仅用于让 Connor Policy Engine 成为唯一审批/审计层，不表示 unrestricted product authority

---

## Source / MCP Platform

Commercial Train 3 将 MCP Source 从 config/call helper 升级为 Connor-owned source platform object。

关键文件：

```text
Sources/ConnorGraphAppSupport/AppMCPSourceRuntimeRepository.swift
Sources/ConnorGraphAppSupport/MCPJSONRPCClient.swift
Sources/ConnorGraphAppSupport/MCPSourceRuntime.swift
Sources/ConnorGraphAppSupport/SourceSkillAutomationUIPresentation.swift
```

当前能力：

- Source runtime registry persistence
- Stdio / HTTP transport configuration shape
- Source ID validation
- Tool name prefix validation
- Unsafe graph write policy rejection
- MCP JSON-RPC lifecycle：initialize、notifications/initialized、tools/list、tools/call、shutdown
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

边界：MCP servers 是能力提供者；Connor 拥有 registry、lifecycle、health、permission policy、graph ingestion policy、audit 与 readiness。

---

## Graph Memory Kernel

Commercial Train 4 将 Graph Memory 从后处理能力升级为 Agent runtime 核心能力。

当前图谱记忆相关类型包括：

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

当前写入路径：

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

Agent context 注入路径：

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

Graph write candidate 或 extraction draft 可进入 admission hold queue。Review Center 通过 `GraphMemoryProductizationCenter` 聚合 context use、feedback signal、distillation candidate、hold queue 和 change log，并提供 review evidence。

边界：对话 LLM 不直接写图谱；Graph Memory 继续作为 Connor-owned background memory substrate 服务通用助手。

---

## Automation Engine and Local Automation Surface

Automation Engine 文件：

```text
Sources/ConnorGraphCore/ProductOSAutomation.swift
Sources/ConnorGraphAppSupport/AppProductOSAutomationRepository.swift
Sources/ConnorGraphAppSupport/AutomationEngine.swift
```

Automation Engine 当前能力：

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

执行历史路径：

```text
automations/automation-execution-history.json
```

Commercial Train 6 新增 Local API / CLI / Automation Surface：

```text
Sources/ConnorGraphAppSupport/ConnorLocalAutomationSurface.swift
Sources/ConnorCLI/main.swift
```

当前 Local API route catalog：

```text
GET  /v1/readiness
GET  /v1/automation/rules
POST /v1/automation/evaluate
POST /v1/automation/execute-reviewed
GET  /v1/commands
```

当前 CLI catalog：

```text
connor commands
connor readiness
connor automations list
connor automations evaluate --trigger <kind> --session <id> --status <status> --dry-run
connor automations execute-reviewed --review-token <token>
```

其中当前 smoke-tested commands：

```text
connor commands
connor readiness
connor automations evaluate --trigger sessionStatusChanged --session demo --status needs_review --dry-run
```

Automation Surface readiness evidence：

```text
endpointCount
cliCommandCount
automationTriggerCount
dryRunEvaluationReady
reviewedExecutionGateReady
auditSurfaceReady
localOnlySafetyReady
```

安全边界：

- Local API 是 contract/router，不默认启动长期 server。
- CLI/API 不直接写图谱。
- State-changing automation 必须经过 reviewed execution gate。
- Dry-run evaluation 输出 matched rules、action plans、ready/pending/blocked counts 和 audit summary。
- Unsafe 或 pending-review actions 不会被未审查执行。

---

## Native UI

Commercial Train 5 将 Native UI 从功能入口集合升级为商业级 Agent OS 控制台。

当前 shell 信息架构：

```text
Home
Work
Memory
Governance
Extensions
System
```

当前主入口：

```text
Sessions
```

当前 sidebar destinations：

```text
New Session
All Sessions
Inbox
Labels
Graph Memory Review
Approvals
Automations
Local API / CLI
Sources
Skills
Browser Workspace
Settings
```

当前 native panels / views：

```text
CraftPrimarySidebarView
CraftListPaneView
CraftSessionListPane
CraftDetailPaneView
AgentChatView
AgentChatComposerView
AgentChatInspectorView
ConnorSettingsDetailView
SourceRuntimePanelView
SkillRuntimePanelView
AutomationRuntimePanelView
ConnorCommandPaletteView
BrowserWorkspaceView
```

Browser Workspace 当前支持：

- SwiftUI + WKWebView 内置网页工作区
- 轻量多标签页标签栏；标签过多时先自动缩窄每个标签，达到最小宽度后再横向滚动
- 每个 Connor Session 拥有独立的浏览器标签页栈、选中文本浮窗、网页选择 mini-thread 记录和上次离开时的浏览器/对话视图模式
- 浏览器状态是 Session Capsule 的子状态，持久化到 `sessions/{sessionID}/browser/browser-state.json`
- 网页选择提问会同时追加到 `sessions/{sessionID}/state/records.jsonl`，作为会话记录流的一部分
- 每个标签页独立保留 URL、标题、加载状态和前进/后退 metadata；运行期 WKWebView 缓存在 UI 层，不跨重启持久化
- 地址栏输入 URL、域名或搜索词，按 Return 打开
- target=_blank / 新窗口导航自动打开为新标签页
- Browser Workspace 可见时，按 ⌘W 关闭当前选中的浏览器标签页，而不是关闭整个 macOS 窗口
- 从对话 transcript 中打开链接时，会写入当前会话的浏览器状态，追加并选中新标签页，同时更新地址栏目标
- 内置搜索服务需要浏览器时，可先通过隐藏的 Browser Background Task Runner 使用同一应用级 WebKit 存储在后台加载搜索页；若流程未遇到验证/安全挑战，则后台完成不切换用户界面；若检测到 CAPTCHA、人机验证、Cloudflare challenge 等卡点，则标记为 awaiting user intervention，并显式切换到对应浏览器标签页请用户处理
- 地址栏右侧提供“问一问 AI”按钮，可基于当前网页全文打开与选区浮窗一致的整页 mini-thread 提问浮窗
- 用户在网页中选中文本后自动显示跟随选区的浮动窗口
- 浮窗会根据 Browser Workspace 可视区域自动翻转、平移并限制最大高度，避免在窗口边缘、小窗口或长 mini-thread 场景下显示不全
- 浮窗可基于选中文本提问、插入主对话输入框或保存为 Graph Evidence episode
- 浮窗打开时按 Esc 可关闭浮窗并保留当前输入草稿，便于稍后重新打开继续编辑
- 浮窗发送按钮复用主对话 composer 的原型发送按钮样式
- 发送给 LLM 后浮窗保持打开，局部 mini-thread 显示 loading 状态、用户提问与 assistant Markdown 回复
- 同一次网页选区提问也会同步进入主会话 transcript：主会话显示简洁可读的“网页选区提问”，LLM 实际接收完整网页上下文

Command Palette 当前支持：

- command / destination entries
- group metadata
- risk badge
- primary action marker
- shortcut search
- keyword search
- empty state

当前 command examples：

```text
Open Home
New Session
Open Graph Memory Review
Open Approvals
Open Automations
Open Local API / CLI
Open Sources
Open Skills
Open Browser Workspace
Open Settings
```

Deep-link resolver 文件：

```text
Sources/ConnorGraphAppSupport/ConnorDeepLinkNavigator.swift
```

支持 URL 形态：

```text
connor://open/{destination}
connor://open/{destination}?focus={focusID}
```

示例：

```text
connor://open/home
connor://open/sources
connor://open/automation?focus=history
connor://open/browserWorkspace
```

---

## Settings Center

设置入口位于 System / Settings。设置中心由中间栏分类列表和右侧设置详情组成，不包含 workspace / workplace 设置，因为当前应用仍是单一 Home / Runtime Root，不支持多 workspace。

当前设置分类：

```text
应用
AI
外观
输入
权限
标签
快捷键
偏好
```

核心视图：

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

设置持久化文件：

```text
Sources/ConnorGraphAppSupport/AppRuntimeSettingsRepository.swift
Sources/ConnorGraphAppSupport/AppLLMSettingsRepository.swift
```

`AgentRuntimeSettings` 当前包含：

```text
schemaVersion
loop
ui
app
appearance
input
permissions
preferences
updatedAt
```

AI 设置页支持：

- OpenAI-compatible provider
- Governed Claude Sidecar provider
- Model / selected model
- Base URL
- API Key 输入 / 清除
- 连接测试
- Claude Sidecar executable / arguments / working directory
- Sidecar mode guardrail

注意：部分设置已完成本地持久化，但尚未全部接入实际运行时行为，例如桌面通知、保持屏幕常亮、外观模式实时切换、输入框拼写检查和网络 / Shell 审批细粒度 enforcement。

---

## Hybrid Graph Retrieval and Evaluation

统一检索接口：

```text
GraphHybridSearchService
```

SQLite 实现：

```text
SQLiteGraphHybridSearchService
```

当前检索组成：

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

Retrieval evaluation 持久化路径：

```text
graph/evaluations/retrieval-evaluation-cases.json
graph/evaluations/reports/*.json
```

支持指标：

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

Commercial Readiness 当前覆盖 6 个 phase：

```text
Phase 1 · Session OS / Governance
Phase 2 · Claude SDK Sidecar Runtime
Phase 3 · Source / MCP Platform
Phase 4 · Graph Memory Core Capability
Phase 5 · Native Commercial UI
Phase 6 · Local API / CLI / Automation Surface
```

Readiness Gate 聚合：

- Session runs / journal / pending plan / branch / restore snapshot evidence
- Claude sidecar runtime / diagnostics / permission sovereignty evidence
- Source health / discovery / tool catalog / audit / graph write policy evidence
- Graph Memory context / ingestion / distillation / review evidence
- Native UI home / runtime center / command palette / settings evidence
- Local API / CLI endpoint / command / dry-run / reviewed gate / audit / local-only evidence

关键文件：

```text
Sources/ConnorGraphAppSupport/CommercialReadinessGate.swift
Sources/ConnorGraphAppSupport/ConnorNativeCommercialUIPresentation.swift
```

---

## Build, Test and CLI Smoke

Build：

```bash
cd /Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac
swift build
```

Product builds：

```bash
swift build --product connor-graph-agent-mac
swift build --product connor
```

Test：

```bash
swift test
```

CLI smoke：

```bash
swift run connor commands
swift run connor readiness
swift run connor automations evaluate --trigger sessionStatusChanged --session demo --status needs_review --dry-run
```

最近验证结果：

```text
Build of products 'connor-graph-agent-mac' and 'connor' succeeded.
377 tests in 16 suites passed (2026-06-12 21:34 GMT+8).
CLI smoke checks passed for commands, readiness and automation dry-run evaluation.
```

---

## Test Coverage Highlights

重要商业化测试：

```text
Tests/ConnorGraphAppSupportTests/NativeSessionManagerSessionOSTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain2ClaudeSDKSidecarTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain3SourceMCPPlatformTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain4GraphMemoryCoreTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain5NativeUICommercializationTests.swift
Tests/ConnorGraphAppSupportTests/CommercialTrain6LocalAPICLIAutomationSurfaceTests.swift
```

其他关键测试：

```text
Tests/ConnorGraphAgentTests/AgentLoopControllerTests.swift
Tests/ConnorGraphAgentTests/AgentContextBuilderSQLiteSearchTests.swift
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

早期阶段性增量：

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

商业化列车：

```text
Commercial Train 1: Session OS Maturation
Commercial Train 2: Claude SDK Sidecar Productionization
Commercial Train 3: Source / MCP Platformization
Commercial Train 4: Graph Memory as Agent Core Capability
Commercial Train 5: Native UI Commercialization
Commercial Train 6: Local API / CLI / Automation Surface
```

已知合并/阶段提交：

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
```

Phase H 在 main 历史中体现为：

```text
05457b3 Phase H add source runtime UI presentation
b011671 Phase H add skill runtime UI presentation
84271e6 Phase H wire automation source and skill UI panels
```

---

## Deferred Scope

当前仍刻意延后：

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
