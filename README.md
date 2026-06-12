# Connor Graph Agent Mac

文档更新时间：2026-06-12 14:58 GMT+8  
当前代码基线：`main`，提交 `eac3db3`，叠加本地 Craft-grade shell、聊天工作台和设置中心改造。

Connor Graph Agent Mac 是一个 Swift / SwiftUI macOS 应用和 SwiftPM package。项目包含本地会话运行时、SQLite temporal graph、后台图谱记忆管线、Agent runtime、Claude SDK sidecar 边界、MCP source runtime、skill runtime、automation engine、Craft 风格三栏 native UI、会话工作台、设置中心、command palette 和 deep-link resolver。

产品定位上，图谱是后台记忆基础设施，不作为普通用户的主导航概念暴露；前台 UI 以会话、数据源、技能、自动化和设置为核心。

---

## Package 信息

```text
Package name: ConnorGraphAgentMac
Swift tools version: 6.0
Platform: macOS 14+
Executable product: connor-graph-agent-mac
System libraries/frameworks: sqlite3, Security, WebKit
```

Package products：

```text
ConnorGraphCore
ConnorGraphMemory
ConnorGraphStore
ConnorGraphSearch
ConnorGraphAgent
ConnorGraphAppSupport
connor-graph-agent-mac
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

## 本地存储结构

运行时根目录由 `AppStoragePaths` 解析到用户 Application Support 下的 `Connor` 目录。当前实现使用单一 Home / Runtime Root。

目录结构包含：

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

Session artifact directories：

```text
sessions/{sessionID}/
├── plans/
├── data/
├── attachments/
├── exports/
└── logs/
```

主要 JSON 状态文件包括：

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

## 模块现状

### ConnorGraphCore

领域模型 target。包含：

- Temporal graph domain
- Agent conversation domain
- Agent permission domain
- Agent runtime event domain
- Session governance model
- Product OS registry model
- Product OS automation model
- Graph extraction domain
- Structured extraction domain
- Graph write candidate domain
- Optimistic write domain
- Self-healing domain

相关文件示例：

```text
Sources/ConnorGraphCore/AgentConversation.swift
Sources/ConnorGraphCore/AgentPermissionDomain.swift
Sources/ConnorGraphCore/AgentRuntimeDomain.swift
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

相关文件示例：

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
- Agent runtime persistence
- Chat session persistence
- Audit persistence
- Entity resolver
- Entity resolution plan
- Conflict preview
- Extraction prompt builder
- LLM graph extractor
- Extraction trace persistence
- Extraction replay
- Graph write admission policy
- Optimistic write service
- Background job runner
- Extraction worker
- Index refresh worker
- Grounding check worker
- Self-healing service
- Memory change log
- Admission hold queue
- SQLite hybrid search service

相关文件示例：

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
- Retrieval evaluation cases
- Retrieval judgments
- Retrieval hits
- Retrieval metrics
- Retrieval reports
- Retrieval evaluation harness

相关文件示例：

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
- Prompt budget estimation
- Prompt inspection
- Session summary strategy
- Agent event recorder
- Event replay
- Text delta buffering
- Runtime usage tracking

相关文件示例：

```text
Sources/ConnorGraphAgent/GraphAgentBackend.swift
Sources/ConnorGraphAgent/AnyAgentBackend.swift
Sources/ConnorGraphAgent/AgentLoopController.swift
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

App repositories、runtime factory、runtime integration 和 SwiftUI presentation model target。包含：

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
- Automation engine
- Automation execution history
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

相关文件示例：

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
Sources/ConnorGraphAppSupport/ConnorNativeShellPresentation.swift
Sources/ConnorGraphAppSupport/ConnorRuntimeCenterPresentation.swift
Sources/ConnorGraphAppSupport/SourceSkillAutomationUIPresentation.swift
Sources/ConnorGraphAppSupport/ConnorCommandPalettePresentation.swift
Sources/ConnorGraphAppSupport/ConnorDeepLinkNavigator.swift
```

### ConnorGraphAgentMac

SwiftUI macOS executable target。当前前台体验采用 Craft Agent 风格三栏布局：左侧产品导航、中间列表/设置分类、右侧详情工作区。程序启动默认进入“所有会话 / 全部”，并自动选择最近更新的对话。普通用户主导航不暴露 graph node、write candidate、promotion queue、Runtime Center 或记忆调试中心；图谱能力作为后台记忆基础设施服务于会话和检索。

包含：

- App entry point
- Craft-style product sidebar navigation
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
- Command Palette view
- Browser workspace view
- Developer/runtime diagnostics retained as data/presentation models where still used by readiness tests; Runtime Center no longer has a user-facing SwiftUI view or command entry

相关文件示例：

```text
Sources/ConnorGraphAgentMac/ConnorGraphAgentMacApp.swift
Sources/ConnorGraphAgentMac/ConnorCommandPaletteView.swift
Sources/ConnorGraphAgentMac/SourceSkillAutomationRuntimeViews.swift
Sources/ConnorGraphAgentMac/AgentChatView.swift
Sources/ConnorGraphAgentMac/BrowserWorkspaceView.swift
Sources/ConnorGraphAgentMac/EmptyGraphHybridSearchService.swift
```

---

## Graph Memory Kernel

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
```

当前写入路径由以下阶段组成：

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

Graph write candidate 或 extraction draft 可进入 admission hold queue。Review Center 通过 `GraphMemoryProductizationCenter` 聚合候选、hold queue 和 change log，并提供 approve / reject action result。

---

## Agent Runtime

Agent runtime 使用 backend/event abstraction。

主要组成：

```text
AgentBackend
AnyAgentBackend
AgentLoopController
NativeSessionManager
AgentEvent
AgentPermission
AgentPendingApproval
SQLiteAgentAuditLog
AgentEventRecorder
AgentEventReplayer
AgentTextDeltaBuffer
AgentRuntimeUsageTracker
```

当前 runtime event 覆盖：

```text
model message
tool call started / finished / failed
permission requested
approval resolved
graph memory proposed / committed / held
session status changed
session labels changed
source registry changed
skill registry changed
automation triggered
artifact created
```

`NativeSessionManager` 当前包含 processing state、active run tracking、cancel、retry last user message、runtime state metadata 等行为。

---

## Claude SDK Sidecar Runtime

当前 sidecar 相关目录：

```text
sidecars/claude-agent-engine/claude-sidecar.mjs
```

Swift 侧相关文件：

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
- Sidecar health event decoding
- Cancel command envelope
- Approval resolution command mapping
- Persistent process transport
- Factory wiring through app storage paths
- Guardrail against routing governed Claude Sidecar mode through legacy direct model provider paths; Sidecar runs through `NativeSessionManager` + `ClaudeSDKSidecarBackend`.

---

## MCP Source Runtime

当前 MCP / source runtime 文件：

```text
Sources/ConnorGraphAppSupport/AppMCPSourceRuntimeRepository.swift
Sources/ConnorGraphAppSupport/MCPJSONRPCClient.swift
Sources/ConnorGraphAppSupport/MCPSourceRuntime.swift
```

当前实现包含：

- Source runtime registry persistence
- Stdio / HTTP transport configuration shape
- Source ID validation
- Tool name prefix validation
- Unsafe graph write policy rejection
- MCP JSON-RPC lifecycle client
- `initialize`
- `notifications/initialized`
- `tools/list`
- `tools/call`
- `shutdown`
- Server error mapping
- Source-prefixed tool catalog
- Disabled-source gate
- MCP tool call event bridge
- Product OS registry sync event

---

## Skill Runtime

当前 skill runtime 文件：

```text
Sources/ConnorGraphAppSupport/AppSkillRuntimeRepository.swift
Sources/ConnorGraphAppSupport/SkillRuntime.swift
```

当前实现包含：

- `SKILL.md` frontmatter parser
- Skill manifest persistence
- Resolution order: project > home > global
- Trigger matching
- Glob matching
- Instruction bundle generation
- Required capability propagation
- Required source propagation
- Permission request generation
- Disabled-skill rejection
- Product OS registry sync event

支持的 manifest 字段包括：

```text
name
description
triggers
requiredCapabilities
requiredSources
globs
graphContextPolicy
tags
icon
```

---

## Automation Engine

当前 automation 文件：

```text
Sources/ConnorGraphCore/ProductOSAutomation.swift
Sources/ConnorGraphAppSupport/AppProductOSAutomationRepository.swift
Sources/ConnorGraphAppSupport/AutomationEngine.swift
```

当前实现包含：

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

---

## Native UI 状态

当前主界面改为 Craft Agent 风格三栏 shell：

```text
左侧：产品导航
中间：会话列表 / 数据源列表 / 技能列表 / 自动化列表 / 设置分类
右侧：聊天详情 / 设置详情 / 运行时面板
```

默认 selection：

```text
agentChat
```

左侧用户主导航只保留产品级概念：

```text
新建会话
所有会话
  全部
  收件箱
  configured statuses
标签
  configured labels
数据源
技能
自动化
  定时任务
  事件触发
  智能体
设置
```

不再作为普通用户主导航展示的内部实现概念：

```text
Runtime Center
图谱节点
图谱搜索
写入候选
提升队列
记忆变更
记忆准入
Graph Memory Review Center
```

这些能力仍可作为后台基础设施、内部数据模型或开发诊断能力存在；Runtime Center 的用户界面与命令入口已删除，避免让用户把 Connor 理解成“运行时控制台”或“图谱编辑器”。

当前 native panels / views 包括：

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

聊天工作台当前特性：

- 会话列表由 shell 中间栏负责，`AgentChatView` 不再内嵌第二份会话列表。
- 右侧常驻 inspector 已改为浮动“信息”面板。
- Composer 底部提供附件、浏览器、token 信息、权限模式、模型选择和发送按钮。
- 权限模式显示中文名称，并默认隐藏 `allowAll` 级别。
- 模型选择由 `AppLLMModelCatalog` 从当前 provider mode 构建连接：OpenAI-compatible 可读取 live `/models`，Claude Sidecar 使用 sidecar 配置候选；Sidecar 执行路径通过 `NativeSessionManager` + `ClaudeSDKSidecarBackend`。产品设置不再提供模拟 provider mode。

### 设置中心

设置入口位于左侧主导航底部。设置中心由中间栏分类列表和右侧设置详情组成，不包含 workspace / workplace 相关设置，因为当前应用仍是单一 Home / Runtime Root，不支持多 workspace。

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

设置详情页文件：

```text
Sources/ConnorGraphAgentMac/ConnorGraphAgentMacApp.swift
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

新增 runtime settings 分组：

```text
AgentRuntimeAppSettings
  desktopNotificationsEnabled
  keepScreenAwake
  internalBrowserEnabled
  httpProxyEnabled
  httpProxyURLString

AgentRuntimeAppearanceSettings
  mode

AgentRuntimeInputSettings
  composerSendShortcut
  spellCheckEnabled
  autoSaveDraftsEnabled

AgentRuntimePermissionSettings
  requireApprovalForNetwork
  requireApprovalForShell

AgentRuntimePreferenceSettings
  displayName
  timezone
  city
  country
  notes

AgentRuntimeUISettings
  showProviderIcons
  richToolDescriptionsEnabled
```

`AgentRuntimeSettings` 提供自定义 decode，旧版 `runtime-settings.json` 缺少新增字段时会自动补默认值，避免升级后配置解码失败。

AI 设置页复用现有 LLM 设置逻辑：

- provider mode：OpenAI-compatible、governed Claude Sidecar
- model / selected model
- base URL
- API Key 输入 / 清除
- 连接测试
- Claude Sidecar executable / arguments / working directory
- Sidecar mode guardrail：legacy direct LLM/model provider path 会返回明确错误，Claude Sidecar 只通过 session manager/backend 执行。

注意：部分设置目前已完成本地持久化，但尚未全部接入实际运行时行为，例如桌面通知、保持屏幕常亮、外观模式实时切换、输入框拼写检查和网络 / Shell 审批细粒度 enforcement。

---

## Command Palette 与 Deep Link

当前 command palette 文件：

```text
Sources/ConnorGraphAppSupport/ConnorCommandPalettePresentation.swift
Sources/ConnorGraphAgentMac/ConnorCommandPaletteView.swift
```

当前 command palette 从 `ConnorNativeShellPresentation.default` 构建 entries，entry 类型包括：

```text
command
destination
```

当前支持按以下字段搜索：

```text
title
subtitle
shortcut
target
keywords
```

当前 deep-link resolver 文件：

```text
Sources/ConnorGraphAppSupport/ConnorDeepLinkNavigator.swift
```

当前支持 URL 形态：

```text
connor://open/{destination}
connor://open/{destination}?focus={focusID}
```

示例：

```text
connor://open/sources
connor://open/automation?focus=history
connor://open/browserWorkspace
```

Resolver 输出：

```text
item
sidebarItem
requiresBrowserVisible
focus
```

---

## Hybrid Graph Retrieval

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

Agent context 注入路径：

```text
User message
→ AgentContextBuilder
→ GraphHybridSearchService
→ GraphSearchResponse
→ AgentContext items
→ Prompt context
→ Model response with citations
```

---

## Retrieval Evaluation

当前检索评估类型：

```text
GraphRetrievalEvaluationCase
GraphRetrievalJudgment
GraphRetrievalEvaluationHit
GraphRetrievalEvaluationMetrics
GraphRetrievalEvaluationCaseResult
GraphRetrievalEvaluationReport
GraphRetrievalEvaluator
GraphRetrievalEvaluationHarness
```

当前支持指标：

```text
Precision@k
Recall@k
HitRate@k
Mean Reciprocal Rank
Average Precision
nDCG@k
RequiredHitRate@k
```

本地持久化路径：

```text
graph/evaluations/retrieval-evaluation-cases.json
graph/evaluations/reports/*.json
```

---

## 构建与测试

Build：

```bash
cd /Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

Product build：

```bash
cd /Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac
swift build --product connor-graph-agent-mac
```

最近验证结果：

```text
Build of product 'connor-graph-agent-mac' complete! (2026-06-12 14:58 GMT+8)
```

Test：

```bash
cd /Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

最近验证结果：

```text
344 tests in 9 suites passed
```

Phase I 专项验证：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PhaseI
```

最近验证结果：

```text
4 tests passed
```

---

## 已记录的阶段性系统增量

截至提交 `eac3db3` 并叠加当前本地改造，已合入 / 已完成的阶段性增量包括：

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
Local UI Refresh: Craft-like three-column shell and user-facing navigation cleanup
Local Settings Center: App / AI / Appearance / Input / Permissions / Labels / Shortcuts / Preferences
```

对应合并提交：

```text
Phase A: e0b6f27
Phase B: ad18b8f
Phase C: fa72f43
Phase D: 23f5776
Phase E: 829d130
Phase F: 9c77c85
Phase G: 0f9c99e
Phase I: 7d17ef8
```

Phase H 当前在 main 历史中体现为 commits：

```text
05457b3 Phase H add source runtime UI presentation
b011671 Phase H add skill runtime UI presentation
84271e6 Phase H wire automation source and skill UI panels
```

---

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE) for details.
