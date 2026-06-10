# Native Connor Agent OS Architecture Freeze

Last updated: 2026-06-11

## Status

This document freezes the Phase 0 architecture direction for Connor Graph Agent Mac.

Connor is a **macOS native Graph-Native Agent OS**, not an Electron fork and not a graph-construction tool. Craft Agents OSS is used as a mature architectural reference for session governance, agent backend abstraction, sources, skills, permissions, automations, labels, statuses, settings, and event-driven UI patterns. Its Electron application code is not the implementation base.

## Product Identity

Connor is a general-purpose agent product with a built-in temporal knowledge graph memory kernel.

```text
Connor = macOS native general agent product
Graph = background memory, evidence, reasoning, and long-term intelligence infrastructure
SQLite temporal graph = local truth layer
Claude Agent SDK = optional sidecar agent engine, not the owner of product state
```

Connor must not be described or implemented as only:

- a manual graph editor;
- a graph extraction tool;
- a generic RAG demo;
- a Markdown knowledge-base manager;
- an Electron rebrand of Craft Agents.

## Non-Negotiable Architecture Constraints

### 1. macOS Native First

Connor keeps a native Swift / SwiftUI / AppKit / WebKit architecture.

- The application shell is implemented in SwiftUI/AppKit.
- SQLite remains the local graph truth layer.
- macOS platform integrations are first-class future extension points.
- Electron UI code from Craft Agents OSS is not forked.

### 2. No Multi-Workspace Model

Connor uses a single native application root. It does not introduce Craft-style workspace roots.

Allowed organizing concepts:

- session;
- source;
- skill;
- graph scope;
- project working directory;
- label;
- status;
- automation.

Forbidden organizing concepts:

- `workspaces/{workspaceId}` as a product-level root;
- workspace-scoped copies of sources, skills, labels, statuses, permissions, and automations.

### 3. Session State Belongs to Connor

The SessionManager must own product state.

- User messages are persisted before any model/agent backend starts work.
- Agent backend SDK session IDs are metadata, not primary session IDs.
- Event streams are normalized into Connor `AgentEvent` records.
- Runs, messages, tool calls, graph context snapshots, and audit events are Connor-owned.

### 4. Agent Backend Is Replaceable

Agent backends are engines behind a stable Connor protocol.

Planned backend families:

- `ClaudeSDKSidecarBackend`;
- `OpenAICompatibleBackend`;
- `GraphNativeBackend`;
- `StubBackend` for deterministic tests.

The Claude Agent SDK may provide mature tool loop, MCP, streaming, and hook behavior, but it must not own:

- Connor sessions;
- graph memory state;
- source credentials;
- permission policy;
- audit logs;
- UI state;
- long-term memory writes.

### 5. Graph Memory Is Built-In Infrastructure

The graph is not a normal optional external source. It is a privileged built-in memory kernel.

The graph runtime owns:

- temporal entities and statements;
- evidence episodes;
- memory staging;
- extraction traces;
- write candidates;
- admission policy;
- entity resolution;
- anomaly detection;
- belief status and confidence;
- self-healing jobs;
- graph-backed context assembly.

LLMs may propose graph writes, but production graph commits must pass through Connor policy, trace, and audit boundaries.

### 6. Craft Agents OSS Is a Reference, Not a Codebase to Fork

Connor should learn from Craft Agents OSS in these areas:

- SessionManager pattern;
- AgentBackend / BaseAgent abstraction;
- unified `AgentEvent` stream;
- JSONL/event persistence;
- source and MCP configuration patterns;
- skill folder conventions;
- permission modes;
- labels and statuses;
- automations;
- settings information architecture;
- UI interaction patterns for tool events and approvals.

Connor should not copy:

- Electron app shell;
- multi-workspace storage model;
- workspace-scoped configuration hierarchy;
- any assumption that source/tool runtime is more important than graph memory.

## Native Application Data Root

The Phase 0 storage root is:

```text
~/Library/Application Support/Connor/
```

Required directory hierarchy:

```text
Connor/
  config/
    app.json
    llm-connections.json
    permissions.json
    statuses.json
    labels.json
    automations.json
    preferences.json
    theme.json

  sessions/
    {sessionId}/
      session.json
      events.jsonl
      messages.jsonl
      runs.jsonl
      artifacts/
      data/
      plans/
      graph-context/
      attachments/

  sources/
    {sourceSlug}/
      config.json
      guide.md
      icon.svg

  skills/
    {skillSlug}/
      SKILL.md
      icon.svg

  graph/
    connor.sqlite
    indexes/
    exports/
    snapshots/

  logs/
    audit/
    runtime/

  sidecars/
    claude-agent-engine/
```

The current Phase 0 code freezes the root and required top-level directories through `AppStoragePaths`.

## Module Boundaries

### ConnorGraphCore

Owns stable domain types and protocol-level concepts.

Examples:

- sessions;
- messages;
- runs;
- agent events;
- graph domain types;
- extraction domain types;
- permission/status/label domain types as they are added.

### ConnorGraphStore

Owns durable persistence.

Examples:

- SQLite temporal graph store;
- schema migration;
- graph jobs;
- extraction traces;
- session/event storage as it is promoted from app support;
- audit persistence.

### ConnorGraphMemory

Owns memory staging, distillation, promotion, contradiction detection, and memory policy.

### ConnorGraphSearch

Owns graph search and retrieval abstractions.

Examples:

- hybrid search;
- embedding providers;
- graph search query/result types;
- retrieval trace expansion as it matures.

### ConnorGraphAgent

Owns agent runtime protocols and tool abstractions.

Examples:

- `AgentBackend` protocol evolution;
- tool registry;
- permission request/decision types;
- agent event stream;
- graph tools;
- OpenAI-compatible provider;
- native graph loop backend.

### ConnorGraphAppSupport

Owns app-level service assembly and macOS support services.

Examples:

- `AppStoragePaths`;
- repositories that compose store/runtime objects;
- settings repositories;
- Keychain credential storage;
- sidecar process manager as it is introduced;
- service container / bootstrapper.

### ConnorGraphAgentMac

Owns native UI.

Examples:

- session inbox;
- chat UI;
- graph context and memory candidate panels;
- settings windows;
- source/skill/permission/status/label/automation management UI;
- browser workspace UI.

## Phase 0 Implementation Decisions

1. The app data root is renamed from `ConnorGraphAgent` to `Connor`.
2. The graph database path moves from root-level `connor-graph.sqlite` to `graph/connor.sqlite`.
3. `AppStoragePaths` is the source of truth for native data-root layout.
4. `AppGraphBootstrapper` must create the full required directory hierarchy before opening the graph store.
5. Tests must guard against reintroducing workspace path segments or the old `ConnorGraphAgent` root name.

## Next Phase Entry Criteria

Phase 1 may start when:

- the native root and directory hierarchy are encoded in `AppStoragePaths`;
- tests verify the storage layout;
- this architecture freeze document exists;
- the branch contains no Electron fork assumptions;
- the README or future docs point to this document as the Phase 0 authority.
