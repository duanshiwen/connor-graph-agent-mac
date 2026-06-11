# Connor Graph Agent Mac

Connor Graph Agent Mac 是一个 macOS 本地优先的 Graph-Native Agent OS。系统以 Swift / SwiftUI 构建桌面产品壳，以 SQLite temporal graph 作为本地 truth layer，以 Connor 自有的会话、权限、审计、图谱记忆、Product OS 控制面和检索评估状态作为核心产品状态。

文档状态：2026-06-11 19:05 GMT+8。

---

## 系统定位

Connor 是一个通用助手，不是图谱编辑器，也不是普通 RAG demo。

图谱在系统中承担后台长期记忆基础设施角色：

- 对话、浏览、文件、source artifact 等输入先进入 evidence / episode / staging 层。
- 后台流程把可沉淀的信息抽取为候选实体和候选事实。
- Entity resolution、conflict preview、constraint validation 与 admission policy 决定事实是否进入 truth graph。
- Agent 回答前通过 graph-aware retrieval 读取相关长期记忆，并保留 citation / reason / metadata。
- 记忆写入、审批、审计、检索、评估与 Product OS 状态由 Connor 本地持有。

外部模型或 SDK 是推理引擎，不拥有 Connor 的产品状态。

---

## 当前系统状态

```text
Swift / SwiftUI macOS App
+ Product OS local state
+ SQLite temporal graph truth layer
+ Graph memory extraction / admission / self-healing pipeline
+ Graph-aware agent runtime
+ Governed sidecar backend boundary
+ Hybrid graph retrieval
+ Retrieval evaluation harness
```

核心能力：

- macOS SwiftUI 原生应用。
- SwiftPM 多模块 package。
- 单一 Home / Runtime Root。
- SQLite-backed temporal knowledge graph。
- Session governance。
- Product OS source / skill registry。
- Product OS labels / statuses / automations control-plane。
- Agent runtime、tool calling、permission policy、pending approval、audit log。
- Background memory ingestion、distillation、extraction、entity resolution、admission、commit、index refresh。
- Graph memory change log、admission hold queue、self-healing job queue。
- Hybrid graph retrieval：entity / statement / episode FTS、graph expansion、source episode expansion、local reranking、optional MMR。
- Retrieval evaluation：golden query cases、top-k metrics、required-hit coverage、本地 JSON reports。
- Governed Claude SDK sidecar runtime：SDK 是 backend engine，Connor 持有 session、approval、permission、audit、graph memory 与 Product OS state。

---

## 本地 Product OS 存储结构

运行时根目录位于用户 Application Support 下的 `Connor` 目录。系统使用单一 Home / Runtime Root，不使用多 workspace 模型。

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

每个 session 拥有自己的 artifact directories：

```text
sessions/{sessionID}/
├── plans/
├── data/
├── attachments/
├── exports/
└── logs/
```

主要本地配置与状态文件：

```text
config/session-governance.json
config/product-os-registry.json
automations/automations.json
automations/automation-trigger-log.json
labels/labels.json
statuses/statuses.json
graph/evaluations/retrieval-evaluation-cases.json
graph/evaluations/reports/*.json
```

---

## 模块结构

```text
Sources/
├── ConnorGraphCore/
├── ConnorGraphMemory/
├── ConnorGraphStore/
├── ConnorGraphSearch/
├── ConnorGraphAgent/
├── ConnorGraphAppSupport/
└── ConnorGraphAgentMac/
```

### ConnorGraphCore

领域模型层。

包含：

- Temporal graph domain。
- Agent conversation domain。
- Agent permission domain。
- Agent runtime event domain。
- Session governance model。
- Product OS registry model。
- Product OS automation model。
- Graph extraction / structured extraction domain。
- Graph write candidate domain。
- Optimistic write domain。
- Self-healing domain。

代表文件：

```text
Sources/ConnorGraphCore/GraphTemporalDomain.swift
Sources/ConnorGraphCore/AgentConversation.swift
Sources/ConnorGraphCore/AgentPermissionDomain.swift
Sources/ConnorGraphCore/AgentRuntimeDomain.swift
Sources/ConnorGraphCore/AgentSessionGovernance.swift
Sources/ConnorGraphCore/ProductOSRegistry.swift
Sources/ConnorGraphCore/ProductOSAutomation.swift
Sources/ConnorGraphCore/GraphExtractionDomain.swift
Sources/ConnorGraphCore/GraphStructuredExtraction.swift
Sources/ConnorGraphCore/GraphOptimisticWriteDomain.swift
Sources/ConnorGraphCore/GraphSelfHealingDomain.swift
```

### ConnorGraphMemory

记忆管线领域服务层。

包含：

- Observe log。
- Memory ingestion。
- Memory staging。
- Memory distillation。
- LLM-backed memory distillation interface。
- Promotion candidate model。
- Constraint validation。
- Contradiction detection。

代表文件：

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

SQLite 持久化、图谱写入与后台 worker 层。

包含：

- SQLite graph kernel store。
- SQLite temporal graph store。
- Agent runtime persistence。
- Chat session persistence。
- Audit persistence。
- Entity resolver。
- Entity resolution plan。
- Conflict preview。
- Graph extraction prompt builder。
- LLM graph extractor。
- Extraction trace / trace payloads。
- Extraction replay。
- Graph write admission policy。
- Optimistic write service。
- Background job runner。
- Extraction worker。
- Index refresh worker。
- Grounding check worker。
- Self-healing service。
- Memory change log。
- Admission hold queue。
- SQLite hybrid search service。

代表文件：

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

图谱检索与检索评估层。

包含：

- `GraphSearchQuery`。
- `GraphSearchHit`。
- `GraphSearchResponse`。
- `GraphHybridSearchService`。
- `GraphRerankingConfig`。
- Embedding provider protocol。
- Retrieval evaluation cases。
- Retrieval judgments。
- Retrieval hits。
- Retrieval metrics。
- Retrieval reports。
- Retrieval evaluation harness。

代表文件：

```text
Sources/ConnorGraphSearch/GraphSearch.swift
Sources/ConnorGraphSearch/GraphHybridSearch.swift
Sources/ConnorGraphSearch/EmbeddingProvider.swift
Sources/ConnorGraphSearch/GraphRetrievalEvaluation.swift
```

### ConnorGraphAgent

Agent runtime 层。

包含：

- Agent backend abstraction。
- Type-erased backend。
- Model provider abstraction。
- OpenAI-compatible provider。
- Tool-calling loop。
- Graph read tools。
- Graph write tools。
- Web/search tools。
- Permission policy。
- Prompt budget estimation。
- Prompt inspection。
- Session summary refresh strategy。
- Agent event recorder。

代表文件：

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
Sources/ConnorGraphAgent/OpenAICompatibleProvider.swift
```

### ConnorGraphAppSupport

App repository、runtime factory 和系统集成层。

包含：

- App storage path resolution。
- SQLite bootstrap。
- Graph repository。
- Chat session repository。
- Session governance config repository。
- Product OS source / skill registry repository。
- Product OS automation / labels / statuses repository。
- Retrieval evaluation repository。
- LLM settings repository。
- LLM provider health checker。
- Keychain credential store。
- Agent runtime factory。
- Governed Claude SDK sidecar runtime。
- Claude SDK sidecar backend。
- Native session manager。
- Pending approval repository。
- Audit log repository。
- App memory staging and distillation workers。
- Presentation models for SwiftUI。

代表文件：

```text
Sources/ConnorGraphAppSupport/AppStoragePaths.swift
Sources/ConnorGraphAppSupport/AppGraphBootstrapper.swift
Sources/ConnorGraphAppSupport/AppChatSessionRepository.swift
Sources/ConnorGraphAppSupport/AppSessionGovernanceConfigRepository.swift
Sources/ConnorGraphAppSupport/AppProductOSRegistryRepository.swift
Sources/ConnorGraphAppSupport/AppProductOSAutomationRepository.swift
Sources/ConnorGraphAppSupport/AppGraphRetrievalEvaluationRepository.swift
Sources/ConnorGraphAppSupport/AppLLMSettingsRepository.swift
Sources/ConnorGraphAppSupport/AppLLMProviderHealthChecker.swift
Sources/ConnorGraphAppSupport/AppGraphAgentRuntimeFactory.swift
Sources/ConnorGraphAppSupport/GovernedClaudeSDKSidecarRuntime.swift
Sources/ConnorGraphAppSupport/ClaudeSDKSidecarBackend.swift
Sources/ConnorGraphAppSupport/NativeSessionManager.swift
Sources/ConnorGraphAppSupport/AppAgentPendingApprovalRepository.swift
Sources/ConnorGraphAppSupport/SQLiteAgentAuditLog.swift
```

### ConnorGraphAgentMac

SwiftUI macOS 应用层。

包含：

- App entry point。
- Sidebar navigation。
- Graph overview。
- Graph search UI。
- Observe log UI。
- Promotion queue UI。
- Agent chat workbench。
- Three-column session layout。
- Session inspector。
- Product OS source / skill / labels / statuses / automations views。
- Prompt inspection UI。
- Model settings UI。
- Browser workspace view。

代表文件：

```text
Sources/ConnorGraphAgentMac/ConnorGraphAgentMacApp.swift
Sources/ConnorGraphAgentMac/AgentChatView.swift
Sources/ConnorGraphAgentMac/BrowserWorkspaceView.swift
Sources/ConnorGraphAgentMac/EmptyGraphHybridSearchService.swift
```

---

## Graph Memory Kernel

Connor 的图谱记忆使用 temporal graph-only 数据模型：

```text
GraphEntity
GraphStatement
GraphEpisodeV3
GraphObservation
GraphExtractionDraft
GraphExtractionTrace
GraphMemoryChangeLog
```

核心原则：

- SQLite graph store 是本地 truth layer。
- Graph statement 使用 temporal validity 与 belief 状态表达事实演化。
- Episode 是证据和来源上下文。
- Extraction draft 是进入 truth graph 前的候选层。
- Entity resolver 负责复用、创建、潜在重复与 merge review。
- Conflict preview 在写入前检测 active statements 中的直接冲突。
- Admission policy 决定 `autoCommit`、`hold`、`askUser`、`discard`。
- Optimistic write service 执行 resolver-backed commit。
- Memory change log 记录图谱记忆变更。
- Admission hold queue 保存需要系统处理或用户判断的候选。

图谱写入路径：

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

---

## Agent Runtime

Agent runtime 使用统一 backend/event abstraction。

主要组成：

- `AgentBackend`：统一 backend 协议。
- `AnyAgentBackend`：type-erased backend。
- `AgentLoopController`：tool-calling loop。
- `NativeSessionManager`：App 侧 session runtime。
- `AgentEvent`：runtime timeline event。
- `AgentPermission` / policy engine：权限治理。
- `AgentPendingApproval`：待审批操作。
- `SQLiteAgentAuditLog`：审计记录。

运行时事件覆盖：

- model message。
- tool call started / finished / failed。
- permission requested。
- approval resolved。
- graph memory proposed / committed / held。
- session status / labels changed。
- source / skill registry changed。
- automation triggered。
- artifact created。

---

## Governed Sidecar Backend

Connor 支持 governed Claude SDK sidecar runtime。

边界：

- Claude SDK 作为外部 sidecar engine。
- Connor 持有 session identity。
- Connor 持有 permission mode。
- Connor 持有 pending approval queue。
- Connor 写入 approval audit。
- Connor 持有 graph memory。
- Connor 持有 Product OS state。
- SDK permission mode 固定为 sidecar 层执行所需模式。
- Connor runtime 拒绝不受控的 allow-all 产品权限。

相关文件：

```text
Sources/ConnorGraphAppSupport/GovernedClaudeSDKSidecarRuntime.swift
Sources/ConnorGraphAppSupport/ClaudeSDKSidecarBackend.swift
Sources/ConnorGraphAppSupport/AppGraphAgentRuntimeFactory.swift
Sources/ConnorGraphAppSupport/AppLLMSettingsRepository.swift
```

---

## Product OS Control Plane

Connor 的 Product OS 控制面是本地 JSON + SQLite 状态组合。

### Session Governance

能力：

- Session status。
- Typed labels。
- Archive / restore。
- Flag。
- Artifact directories。
- Governance timeline events。

相关文件：

```text
Sources/ConnorGraphCore/AgentSessionGovernance.swift
Sources/ConnorGraphAppSupport/AppSessionGovernanceConfigRepository.swift
Sources/ConnorGraphAppSupport/AppChatSessionRepository.swift
```

### Source / Skill Registry

能力：

- Typed source definitions。
- Typed skill definitions。
- Source and skill status。
- Credential requirement metadata。
- Source directory provisioning。
- Skill directory provisioning。
- Graph write / graph context policy guardrails。

相关文件：

```text
Sources/ConnorGraphCore/ProductOSRegistry.swift
Sources/ConnorGraphAppSupport/AppProductOSRegistryRepository.swift
```

### Labels / Statuses / Automations

能力：

- Status mirror。
- Label mirror。
- Automation rules。
- Automation trigger records。
- Event matching。
- Timeline entries for trigger records。
- Unsafe action rejection for automatic archival.

相关文件：

```text
Sources/ConnorGraphCore/ProductOSAutomation.swift
Sources/ConnorGraphAppSupport/AppProductOSAutomationRepository.swift
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

检索能力：

- Entity FTS。
- Statement FTS。
- Episode FTS。
- Source episode expansion。
- Bounded multi-hop graph expansion。
- Candidate pool multiplier。
- Local lexical overlap reranking。
- Statement endpoint context boost。
- Statement confidence boost。
- Episode mention boost。
- Optional MMR diversity reranking。
- Retrieval pipeline metadata。
- Matched terms metadata。
- Rerank reasons metadata。
- Graph hop metadata。
- Graph context entity IDs metadata。

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

检索评估由 Connor 本地持有，不依赖云端评测服务。

核心类型：

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

支持指标：

- Precision@k。
- Recall@k。
- HitRate@k。
- Mean Reciprocal Rank。
- Average Precision。
- nDCG@k。
- RequiredHitRate@k。

本地持久化：

```text
graph/evaluations/retrieval-evaluation-cases.json
graph/evaluations/reports/*.json
```

---

## SwiftUI App

Mac App 当前是一个原生 SwiftUI 产品壳。

主要界面：

- Graph overview。
- Graph search。
- Observe log。
- Promotion queue。
- Memory change log。
- Agent chat workbench。
- Session inbox。
- Conversation view。
- Session inspector。
- Product OS source / skill registry。
- Product OS statuses / labels。
- Product OS automations and trigger log。
- Prompt inspection。
- Model settings。
- Browser workspace。

Agent chat 使用三栏布局：

```text
Session Inbox
→ Conversation
→ Session Inspector
```

---

## 构建与测试

### 环境

```text
Swift tools version: 6.0
Platform: macOS 14+
SQLite: system sqlite3
Frameworks: Security, WebKit
```

### Build

```bash
cd /Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

当前验证结果：

```text
ok (build complete)
```

### Test

```bash
cd /Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

当前验证结果：

```text
Test run with 288 tests in 4 suites passed
```

### Package Products

```text
ConnorGraphCore
ConnorGraphMemory
ConnorGraphStore
ConnorGraphSearch
ConnorGraphAgent
ConnorGraphAppSupport
connor-graph-agent-mac
```

---

## 开发约束

### 图谱主权

- 不让模型 SDK 持有 Connor 产品状态。
- 不让模型 SDK 直接写入 truth graph。
- 不绕过 entity resolution。
- 不绕过 admission policy。
- 不绕过 audit log。

### 存储模型

- 使用单一 Home / Runtime Root。
- 不引入多 workspace 存储模型。
- Product OS 路径中不使用 `workspace` path segment。
- SQLite graph store 是本地 truth layer。

### 图谱模型

- 使用 `GraphEntity`、`GraphStatement`、`GraphEpisodeV3`。
- 不使用 legacy `GraphNode` / `SemanticEdge` 简单图模型。
- 不使用 snapshot-based in-memory search 作为产品检索路径。
- App Search 与 Agent Context 使用 `GraphHybridSearchService`。

### 自动化

- Automation rule 可以匹配事件并记录 trigger。
- Automation trigger 进入本地日志和 timeline。
- 高风险自动 mutation 不直接执行。
- 自动归档 action 当前被 repository 明确拒绝。

---

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE) for details.
