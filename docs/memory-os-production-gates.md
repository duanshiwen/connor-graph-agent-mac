# Memory OS Production Gates

Updated: 2026-06-22 17:58 GMT+8

## Gate 1 — Storage foundation

Status: passed.

- `SQLiteMemoryOSStore` exists.
- Migration is idempotent.
- Required L0-L4 tables, indexes, and FTS tables exist.
- WAL, busy timeout and foreign keys are verified.
- Health report distinguishes healthy, warning, and migration-required states.
- Health checks can be persisted to `memory_store_health_checks`.

## Gate 2 — Repository foundation

Status: passed.

- L0-L4 repositories support Memory OS writes.
- Evidence references are persisted before observed/confirmed statements are accepted.
- L2/L4 temporal entity kernel adapter supports stable keys, aliases, temporal statements, and FTS.
- Production operations repository persists LLM artifacts, audit events, metrics, health reports, and queue snapshots.
- L2/L4 statement upsert persists evidence join rows when referenced spans exist.

## Gate 3 — Processing hardening

Status: passed.

- Queue items carry lease, retry, idempotency, payload hash, and dead-letter fields.
- Queue transition service moves failures to retry with backoff, then dead-letter at max attempts.
- Dead-letter payloads are durable in `memory_l1_dead_letter_queue`.
- LLM artifacts are enveloped with schema name/version, model id, content hash, queue/run identity, and raw content.
- LLM artifacts are persisted before validation.
- Structured extraction artifacts must pass JSON decode, schema validation, entity reference validation, and evidence validation before projection.
- Invalid artifacts are rejected with audit events, metrics, and validation diagnostics.

## Gate 4 — H4 projection and promotion runtime

Status: passed for production foundation.

- Accepted `GraphStructuredExtractionOutput` artifacts are deterministically mapped to:
  - L2 nodes
  - L2 statements
  - L3 observed beliefs for high-confidence evidence-backed statements
  - L4 stable entities
  - L4 entity statements
- Rejected artifacts do not write L2/L3/L4 projections.
- Projection batches are persisted across L2/L3/L4 tables, evidence joins, projection ledger and FTS indexes.
- Projection queue jobs are leased before execution.
- Malformed projection payloads are retried/dead-lettered through the same production queue transition path.
- Successful projection jobs mark the queue item succeeded and audit the result.
- `AppMemoryOSBackgroundJobRunner` executes projection queue jobs before operational health reporting.
- `memory_os_project_structured_artifact` exposes a controlled agent tool surface for validated projection.

## Gate 5 — Observability and recovery

Status: passed.

- `AppMemoryOSFacade.operationalSummary` persists health checks and queue pending metric.
- Queue operational snapshot reports pending, leased, processing, retry scheduled, succeeded, failed, dead-letter and expired lease counts.
- Memory OS dashboard exposes retry scheduled and expired lease counts.
- Background runner uses the facade summary rather than old graph background workflow.

## Gate 6 — Agent/App integration

Status: passed.

- Chat messages write L0/L1 through `AppMemoryOSFacade`.
- Native sessions write messages through `AppMemoryOSFacade`.
- Browser selected evidence writes L0/L1 through `AppMemoryOSFacade`.
- Agent memory tools are Memory OS tools; old candidate graph write tools are removed.
- Agent context compiler reads L2/L3/L4 Memory OS context.

## Gate 7 — UI and deletion

Status: passed.

- Memory OS dashboard replaces legacy Graph Memory dashboard.
- Legacy staging, distillation, extraction, admission, candidate review, self-healing and changelog workflow code is deleted.
- Fresh Memory OS and temporal graph kernel migrations do not create old workflow tables.
- Full `swift test` passes.

## H4 validation evidence

- `swift test --filter MemoryOSProjection`
- `swift test --filter MemoryOSProjectionStore`
- `swift test --filter AppMemoryOSProjectionRuntime`
- `swift test --filter AppMemoryOSProjectionQueueWorker`
- `swift test --filter appMemoryOSBackgroundJobRunner`
- `swift test --filter agentLoopRuntimeFactoryRegistersMemoryOSToolsInsteadOfLegacyGraphWriteTools`
- `swift test --filter MemoryOS`
