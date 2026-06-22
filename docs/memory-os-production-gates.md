# Memory OS Production Gates

Updated: 2026-06-22 19:14 GMT+8

## Gate 1 — Storage foundation

Status: passed.

- `SQLiteMemoryOSStore` exists.
- Migration is idempotent.
- Required L0-L4 tables, indexes, and FTS tables exist.
- WAL, busy timeout and foreign keys are verified.
- Health report distinguishes healthy, warning, and migration-required states.
- Health checks can be persisted to `memory_store_health_checks`.

## Gate 2 — Temporal semantic schema

Status: passed.

- L2/L3/L4 semantic memory records are append-only temporal records.
- Fresh Memory OS schema uses temporal semantic columns:
  - `assertion_kind` for L2/L4 statements
  - `projection_kind` for L3 beliefs/projections
  - `valid_at`, `committed_at`, `projected_at`
  - `source_artifact_id`
- Fresh Memory OS schema does not create semantic governance tables:
  - `memory_l2_conflicts`
  - `memory_l3_conflicts`
- L2/L4 semantic statements do not use `status` or `invalid_at` columns.
- L3 beliefs do not use `status` columns.

## Gate 3 — Processing hardening

Status: passed.

- Queue items carry lease, retry, idempotency, payload hash, and dead-letter fields.
- Queue transition service moves failures to retry with backoff, then dead-letter at max attempts.
- Dead-letter payloads are durable in `memory_l1_dead_letter_queue`.
- LLM artifacts are enveloped with schema name/version, model id, content hash, queue/run identity, and raw content.
- LLM artifacts are persisted before validation.
- Structured extraction artifacts must pass JSON decode, schema validation, entity reference validation, and evidence validation before projection.
- Invalid artifacts are rejected with audit events, metrics, and validation diagnostics.

## Gate 4 — Projection runtime

Status: passed.

- Accepted `GraphStructuredExtractionOutput` artifacts are mapped to L2 nodes/statements, L3 temporal belief projections, L4 stable entities and L4 entity statements.
- Rejected artifacts do not write L2/L3/L4 projections.
- Projection batches are persisted across L2/L3/L4 tables, evidence joins, projection ledger and FTS indexes.
- Projection queue jobs are leased before execution.
- Malformed projection payloads are retried/dead-lettered through the production queue transition path.
- Successful projection jobs mark the queue item succeeded and audit the result.

## Gate 5 — Temporal current view runtime

Status: passed.

- Current L2 statements are derived by temporal query and confidence ordering.
- Current L3 belief projections are derived by temporal query and confidence ordering.
- Current L4 entity profile records are derived from temporal entity statements.
- Historical records are not mutated to express currentness.
- Ambiguous candidates produce diagnostic-only `MemoryOSCurrentViewDiagnostic` records.

## Gate 6 — Observability and recovery

Status: passed.

- `AppMemoryOSFacade.operationalSummary` persists health checks and queue pending metric.
- Queue operational snapshot reports pending, leased, processing, retry scheduled, succeeded, failed, dead-letter and expired lease counts.
- Memory OS dashboard exposes retry scheduled and expired lease counts.
- Background runner executes projection queue jobs before health reporting.

## Gate 7 — Agent/App integration

Status: passed.

- Chat messages write L0/L1 through `AppMemoryOSFacade`.
- Native sessions write messages through `AppMemoryOSFacade`.
- Browser selected evidence writes L0/L1 through `AppMemoryOSFacade`.
- Agent memory tools are Memory OS tools; old candidate graph write tools are removed.
- `memory_os_project_structured_artifact` remains a controlled projection surface, but it writes temporal semantic records rather than governance statuses.

## Gate 8 — UI and deletion

Status: passed.

- Memory OS dashboard replaces legacy Graph Memory dashboard.
- Legacy staging, distillation, extraction, admission, candidate review, self-healing and changelog workflow code is deleted.
- Fresh Memory OS and temporal graph kernel migrations do not create old workflow tables.
- Full `swift test` passes at phase close.

## H5 validation evidence

- `swift test --filter MemoryOSDomain`
- `swift test --filter MemoryOSProjection`
- `swift test --filter MemoryOSProjectionStore`
- `swift test --filter MemoryOSCurrent`
- `swift test --filter MemoryOSSchemaMigration`
- `swift test --filter MemoryOS`
