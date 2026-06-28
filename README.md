# Connor Graph Agent Mac

文档更新时间：2026-06-28 07:59 GMT+8  
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
Dependencies: none
Linked: sqlite3, Security, EventKit, Contacts, WebKit, AVFoundation, Speech, CoreLocation
Additional source imports: PDFKit, QuickLookUI
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

Main targets:

```text
Sources/ConnorGraphCore        Domain models and governance primitives
Sources/ConnorGraphMemory      Memory OS ingestion, processing, validation and projection
Sources/ConnorGraphStore       SQLite persistence for Memory OS, sessions, audits and sources
Sources/ConnorGraphSearch      Graph / hybrid retrieval and evaluation
Sources/ConnorGraphAgent       Agent loop, tools, providers and policy boundary
Sources/ConnorGraphAppSupport  App services, repositories and native runtime bridges
Sources/ConnorGraphAgentMac    SwiftUI/AppKit macOS shell
Sources/ConnorCLI              Local-only CLI control surface
```

---

## 3. Architecture

```text
SwiftUI Native Shell
  ↓
ConnorGraphAppSupport
  ↓
Session OS / Source Platform / Skill Runtime / Task Surface / Readiness Gate
  ↓
ConnorGraphAgent + Native Model Providers
  ↓
Memory OS Runtime Contract
  ↓
L0 Provenance + L1 Capture Queue + L2 Operational Facts + L3 Knowledge + L4 Entities / Concepts
```

Target responsibilities:

- **ConnorGraphCore**：stable domain models for Memory OS, sessions, policy, attachments, native sources, skills, tasks and automation.
- **ConnorGraphMemory**：pre-ingestion, L0/L1 capture decisions, processing artifacts, validators, L2 projection, L3 promotion and L4 disambiguation.
- **ConnorGraphStore**：SQLite schema, repositories, FTS/search tables, legacy graph import and session/run/audit persistence.
- **ConnorGraphSearch**：retrieval contracts, hybrid search abstractions, evaluation cases and embedding seams.
- **ConnorGraphAgent**：agent orchestration, streaming providers, tool execution, approvals, prompt assembly, compression and local tool policy checks.
- **ConnorGraphAppSupport**：Session Capsule persistence, LLM settings, MCP runtime, attachment services, native Mail/RSS/Contacts/Calendar, browser context, skills and tasks.
- **ConnorGraphAgentMac**：native app shell, chat, composer, approvals, browser workspace, attachments, settings and native source surfaces.
- **ConnorCLI**：local-only programmable control plane; it must respect Connor-owned repositories and policy boundaries.

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

### Memory OS

Connor Memory OS is the production memory boundary. It is not a graph editor, dashboard or direct LLM-write surface.

Layer contract:

- **L0 Provenance Vault**：raw evidence objects and spans.
- **L1 Capture Ledger / Processing Queue**：durable capture events and operational queue state.
- **L2 Operational Memory**：append-only temporal facts extracted from validated evidence.
- **L3 Knowledge Layer**：reusable theories, claims, frameworks, patterns, standards, processes, SOPs and decision bases.
- **L4 Stable Entity / Concept Layer**：stable anchors for people, projects, organizations, work objects and concepts.

Write path:

1. Chat messages, browser selections and native-source evidence enter through `AppMemoryOSFacade`.
2. Raw evidence is preserved as L0/L1.
3. LLMs may propose structured artifacts.
4. Repositories accept projections only after artifact preservation, schema validation, evidence validation, audit logging and transactional projection.

Background AI jobs:

- `memory.l1.unified_projection`：groups pending L1 captures and projects evidence-backed operational facts into L2 plus stable entity facts into L4.
- `memory.l2.synthesize_knowledge`：groups pending L2 statements and promotes only reusable knowledge into L3/L4 through the four filters: signal quality, reuse scope, novelty and structurability.

Important rules:

- High confidence alone never promotes L2 facts to L3.
- Historical semantic records are append-only; currentness is derived by query/current-view logic.
- Processed L1 capture events are physically deleted after accepted projection because L0 remains durable evidence.
- L2 organization state is tracked outside immutable fact rows.
- There is intentionally no `memory_os_dashboard_summary` agent tool.

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

## 6. UI Guidelines

Connor is a native macOS app.

1. Prefer SwiftUI/AppKit/macOS-native components over custom web UI.
2. Pure icon buttons need visible labels or `.accessibilityLabel(...)`; add `.help(...)` where useful.
3. `NSViewRepresentable` / WebKit / PDFKit bridges should preserve platform accessibility semantics.
4. Avoid duplicate sources of truth for sidebar, detail and settings navigation.
5. Use existing design tokens in `AgentChatDesignSystem` / `AppShellDesignSystem` before adding ad-hoc colors or dimensions.
6. Keep chat scrolling, pagination, unread markers and date sections inside the commercial Chat Viewport infrastructure; see `Docs/commercial-chat-viewport-architecture.md` before changing it.
7. Avoid nested navigation titles leaking into macOS window/menu state.
8. Destructive or governance actions must open review surfaces; shortcuts must not bypass Connor policy/review gates.

User-facing copy should use the “康纳同学” voice: warm, precise, local-first and action-oriented. Avoid generic `Something went wrong`, `No data`, or raw error-code-only messages on end-user surfaces.

---

## 7. Development Commands

From the repository root:

```bash
swift build
swift test
swift test --filter Browser
swift run connor --help
```

Useful diagnostics:

```bash
git status --short
swift --version
find Sources Tests -name '*.swift' | wc -l
```

---

## 8. Code Quality Checklist

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
- Keep README concise and architectural; use focused design docs or issues for future work and changelogs.

---

## 9. Deferred / Non-goals

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

## 10. License

See [LICENSE](LICENSE).
