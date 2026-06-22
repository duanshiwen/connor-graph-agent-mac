# Memory OS Production Requirements

## Non-goals

- No MVP-only implementation.
- No placeholder-only processing pipeline.
- No LLM-direct database writes.
- No permanent fallback to legacy Graph Memory.
- No silent overwrite of memory facts.

## Storage requirements

`SQLiteMemoryOSStore` must set and verify:

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
PRAGMA temp_store = MEMORY;
```

Migrations must be:

- idempotent
- versioned
- testable on fresh databases
- testable on repeated migration
- safe for existing databases

## Queue requirements

Processing queue states:

- pending
- leased
- processing
- succeeded
- retry_scheduled
- failed
- dead_letter
- cancelled

Required queue fields:

- attempt_count
- max_attempts
- next_run_at
- locked_at
- locked_by
- lease_expires_at
- idempotency_key
- payload_hash
- error_code
- error_message

## LLM processing requirements

The LLM may propose normalized memory candidates, but it must not directly write L2/L3/L4.

Required flow:

1. Save processing run.
2. Save prompt and raw response artifact.
3. Decode JSON.
4. Normalize.
5. Validate schema.
6. Validate evidence references.
7. Apply conflict policy.
8. Commit in a repository transaction.
9. Refresh projections.
10. Write audit event and metrics.

## Evidence requirements

Every L2 statement, L3 belief, and L4 entity statement must be traceable to:

- L0 provenance object, or
- L0 provenance span, or
- an imported legacy graph episode with import metadata.

## Recovery requirements

The system must support:

- stuck lease recovery
- retry with backoff
- dead-letter inspection
- health reports
- artifact preservation
- migration/import run diagnostics

## UI requirements

Production UI must include:

- Memory OS dashboard
- storage health panel
- processing queue panel
- dead-letter queue panel
- provenance inspector
- belief review/correction view
- entity profile view
- migration/import result view

Legacy Graph Memory UI must be removed during the final deletion phase.
