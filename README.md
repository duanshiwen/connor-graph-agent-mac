# Connor Graph Agent Mac

文档更新时间：2026-06-11 22:26 GMT+8  
当前代码基线：`main`，提交 `7d17ef8`（Merge pull request #65 from `feature/phase-i-command-palette-deeplink-clickthrough-260611`）

Connor Graph Agent Mac 是一个 Swift / SwiftUI macOS 应用和 SwiftPM package。项目包含本地会话运行时、SQLite temporal graph、图谱记忆管线、Agent runtime、Product OS 本地控制面、Claude SDK sidecar 边界、MCP source runtime、skill runtime、automation engine、native runtime UI、command palette 和 deep-link resolver。

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
automations/automations.json
automations/automation-trigger-log.json
automations/automation-execution-history.json
labels/labels.json
statuses/statuses.json
graph/evaluations/retrieval-evaluation-cases.json
graph/evaluations/reports/*.json
```

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
- Runtime center presentation
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

SwiftUI macOS executable target。包含：

- App entry point
- Sidebar navigation
- Runtime Center view
- Command Palette view
- Graph overview UI
- Graph search UI
- Observe log UI
- Promotion queue UI
- Agent chat workbench
- Three-column session layout
- Session inspector
- Product OS views
- Source runtime panel
- Skill runtime panel
- Automation runtime panel
- Prompt inspection UI
- Model settings UI
- Browser workspace view

相关文件示例：

```text
Sources/ConnorGraphAgentMac/ConnorGraphAgentMacApp.swift
Sources/ConnorGraphAgentMac/ConnorRuntimeCenterView.swift
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

Native shell presentation 当前定义 sidebar groups：

```text
Run
Memory
Governance
System
```

Default selection：

```text
runtimeCenter
```

当前 shell items：

```text
runtimeCenter
agentChat
browserWorkspace
graphMemory
search
graphEntities
approvals
automation
productOS
sources
skills
settings
```

当前 shell commands：

```text
newSession
toggleBrowser
openRuntimeCenter
openGraphMemoryReview
openApprovals
openSources
openSkills
openAutomation
openSettings
```

当前 native panels / views 包括：

```text
ConnorRuntimeCenterView
SourceRuntimePanelView
SkillRuntimePanelView
AutomationRuntimePanelView
ConnorCommandPaletteView
BrowserWorkspaceView
AgentChatView
```

Runtime Center presentation 聚合：

```text
sessions
events
pending approvals
automation triggers
graph memory dashboard
```

Runtime Center metric / section / row 当前包含 navigation target 字段，用于 click-through navigation。

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

最近验证结果：

```text
build complete
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

截至提交 `7d17ef8`，已合入的阶段性增量包括：

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
