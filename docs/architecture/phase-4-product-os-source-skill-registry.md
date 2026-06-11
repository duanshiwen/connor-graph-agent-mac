# Phase 4: Product OS Source and Skill Registry

Last updated: 2026-06-11 17:25 GMT+8

## Status

Phase 4 introduces the first Connor-owned Product OS registry for sources and skills.

This phase is intentionally a governance and product-state slice, not a full MCP/OAuth/skill execution runtime. Connor now has stable local registry models, JSON persistence, validation, seeded built-in entries, native UI visibility, and normalized timeline events for source/skill registry changes.

## Goals

- Make `sources/` and `skills/` first-class local Product OS state under the single Connor Home root.
- Keep the existing no-multi-workspace architecture.
- Preserve Connor sovereignty over credentials, permissions, audit, graph memory admission, and product state.
- Give the native macOS UI a visible Product OS panel for source and skill governance.
- Establish typed models that future MCP Source Runtime and Skill Runtime can build on without letting external SDKs own state.

## Implemented

- `ProductOSRegistrySnapshot`
- `ProductOSSourceDefinition`
- `ProductOSSkillDefinition`
- Typed enums for source kind, credential requirement, skill scope, triggers, and registry status.
- `AppProductOSRegistryRepository`
  - Loads or creates `config/product-os-registry.json`.
  - Seeds default source and skill entries.
  - Ensures `sources/{id}/` and `skills/{id}/` directories exist.
  - Rejects duplicate IDs.
  - Rejects `.allowAll` graph source/skill policies.
- Product OS sidebar view in SwiftUI.
- Product OS summary cards and source/skill registry rows.
- Source/skill status transitions from the native UI.
- Normalized `AgentEvent` cases:
  - `sourceRegistryChanged`
  - `skillRegistryChanged`
- Presentation and persistence payload support for the new events.
- Phase 4 tests for default seeding, single Home root paths, safety validation, and status persistence.

## Boundaries

Allowed in Phase 4:

- Local JSON registry and typed config.
- Native UI visibility.
- Status changes and timeline presentation.
- Directory seeding under the single Connor Home root.
- Guardrails for future source/skill execution.

Deferred:

- Full MCP Source Runtime.
- OAuth and credential entry flows.
- External connector execution.
- Skill manifest parsing/execution.
- Automation engine triggers.
- Graph ingestion jobs from external sources.

## Guardrails

- No multi-workspace abstraction is introduced.
- Source credentials remain Connor-owned and are not stored in registry JSON.
- Source graph writes cannot use `.allowAll`.
- Skill graph context policy cannot use `.allowAll`.
- Skills are instruction profiles, not direct graph memory writers.
- Graph memory remains Connor's governed kernel, not a normal source/RAG plugin.
- Claude SDK sidecar and future SDK engines remain backends only; they do not own Product OS registry state.

## Default Registry Entries

Sources:

- `local-filesystem` — enabled built-in local read surface.
- `mcp-registry-placeholder` — draft placeholder for future MCP/OAuth source runtime.

Skills:

- `graph-memory-review` — enabled built-in profile for reviewing proposed graph memory.
- `session-summary` — enabled built-in profile for session summarization.

## Next Slice

Recommended Phase 5 candidates:

1. MCP Source Runtime skeleton:
   - source process lifecycle
   - credential references
   - per-source permission policy
   - source audit events
2. Skill manifest loader:
   - `SKILL.md` parsing
   - trigger matching
   - before-model-request instruction injection
   - graph context policy enforcement
3. Automation Engine skeleton:
   - status/label/source events as triggers
   - deterministic audit timeline
   - no background execution without Connor permission policy
4. Product OS settings editor:
   - editable source definitions
   - editable skill definitions
   - validation feedback in UI
