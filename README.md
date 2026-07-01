# Connor Graph Agent Mac

文档更新时间：2026-07-01 11:35 GMT+8  
定位：本 README 只记录当前架构、边界、运行布局和开发约束，不作为历史 changelog。

Connor Graph Agent Mac 是一个 Swift / SwiftUI macOS 应用与 SwiftPM package。它的目标不是图谱编辑器，也不是 LLM SDK 外壳，而是一个本地优先的 **memory-os-native Agent OS**。

核心产品判断：**记忆系统是后台认知基础设施，不是普通用户的前台图谱编辑器。** 用户面对的是会话、数据源、技能、自动化、浏览器、附件、任务和设置；Memory OS 在后台提供连续性、可追溯性、证据化工作记忆、可复用知识层和稳定实体/概念图谱。

---

## 1. Product Boundaries

Connor 当前坚持这些主权边界：  

- **Session OS** owns sessions, runs, journals, approvals, branches, restore snapshots and Session Capsules.
- **Policy Engine** owns permissions, approvals, audit and execution gates.
- **Memory OS** owns memory ingestion, validation, projection, retrieval and current-view derivation.
- **Source Platform** owns source registry, readiness, credentials, policy and ingestion rules.
- **Swift Native Shell** owns the macOS UI; do not introduce Electron/Web UI or fork Craft UI.
- **Task Management Stack** owns scheduled/event task lifecycle, run history and local management surfaces.
- **Attachment Store** owns imported files, manifests, derivatives, extraction state and evidence candidates.
- **Native runtimes** own Mail / RSS / Contacts / Calendar local account boundaries, sync state and cache.

Explicit non-goals:

```text
Public API
Remote daemon / cloud sync
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

## 2. Package

```text
Package: ConnorGraphAgentMac
Swift tools: 6.0
Platform: macOS 14+
Default localization: zh-Hans
Dependencies: none (SQLite via system lib)
Linked: sqlite3, Security, EventKit, Contacts, WebKit, AVFoundation, Speech, CoreLocation
Rust sidecar: SearchKernel (Tantivy embedded search kernel, compiled in-process)
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
- connor-graph-agent-mac    (SwiftUI macOS shell)
- connor                    (local-only CLI)
- ConnorFoundationKGSeedBuilder  (Foundation Knowledge Graph seed tool)
```

Main targets:

```text
Sources/ConnorGraphCore            Domain models and governance primitives
Sources/ConnorGraphMemory          Memory OS ingestion, processing, validation and projection
Sources/ConnorGraphStore           SQLite persistence for Memory OS, sessions, audits and sources
Sources/ConnorGraphSearch          Graph / hybrid retrieval and evaluation
Sources/ConnorGraphAgent           Agent loop, tools, providers and policy boundary
Sources/ConnorGraphAppSupport      App services, repositories, native runtime bridges, MCP
Sources/ConnorGraphAgentMac        SwiftUI/AppKit macOS shell, browser workspace, chat viewport
Sources/ConnorCLI                  Local-only CLI control surface
Sources/ConnorFoundationKGSeedBuilder  Foundation KG seed data builder
```

Tests: 328 source files, 7 test targets across all library modules plus the app shell.

---

## 3. Architecture

```text
SwiftUI Native Shell (chat, sidebar, browser, settings, approvals)
  ↓
ConnorGraphAppSupport (app services, MCP runtime, native source bridges)
  ↓
Session OS / Source Platform / Skill Runtime / Task Surface / Readiness Gate
  ↓
ConnorGraphAgent + Native Model Providers
  ↓
Memory OS Runtime Contract
  ↓
L0 Provenance → L1 Cache Buffer → L2 Operational Facts → L3 Knowledge → L4 Stable Entities
```

Target responsibilities:

- **ConnorGraphCore**：stable domain models for Memory OS, sessions, policy, attachments, native sources, skills, tasks and automation.
- **ConnorGraphMemory**：pre-ingestion, L0/L1 capture decisions, processing artifacts, validators, L2 entity memory, L3 beliefs, L4 entity projection and controlled type normalization.
- **ConnorGraphStore**：SQLite schema, repositories, FTS/search tables, legacy graph import and session/run/audit persistence.
- **ConnorGraphSearch**：retrieval contracts, hybrid search abstractions, evaluation cases and embedding seams.
- **ConnorGraphAgent**：agent orchestration, streaming providers, tool execution, approvals, prompt assembly, compression and local tool policy checks.
- **ConnorGraphAppSupport**：Session Capsule persistence, LLM settings, MCP runtime, attachment services, native Mail/RSS/Contacts/Calendar, browser context, skills and tasks.
- **ConnorGraphAgentMac**：native app shell, chat viewport, composer, approvals, browser workspace, attachments, settings and native source surfaces.
- **ConnorCLI**：local-only programmable control plane; it must respect Connor-owned repositories and policy boundaries.
- **ConnorFoundationKGSeedBuilder**：builds Foundation Knowledge Graph seed databases from structured sources.

Memory OS is deliberately not a user-visible navigation surface. The app can trigger ingestion, scheduling and tool execution, but it should not expose a Memory OS dashboard or direct graph editor.

---

## 4. Runtime Layout

Runtime paths are resolved by `AppStoragePaths` under the user Application Support `Connor` directory.

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

Session Capsule:

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

Key state files include:

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

Credentials and API keys must not be stored in JSON settings files. Use Keychain-backed or equivalent local credential stores.

---

## 5. Current Capability Areas

### Session OS

- Session list, active state, soft deletion, run/event/audit persistence
- Session-local workspace roots and primary root
- Per-session model override
- JSONL records with best-effort recovery
- Browser state and approvals inside Session Capsule

### Local Tools and Workspace Policy

- Session-scoped primary root plus additional allowed roots
- Hidden app-support root for Connor configuration, skills and sources
- File/shell operations must pass Connor policy checks before execution

### Native Model Providers

- OpenAI Responses-native path
- OpenAI-compatible Chat Completions fallback
- Anthropic Messages-native path
- Streaming typed provider events
- Function/tool continuation, reasoning metadata where supported, health checks and per-connection settings
- Providers never own Connor session state, tool execution, approvals, audit or memory projection gates

### Agent Runtime Contract

Every user task should ground itself in this order:

1. Get current time.
2. Retrieve internal context and current user profile when relevant.
3. Search/fetch current web information when freshness or external facts matter.
4. Consider installed skills.
5. Then decide whether to answer, plan, edit, debug, research or ask a clarification.

System prompts are deliberately minimal: only context retrieval and user profile tools are injected. Memory OS write tools are not injected into system prompts; the LLM accesses them through normal tool definitions when needed.

### MCP Source Platform

- Source registry and runtime repository
- HTTP and stdio transport
- Tool discovery and definition-change checks
- Credential materialization without query-string secrets
- Readiness and release-gate checks

### Attachment OS

- Local-first import into Session Capsule
- Text/code/markdown/json/csv/xml/yaml/log/image/document allowlist
- PDFKit extraction for selectable PDFs
- Office/iWork/presentation/spreadsheet extraction through sidecar best-effort paths
- Quick Look / PDFKit native preview

### Browser Workspace

- Session-bound browser tabs and state
- WebKit browsing surface
- History, bookmarks, selection/page prompt folding and shortcut resolution

### Mail / RSS / Contacts / Calendar

- Native source domains and app-support repositories
- Mail draft/send governance: AI may create drafts and request send; real SMTP send requires human approval in the same run
- Sent-message closure: sent cache, audit, receipt and index writeback
- RSS registry/cache/read-state boundaries
- Contacts and Calendar adapter seams
- Native Source Indexed Retrieval with time-aware search filters
- Calendar search should use event interval overlap by default
- Calendar detail reads are captured as memory evidence; title-only reads are not

### Memory OS

Connor Memory OS is the production memory boundary. It is not a graph editor, dashboard or direct LLM-write surface.

- Five-layer architecture: L0 Provenance → L1 Cache Buffer → L2 Operational → L3 Knowledge → L4 Stable Entities.
- LLM-facing tools: 17 total — 13 read tools (`memory_os_context`, `memory_os_search`, `memory_os_read_record`, `memory_os_read_provenance`, `memory_os_get_current_user_profile`, `memory_os_l2_find_entities`, `memory_os_l2_find_statements`, `memory_os_l3_expand_belief`, `memory_os_l3_list_domains`, `memory_os_l4_find_entity`, `memory_os_l4_neighbors`, `memory_os_l4_instances`, `memory_os_expand_l4`) and 4 write tools (`memory_os_l2_update_entities`, `memory_os_update_current_user_profile`, `memory_os_l3_update_beliefs`, `memory_os_l4_update_entities`).
- Full architecture, layer contract, data models, write path, retrieval, ObserveLog and background pipeline → see **Section 6. Memory OS**.

### Skills, Tasks and Automation

- Skill package scanning, lifecycle and prompt augmentation
- Task origins: `system`, `user`, `ai`
- Trigger modes: `scheduled`, `eventTriggered`
- Current user/AI templates:
  - Send a message to a session when that session reaches a status
  - Create a session and send a message at a scheduled time or recurrence
- AI task tools:
  - `tasks_list`
  - `tasks_create_scheduled_session_message`
  - `tasks_create_session_status_message`
- System tasks include Memory OS daily sweeps, 10-minute Mail/Calendar refresh and per-source RSS refresh
- Missed recurring schedules catch up once, then advance to the next future anchor

---

## 6. Memory OS

Memory OS is the cognitive infrastructure backbone of Connor. It is **not** a graph editor, dashboard or direct LLM-write surface.

### 6.1 Layer Architecture

| Layer | Name | Responsibility | Mutability | Data Model |
|-------|------|---------------|------------|------------|
| **L0** | Provenance Vault | Raw evidence objects and spans | **Immutable** | `MemoryOSProvenanceObject`, `MemoryOSProvenanceSpan` |
| **L1** | Cache Buffer | Accumulates events until threshold (≥100 events or ≥24h); triggers unified L2/L3/L4 update | Processed events deleted after accepted projection (L0 retains permanent evidence) | `MemoryOSCaptureEvent`, `MemoryOSQueueItem` |
| **L2** | Operational Memory | Entity-centered working memory extracted from validated evidence | Append-only statements | `MemoryOSNode`, `MemoryOSStatement` |
| **L3** | Knowledge Layer | Reusable theories, claims, frameworks, patterns, standards, SOPs, decision bases | Direct-write by LLM | `MemoryOSBelief` |
| **L4** | Stable Entity / Concept | Relaxed stable anchors for people, projects, organizations, work objects and concepts | Upsert with time-versioning | `MemoryOSEntity`, `MemoryOSEntityStatement` |

L4 uses a controlled entity type vocabulary (`MemoryOSEntityType`); unsupported LLM-provided labels are normalized to `unknown` instead of schema-expanding one-off types. See `Docs/MemoryOS/L4RelaxedEntityGraph.md`.

Read semantics: **query-time current view derivation** — historical semantic records are append-only; currentness is derived by newer validAt → newer committedAt → deterministic id.

```text
                ┌─────────────────────────────────────┐
                │           SwiftUI Shell             │
                │  (chat, sidebar, browser, settings) │
                └──────────────┬──────────────────────┘
                               │
                ┌──────────────▼──────────────────────┐
                │     AppMemoryOSFacade (write gate)  │
                └──────┬───────────────────┬──────────┘
                       │                   │
           ┌───────────▼───┐       ┌───────▼──────────┐
           │  LLM Tools    │       │ Background Jobs  │
           │  (17 tools)   │       │ (unified proj.)  │
           └───┬───┬───┬───┘       └───────┬──────────┘
               │   │   │                   │
    ┌──────────▼┐  │  ┌▼──────────┐  ┌─────▼──────┐
    │    L0     │  │  │  L3       │  │L1→L2+L4   │
    │(immutable)│  │  │(beliefs)  │  │projection  │
    └────┬──────┘  │  └───────────┘  └──┬────┬────┘
         │         │                    │    │
    ┌────▼────┐    │              ┌─────▼┐ ┌─▼────┐
    │   L1    │    │              │  L2  │ │  L4  │
    │ (queue) │    └──────────────┤(nodes│ │(ent.)│
    └─────────┘                   │ stmts│ │relat)│
                                  └──────┘ └──────┘
```

### 6.2 Data Models

**L0/L1 models** (`MemoryOSDomain.swift`):

```swift
// L0: immutable provenance
MemoryOSProvenanceObject  // sourceType, sourceID, title, content, contentHash (SHA256),
                          // occurredAt, ingestedAt, sessionID, workObjectID, confidentiality,
                          // status. Immutable after creation.
MemoryOSProvenanceSpan    // provenanceObjectID, startOffset, endOffset, text. Points to
                          // a slice within the provenance object.

// L1: capture events + queue
MemoryOSCaptureEvent      // provenanceObjectID, eventType, occurredAt, tokenEstimate,
                          // processingState (pending→leased→processing→succeeded|failed|deadLetter)
MemoryOSQueueItem         // kind, status, priority, payloadJSON, attemptCount, maxAttempts,
                          // nextRunAt, lockedAt/By, leaseExpiresAt, idempotencyKey, payloadHash
```

**L2 models** (`MemoryOSDomain.swift`, `MemoryOSL2EntityMemoryService.swift`):

```swift
// L2: operational working memory
MemoryOSNode              // id, stableKey, nodeType, name, summary. Entity anchor in working memory.
MemoryOSStatement         // id, subjectID, predicate, objectID?, text, assertionKind (observed/inferred/summarized),
                          // confidence, validAt, committedAt, evidenceSpanIDs, sourceArtifactID.
                          // Temporal: append-only; currentness derived by query-time logic.

// L2 simplified entity model (for LLM tool interface)
MemoryOSL2StoredEntity    // id, name, type, aliases[], summary, statements[]
MemoryOSL2StoredStatement // id, text, relation, metadata (historical connectedEntityName column preserved)
```

**L3 models**:

```swift
// L3: reusable knowledge beliefs
MemoryOSBelief            // id, statement, domain (normalized discipline domain),
                          // relatedObjectNames (deduplicated, normalized). Domain aliases:
                          // "cs"→"computer-science", "ai"/"ml"→"artificial-intelligence",
                          // "software"→"software-engineering", "memory-os"→"knowledge-management"
```

**L4 models** (`MemoryOSDomain.swift`):

```swift
// L4: stable entities and entity statements
MemoryOSEntity            // id, stableKey (scope:type:name), entityType (controlled vocab),
                          // name, aliases[], summary, confidence, createdAt, updatedAt, validFrom?
MemoryOSEntityStatement   // id, entityID, predicate (MemoryOSL4RelationPredicate),
                          // objectEntityID?, text, assertionKind, confidence,
                          // validAt, committedAt, evidenceSpanIDs, sourceArtifactID
```

**L4 Controlled Entity Type Vocabulary** (`MemoryOSEntityType` — 41 types):

```text
person, organization, group, role, population, place, facility, spatial_object,
concept, theory, framework, discipline, standard, language, metric, identifier_scheme,
creative_work, document, dataset, software, product, media_object, website,
project, event, process, decision, task, rule, agreement,
physical_object, device, vehicle, biological_entity, medical_entity, chemical_entity,
economic_entity, award, unknown
```

Raw LLM labels go through `normalizeRawType()` with 80+ aliases (e.g. `human`→`person`, `company`→`organization`, `method`→`framework`, `app`→`software`, `policy`→`rule`, `workflow`→`process`). Unmatched labels become `unknown`.

**L4 Relation Predicates** (`MemoryOSL4RelationPredicate` — 80+ predicates, 12 categories):

| Category | Predicates (selected) | Retrieval Weight Range |
|----------|-----------------------|-----------------------|
| **Identity** | `SAME_AS`, `ALIAS_OF`, `EQUIVALENT_TO`, `EXACT_MATCH`, `CLOSE_MATCH` | 0.88 – 1.0 |
| **Taxonomy** | `INSTANCE_OF`, `SUBCLASS_OF`, `BROADER_THAN`, `NARROWER_THAN` | 0.9 |
| **Composition** | `HAS_PART`, `PART_OF`, `CONTAINS`, `MEMBER_OF`, `OVERLAPS_WITH` | 0.8 |
| **Dependency** | `DEPENDS_ON`, `REQUIRES`, `ENABLES`, `PREVENTS`, `CONSTRAINS` | 0.72 – 0.8 |
| **Capability** | `SUPPORTS_CAPABILITY`, `IMPLEMENTS`, `USES` | 0.72 – 0.75 |
| **Applicability** | `APPLIES_TO`, `USED_FOR`, `SPECIALIZES`, `GENERALIZES`, `FIELD_OF_WORK`, `IN_INDUSTRY` | 0.7 – 0.75 |
| **Provenance** | `DERIVED_FROM`, `BASED_ON`, `SUPPORTED_BY`, `CITES`, `QUOTES`, `GENERATED_BY`, `VALIDATED_BY`, `ATTRIBUTED_TO` | 0.68 – 0.75 |
| **Governance** | `DECIDES`, `GOVERNS`, `COMPLIES_WITH`, `VIOLATES`, `REPLACES`, `SUPERSEDES`, `DEPRECATES` | 0.72 |
| **Causality** | `CAUSES`, `INFLUENCES`, `MITIGATES`, `RISKS` | 0.65 – 0.7 |
| **Contribution** | `CREATED_BY`, `MAINTAINED_BY`, `OWNED_BY`, `RESPONSIBLE_FOR`, `CONTRIBUTED_BY`, `REVIEWED_BY`, `AUTHORED_BY`, `DEVELOPED_BY`, `FOUNDED_BY`, `WORKS_ON` | 0.68 |
| **Location** | `LOCATED_IN`, `HAS_LOCATION`, `HAS_COORDINATE` | 0.58 – 0.7 |
| **Reference** | `DIFFERENT_FROM`, `OPPOSITE_OF`, `RELATED_TO`, `ASSOCIATED_WITH`, `ABOUT`, `MENTIONS` | 0.4 – 0.62 |

Each predicate has four properties: **category** (1 of 12), **inverse** (optional reverse predicate, e.g. `HAS_PART`↔`PART_OF`), **isSymmetric** (e.g. `SAME_AS`, `RELATED_TO`), **isTransitive** (e.g. `SUBCLASS_OF`, `PART_OF`, `LOCATED_IN`, `DEPENDS_ON`).

### 6.3 LLM Interface (17 tools)

LLM-facing Memory OS tools, registered in `AppMemoryOSAgentTools.swift`:

**Read tools (13):**

| Tool | Layer | Description |
|------|-------|-------------|
| `memory_os_context` | All | Multi-term search across L1–L4, returns flat natural-language memory items |
| `memory_os_search` | All | Full-text search across L0–L4, returns ranked hits with title/summary/matchedText/score |
| `memory_os_read_record` | All | Read a single Memory OS record by layer and ID |
| `memory_os_read_provenance` | L0 | Read L0 provenance object with optional span detail |
| `memory_os_get_current_user_profile` | L2 | Retrieve all current-user personalization facts as flat natural-language strings |
| `memory_os_l2_find_entities` | L2 | Find L2 working-memory entities by exact name or alias |
| `memory_os_l2_find_statements` | L2 | Find L2 statement edges by text, subject ID, and/or predicate filters |
| `memory_os_l3_expand_belief` | L3 | Expand L3 beliefs by ID, domain, or text query |
| `memory_os_l3_list_domains` | L3 | List all L3 discipline domains and belief counts |
| `memory_os_l4_find_entity` | L4 | Find L4 entity nodes by exact ID, stable key, name, or alias |
| `memory_os_l4_neighbors` | L4 | Query outgoing/incoming/both-direction L4 graph neighbors for a known entity ID |
| `memory_os_l4_instances` | L4 | Query L4 graph for instances of one or more class entities (INSTANCE_OF) |
| `memory_os_expand_l4` | L4 | Depth-limited L4 entity neighborhood expansion |

**Write tools (4):**

| Tool | Layer | Description |
|------|-------|-------------|
| `memory_os_l2_update_entities` | L2 | Upsert L2 entities and append statements; entity names split/dedup/upsert |
| `memory_os_update_current_user_profile` | L2 | Append current-user-scoped L2 fact statements |
| `memory_os_l3_update_beliefs` | L3 | Direct-write L3 beliefs (bypasses promotion policy; domain + statement validated) |
| `memory_os_l4_update_entities` | L4 | Direct-write L4 entities and relations; entity type normalized via `MemoryOSEntityType.normalizeRawType()`; structural validation applied |

### 6.4 Write Path

```text
Chat messages ─────────┐
Browser selections ────┤
Native source evidence ┤   ┌─────────────────────────┐
Source events ─────────┼──▶│   AppMemoryOSFacade     │
Attachments ───────────┘   │   (write gate / facade) │
                           └────┬──────────┬─────────┘
                                │          │
                    ┌───────────▼───┐  ┌───▼───────────────┐
                    │ LLM Tools     │  │ Background AI Job │
                    │ (7 tools)     │  │ unified_projection│
                    └──┬──┬──┬──┬───┘  └──┬────────┬───────┘
                       │  │  │  │         │        │
              ┌────────▼┐ │  │ ┌▼───────┐ │  ┌─────▼────┐
              │  L0/L1  │ │  │ │  L3    │ │  │ L2+L4   │
              │(evidence│ │  │ │(belief)│ │  │(projec.)│
              └────┬────┘ │  │ └────────┘ │  └─────────┘
                   │      │  │            │
              ┌────▼────┐ │  └────────────│──── L4 direct write
              │   L1    │ │               │
              │ (queue)─│─┘               │
              └────┬────┘                 │
                   │                      │
                   ▼                      ▼
           ┌───────────────┐    ┌──────────────────┐
           │ L1→L2+L4      │    │ Artifact         │
           │ Unified Proj. │───▶│ Validation +     │
           │ (background)  │    │ Type Normalization│
           └───────────────┘    └──────────────────┘
```

Key write-path rules:

- **Dual write paths**: (1) LLM directly writes L2/L3/L4 in real-time conversation via tools; (2) L1 cache buffer accumulates events and triggers background unified projection when threshold is reached (≥100 events or ≥24h).
- **L1 cache lifecycle**: Events accumulate from all sources → threshold triggers batch projection → LLM produces structured artifact → artifact validated → projected into L2/L3/L4 → processed L1 events physically deleted (L0 retains permanent evidence).
- High confidence alone never promotes L2 facts to L3.
- L4 normalizes raw LLM entity type labels into a controlled vocabulary; unsupported labels become `unknown`.
- L4 does not use LLM-provided confidence or required evidence spans as relation gates.
- L4 relation validation keeps structural checks (subject/object existence, known predicates, self-loop rejection, endpoint type sanity) but not confidence/evidence gates.
- L4 expansion scoring uses predicate weight and graph depth decay, not LLM-provided confidence.
- Historical semantic records are append-only; currentness is derived by query/current-view logic (newer validAt → newer committedAt → deterministic id).
- L2 statements do not require evidence span IDs; the L1→L2 prompt emphasizes fact-first extraction with entity names and relation types.

### 6.5 Retrieval & Context System

**Tool result delivery contract** — all Memory OS read tools return actual data in `contentText` (the field the LLM sees). The `contentJSON` field preserves the full structured payload for programmatic consumers (UI, debugging). `AgentToolResultGate.gatedContent()` selects `contentText` when non-empty; tools must not rely on `contentJSON` being visible to the LLM.

**Hybrid retrieval** — merged ranking across lexical (FTS), semantic (vector) and graph (L4 neighborhood expansion) retrieval modes.

**Context building pipeline** (`MemoryOSContextBuilder`, `MemoryOSContextModels.swift`):

1. Multi-layer retrieval collects relevant records from L0–L4.
2. Context builder assembles: blocks, entity cards, relation cards, evidence snippets.
3. Budget-trimmed to configured limits.
4. Rendered as a `MemoryOSContextPackage` — the LLM's interface to memory.

`MemoryOSContextPackage` contains: executive summary, context text, blocks, entity cards, relation cards, evidence cards, diagnostics, raw retrieval trace, suggested next actions, budget report, quality signals (relevance score, evidence coverage, relation coverage).

Budget defaults: max 8,000 characters, 16 blocks, 10 entity cards, 24 relation cards, 8 evidence cards, 3 evidence refs per block.

**Roles & priorities** (descending):

| Role | Priority | Trigger |
|------|----------|---------|
| `currentUserProfile` | 100 | taskIntent == `.currentUserPersonalization` |
| `conflict` | 95 | conflicting facts in retrieval set |
| `projectState` | 90 | project-related retrieval |
| `operationalFact` | 80 | L2 hits |
| `relation` | 75 | L4 relation hits |
| `stableEntity` | 70 | L4 entity hits |
| `reusableKnowledge` | 65 | L3 hits |
| `evidence` | 60 | L0/L1 hits |
| `uncertainty` | 50 | low-confidence retrieval |
| `historicalContext` | 40 | stale temporal records |
| `nextStepHint` | 30 | suggested next actions |

**Task intents** (`MemoryOSTaskIntent`): `answerQuestion`, `continueConversation`, `updateProject`, `debugCode`, `planWork`, `summarizeMemory`, `verifyClaim`, `resolveEntity`, `listInstances`, `explainRelationship`, `currentUserPersonalization`, `auto`.

### 6.6 ObserveLog (Rolling Buffer)

`ObserveLog.swift` — lightweight short-term buffer for observations that may be worth absorbing into Memory OS.

| Field | Values / Notes |
|-------|---------------|
| Kinds (8) | `operation`, `tool_event`, `insight`, `fragment`, `observation`, `candidate_fact`, `decision_hint`, `user_preference` |
| Sources (7) | `user`, `agent`, `tool`, `import`, `search`, `system` |
| Statuses (4) | `active`, `promoted`, `dismissed`, `expired` |
| Retention | 30 days default |
| Expiring-soon window | 3 days before expiry |
| System task | Daily sweep of expired entries |
| Promotion path | Entry can be promoted to Memory OS node via `promoted(toNodeID:)` |

### 6.7 Background Pipeline

**Trigger conditions** (`MemoryOSL1ProcessingTriggerPolicy`):
- Pending capture events ≥ 100 (`pendingCountThreshold`), **or**
- Oldest pending event age ≥ 24h (`pendingAgeThreshold`), **or**
- Manual trigger via CLI.

**Job types** (`MemoryOSBackgroundJobKind`):
- `memory.l1.unified_projection` — groups pending L1 captures (up to 30 events / 12k tokens per batch), projects operational facts into L2 + stable entity/concept facts into L4. After successful artifact acceptance, processed L1 capture events are physically deleted; L0 retains permanent evidence.
- `memory.l1.synthesize_knowledge` — knowledge candidate synthesis (L2 candidates → L3 beliefs).

**Time-block builder** (`MemoryOSTimeBlockBuilder`): target token limit 60k, hard limit 80k; splits on day boundaries and 3-hour gaps.

**Execution tracking** (`MemoryOSBackgroundRunDomain.swift`): full message/tool-call history per run. `MemoryOSBackgroundRunRecord` (run lifecycle), `MemoryOSBackgroundMessageRecord` (messages), `MemoryOSBackgroundToolCallRecord` (tool calls). Supports idempotency keys, max 3 retries, dead-letter queue.

---

## 7. Search Kernel

The Rust-based Tantivy embedded search kernel (`SearchKernel/`) is compiled as an in-process C-ABI sidecar. It is not a server, daemon or HTTP service.

Responsibilities:
- Chinese/full-text candidate retrieval via Jieba/CJK tokenization
- Tantivy index schema and query execution
- C ABI for Swift in-process calls

Non-responsibilities (owned by Swift/SQLite Graph Retrieval Kernel):
- L1/L2/L3/L4 graph traversal
- Evidence trace
- Instance enumeration
- Timeline aggregation

Build scripts:
- `Scripts/package-search-kernel.sh` — compile and package the Rust sidecar
- `Scripts/verify-memory-os-release.sh` — verify Memory OS release readiness

---

## 8. UI Guidelines

Connor is a native macOS app.

1. Prefer SwiftUI/AppKit/macOS-native components over custom web UI.
2. Pure icon buttons need visible labels or `.accessibilityLabel(...)`; add `.help(...)` where useful.
3. `NSViewRepresentable` / WebKit / PDFKit bridges should preserve platform accessibility semantics.
4. Avoid duplicate sources of truth for sidebar, detail and settings navigation.
5. Use existing design tokens in `AgentChatDesignSystem` / `AppShellDesignSystem` before adding ad-hoc colors or dimensions.
6. Keep chat scrolling, pagination, unread markers and date sections inside the commercial Chat Viewport infrastructure; see `Sources/ConnorGraphAgentMac/ChatViewport/` before changing it.
7. Avoid nested navigation titles leaking into macOS window/menu state.
8. Destructive or governance actions must open review surfaces; shortcuts must not bypass Connor policy/review gates.

User-facing copy should use the "康纳同学" voice: warm, precise, local-first and action-oriented. Avoid generic `Something went wrong`, `No data`, or raw error-code-only messages on end-user surfaces.

---

## 9. Development Commands

From the repository root:

```bash
swift build
swift test
swift test --filter Browser
swift run connor --help
```

Search Kernel (Rust sidecar):

```bash
cd SearchKernel
cargo build
```

Diagnostics:

```bash
git status --short
swift --version
find Sources Tests -name '*.swift' | wc -l
```

---

## 10. Code Quality Checklist

Before claiming a change is complete:

- Run the smallest relevant tests first; run full `swift test` before final handoff when feasible.
- Keep provider, sidecar and source adapters behind Connor-owned policy and audit boundaries.
- Keep credentials out of JSON, prompt context, audit payloads, README examples and source cache records.
- Keep Memory OS writes behind provenance capture, artifact validation, audit logging and projection gates.
- Keep attachment source of truth in Session Capsule / Attachment Store.
- Keep native source search indexes updated or explicitly invalidated after source mutations.
- Preserve temporal metadata in Mail/RSS/Calendar search results.
- Mail sending must never trust model-supplied approval flags; only human approval in `AgentToolExecutionContext.approvedCapabilities(.sendMail)` authorizes SMTP send.
- Add accessibility labels for pure icon controls.
- Prefer structured errors over force unwraps or force casts.
- L4 entity type labels must go through `MemoryOSEntityType.normalizeRawType()`; do not pass raw LLM labels to storage.
- L2 entity operations must go through `MemoryOSL2EntityMemoryService`; do not bypass name-splitting, dedup or upsert logic.
- Keep README concise and architectural; use focused design docs or issues for future work and changelogs.

---

## 11. Deferred / Non-goals

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

---

## 12. License

See [LICENSE](LICENSE).
