# Memory OS Phase Log

## Phase A — Production architecture and deletion boundary

Status: implemented and committed.

Artifacts:

- `MEMORY_OS_REFACTOR.md`
- `docs/memory-os-production-requirements.md`
- `docs/memory-os-deletion-checklist.md`
- `docs/memory-os-legacy-import-plan.md`
- `docs/memory-os-test-matrix.md`

Purpose:

- Lock production-grade requirements.
- Prevent long-lived legacy Graph Memory coexistence.
- Define what can be migrated from the old SQLite temporal graph kernel.
- Define what must be deleted after replacement.

## Phase B/C — Storage foundation, domain, repositories and kernel adapter

Status: implemented and committed.

Artifacts:

- `MemoryOSDomain.swift`
- `SQLiteMemoryOSStore.swift`
- `MemoryOSRepositories.swift`
- `MemoryOSTemporalEntityKernelAdapter.swift`
- MemoryOS schema, health report, FTS tables and no-legacy-workflow-table tests

Test evidence:

- `swift test --filter MemoryOS` passed with 18 MemoryOS tests after this phase.

## Phase D/E/F — Production service layer and Agent runtime interfaces

Status: implemented and committed.

Artifacts:

- `MemoryOSServices.swift`
- `MemoryOSAgentRuntime.swift`
- ingestion, time block builder, validators, projection, belief/entity/recovery services
- context compiler, read tools and write tools

Test evidence:

- `swift test --filter MemoryOS` passed with 35 MemoryOS tests after this phase.

## Phase F/G partial — AppSupport ingestion and dashboard presentation foundation

Status: implemented and committed.

Artifacts:

- `AppMemoryOSRepository.swift`
- `AgentLoopChatController` optional Memory OS L0/L1 ingestion path
- `MemoryOSUIPresentation.swift`
- MemoryOS dashboard presentation tests

Test evidence:

- `swift test --filter MemoryOS` passed with 39+ MemoryOS tests as presentation/facade coverage expanded.

## Phase H-1 — Production entrypoint cutover before physical deletion

Status: implemented and committed.

Commits:

- `69ffb7e` — `feat: add App Memory OS facade`
- `003ca6b` — `feat: route chat memory writes through Memory OS facade`
- `d3efeae` — `feat: expose Memory OS dashboard in app shell`
- `e72be84` — `feat: run Memory OS background jobs from app`
- `fcd727c` — `feat: persist native sessions through Memory OS`
- `f243de2` — `refactor: route graph memory surface to Memory OS`

Artifacts:

- `AppMemoryOSFacade.swift`
- `MemoryOSDashboardView.swift`
- Memory OS database path: `graph/memory-os.sqlite`
- App shell `graphMemory` route now resolves to `memoryOS`
- `AgentLoopChatController` and `NativeSessionManager` now write user/assistant messages to Memory OS L0/L1 through `AppMemoryOSFacade`
- App background jobs now run Memory OS health/recovery summary before transitional legacy jobs

Deletion status:

- H-1 completed production entrypoint cutover.
- H-2 later completed physical deletion/isolation of old staging, distillation, extraction, admission, candidate-review, self-healing and change-log workflows.

## Phase H-2 — physical deletion / isolation of old Graph Memory workflow

Completed on 2026-06-22 17:06 GMT+8.

Commits:

- `149649f test: add Memory OS legacy deletion gates`
- `21a58e8 refactor: route agent memory tools through Memory OS`
- `7295df0 refactor: remove legacy graph memory state from app view model path`
- `20fecbd refactor: remove legacy graph memory UI`
- `2a44696 refactor: replace graph memory background jobs with Memory OS runner`
- `301b117 refactor: remove legacy graph memory app support adapters`
- `49f182d refactor: remove legacy memory staging and distillation`
- `d1c8f3e refactor: remove legacy graph write agent tools`
- `35dd479 refactor: ingest browser evidence through Memory OS`
- `f3896c1 refactor: delete legacy graph extraction workflow`

Artifacts:

- `AppMemoryOSFacade` is the app-level Memory OS boundary for chat, native sessions, dashboard, background recovery, agent tools, and browser evidence ingestion.
- `SQLiteGraphKernelStore` is retained only as temporal graph/session/kernel storage; old workflow schema and CRUD were removed.
- Fresh kernel and Memory OS migrations no longer create old workflow tables.
- Old GraphExtraction/admission/self-healing/change-log/candidate workflow source and tests were physically removed.

Validation evidence:

- `swift test --filter AppViewModelMemoryOSCutover && swift test --filter MemoryOS && swift test` after browser evidence cutover: 1001 tests / 115 suites passed.
- `swift test --filter SQLiteGraphStoreV2 && swift test --filter MemoryOS && swift test` after old workflow physical deletion: 964 tests / 115 suites passed.
- Final Swift grep gate leaves old workflow names only in negative schema/deletion assertions.

## Phase H-3 — production hardening foundation

Completed on 2026-06-22 17:42 GMT+8.

Commits:

- `f55af7e feat: harden Memory OS production pipeline`
- `6152d7a feat: expose Memory OS queue observability`

Artifacts:

- `MemoryOSLLMArtifactEnvelope` records raw model output with schema name/version, model id, content hash, queue item id and processing run id.
- `MemoryOSLLMArtifactValidator` validates structured extraction JSON, entity references and evidence before any projection/write path accepts the artifact.
- `MemoryOSQueueTransitionService` implements retry-with-backoff and dead-letter transition semantics.
- `SQLiteMemoryOSStore` persists LLM artifacts, queue attempts, dead letters, audit events, processing metrics and health reports.
- `AppMemoryOSFacade` exposes validated artifact recording, queue failure recording, persisted health checks and operational queue snapshot.
- Memory OS dashboard now surfaces retry scheduled counts and expired queue leases.

Validation evidence:

- `swift test --filter MemoryOSProductionHardening` passed.
- `swift test --filter MemoryOSProductionOperations` passed.
- `swift test --filter AppMemoryOSProductionHardening` passed.
- `swift test --filter MemoryOSDashboard` passed.
- `swift test --filter MemoryOS` passed with 58 MemoryOS tests.

## Phase H-4 — projection / promotion runtime

Completed on 2026-06-22 17:58 GMT+8.

Commits:

- `df58154 feat: add Memory OS projection runtime mapping`
- `cf36a58 feat: persist Memory OS projection batches`
- `2d04800 feat: run Memory OS projections through facade`
- `fd040a0 feat: add Memory OS projection queue worker`
- `16b9081 feat: run Memory OS projections in background jobs`
- `621e840 feat: expose Memory OS projection agent tool`
- `a1c5f16 test: assert automatic Memory OS evidence joins`

Artifacts:

- `MemoryOSProjectionQueuePayload` defines durable queued projection work.
- `MemoryOSProjectionBatch` and `MemoryOSProjectionRunSummary` define the L2/L3/L4 projection runtime contract.
- `MemoryOSProjectionService` maps accepted structured extraction artifacts into L2 nodes/statements, L3 high-confidence observed beliefs, L4 stable entities and L4 entity statements.
- `SQLiteMemoryOSStore.saveProjectionBatch` persists projection results across L2/L3/L4 tables, projection ledger, FTS and evidence joins.
- `AppMemoryOSFacade.projectAndRecordLLMArtifact` runs artifact persistence, validation, projection, audit, metric and queue success/failure transitions as one application boundary.
- `AppMemoryOSFacade.runProjectionQueueOnce` leases runnable `project_artifact` queue jobs and executes them through the production projection path.
- `AppMemoryOSBackgroundJobRunner` now executes projection queue jobs before health/operational reporting.
- `memory_os_project_structured_artifact` exposes the controlled agent tool surface for projection.

Validation evidence:

- `swift test --filter MemoryOSProjection` passed.
- `swift test --filter MemoryOSProjectionStore` passed.
- `swift test --filter AppMemoryOSProjectionRuntime` passed.
- `swift test --filter AppMemoryOSProjectionQueueWorker` passed.
- `swift test --filter appMemoryOSBackgroundJobRunner` passed.
- `swift test --filter agentLoopRuntimeFactoryRegistersMemoryOSToolsInsteadOfLegacyGraphWriteTools` passed.
- `swift test --filter MemoryOS` passed with 66 MemoryOS tests.

## Phase H-5 — temporal semantic memory refactor

Completed on 2026-06-22 19:14 GMT+8.

Core invariant:

- L2, L3 and L4 semantic memory records are append-only temporal records.
- Historical semantic records are not mutated to express currentness.
- Current memory is derived by query/view logic using temporal ordering, confidence and evidence.
- Ambiguity is diagnostic-only and does not block writes or mutate old records.
- Operational statuses remain valid for queue, artifact validation and health reporting.

Commits:

- `d1bb728 refactor: make Memory OS semantic records temporal`
- `d67609e feat: add Memory OS temporal current view`
- `2ab1c61 refactor: simplify Memory OS record status`
- `d554cc1 refactor: remove Memory OS semantic conflict schema`
- `a60af84 refactor: show Memory OS diagnostics instead of conflicts`

Artifacts:

- `MemoryOSAssertionKind` replaces L2/L4 semantic lifecycle status.
- `MemoryOSProjectionKind` replaces L3 belief lifecycle status.
- `MemoryOSStatement`, `MemoryOSBelief` and `MemoryOSEntityStatement` now carry temporal/source fields rather than confirmed/conflicted/deprecated/superseded semantics.
- `MemoryOSCurrentViewService` derives current L2/L3/L4 views from append-only records.
- `MemoryOSCurrentViewDiagnostic` records ambiguity as non-blocking diagnostics.
- `SQLiteMemoryOSStore` schema version advanced to v2 with temporal semantic columns:
  - `assertion_kind`
  - `projection_kind`
  - `valid_at`
  - `projected_at`
  - `source_artifact_id`
- L2/L3 semantic conflict tables were removed from fresh Memory OS schema.
- Memory OS dashboard/tool output now shows temporal diagnostics rather than conflict counts.

Validation evidence:

- `swift test --filter MemoryOSDomain` passed.
- `swift test --filter MemoryOSProjection` passed.
- `swift test --filter MemoryOSProjectionStore` passed.
- `swift test --filter MemoryOSCurrent` passed.
- `swift test --filter MemoryOSSchemaMigration` passed.
- `swift test --filter MemoryOS` passed with 69 MemoryOS tests.
- `swift test --filter AgentLoopChatControllerMemoryOS`, `swift test --filter NativeSessionManagerMemoryOS`, and `swift test --filter MemoryOSDashboard` passed after removing conflict table queries.
