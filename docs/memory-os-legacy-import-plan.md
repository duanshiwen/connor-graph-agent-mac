# Memory OS Legacy Import Plan

## Purpose

Memory OS does not keep the legacy Graph Memory pipeline, but it must protect existing user data stored in the old SQLite temporal graph kernel.

## Imported tables

The importer reads:

- `graph_entities`
- `graph_statements`
- `graph_episodes_v3`

## Import targets

| Legacy table | Memory OS target |
|---|---|
| `graph_entities` | `memory_l4_entities` |
| `graph_statements` | `memory_l4_entity_statements` and/or `memory_l2_statements` |
| `graph_episodes_v3` | `memory_l0_provenance_objects`, `memory_l2_episodes` |

## Non-imported workflow tables

The following are not imported into production memory state:

- `memory_staging_buffers`
- `graph_extraction_traces`
- `graph_extraction_trace_payloads`
- `graph_admission_hold_queue`
- `graph_memory_change_log`
- `graph_write_candidates`

They may be summarized into an import audit event for diagnostics only.

## Required importer behavior

`SQLiteMemoryOSLegacyImporter` must support:

- dry run
- import run id
- idempotent stable mapping
- per-row result records
- malformed JSON diagnostics
- duplicate stable key resolution
- interrupted import resume
- summary audit event

## Safety rules

- Import must run inside bounded transactions.
- Failed rows must not abort the whole import unless schema integrity is at risk.
- Imported records must contain metadata marking their legacy origin.
- New Memory OS production code must not read old tables after import.

## Test cases

- fresh database with no legacy tables
- database with graph episodes only
- database with entities and statements
- duplicate legacy stable keys
- malformed metadata JSON
- repeated import is idempotent
- interrupted import can resume
