# Memory OS Governance Requirements

## Confidentiality

Every provenance object and derived memory record should carry confidentiality metadata when available.

Allowed baseline values:

- public
- internal
- personal
- sensitive
- secret

## Retention

Records should support retention metadata without enforcing deletion in early phases. Deletion or compaction must never silently remove evidence required by active L2/L3/L4 records.

## Audit

Audit events are required for:

- import runs
- ingestion decisions
- queue failures
- dead-letter transitions
- belief confirmation/correction
- entity merge/split
- projection rebuilds

## User correction

User correction must be represented as an explicit event or metadata trail. Corrections should deprecate or supersede prior statements rather than deleting them silently.

## No silent overwrite

L2 statements, L3 beliefs, and L4 entity statements are append-oriented. Updates that change meaning must create supersession, invalidation, correction, or merge/split records.
