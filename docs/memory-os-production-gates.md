# Memory OS Production Gates

## Gate 1 — Storage foundation

- `SQLiteMemoryOSStore` exists.
- Migration is idempotent.
- Required tables, indexes, and FTS tables exist.
- WAL and foreign keys are verified.
- Health report distinguishes healthy, warning, and migration-required states.

## Gate 2 — Repository foundation

- L0-L4 repositories support transactional writes.
- Evidence references are persisted.
- L2/L4 temporal entity kernel adapter supports stable keys, aliases, temporal statements, and FTS.

## Gate 3 — Processing foundation

- Queue supports lease, retry, dead-letter, and stuck lease recovery.
- LLM artifacts are persisted before validation.
- Invalid candidates are rejected with diagnostics.

## Gate 4 — Agent integration

- Chat messages write L0/L1.
- Agent context compiler reads L2/L3/L4.
- Legacy graph write tools are replaced.

## Gate 5 — UI and deletion

- Memory OS dashboard replaces legacy Graph Memory dashboard.
- Legacy Graph Memory pipeline code is deleted.
- Full `swift test` and `swift build` pass.
