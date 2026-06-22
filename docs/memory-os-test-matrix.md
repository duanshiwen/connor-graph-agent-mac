# Memory OS Test Matrix

## Domain tests

- identifiers
- Codable round trip
- stable key generation
- status transitions
- validation result modeling

## Store tests

- fresh migration
- repeated migration
- all required tables exist
- all required indexes exist
- all required FTS tables exist
- foreign keys are enforced
- transaction rollback
- WAL mode enabled
- queue lease and recovery
- dead-letter writes
- FTS search

## Import tests

- no legacy tables
- legacy episodes
- legacy entities
- legacy statements
- malformed JSON
- duplicate stable keys
- repeated idempotent import

## Pipeline tests

- pre-ingestion filter
- L0/L1 ingestion
- adaptive time block builder
- queue lifecycle
- LLM artifact preservation
- schema validation
- evidence validation
- projection rebuild
- conflict recording
- L3 belief synthesis
- L4 entity archive

## Agent tests

- context compiler token budgeting
- stale/conflict/uncertainty flags
- read tools
- write tools
- permission integration
- prompt rendering

## AppSupport tests

- chat controller writes L0/L1
- background runner
- recovery worker
- health monitor

## UI presentation tests

- dashboard summary
- health panel model
- queue/dead-letter panel model
- provenance inspector model
- belief review model
- entity profile model

## Regression tests

- fresh schema does not create legacy workflow tables
- legacy staging/distillation/extraction/admission are not referenced by production paths
- full `swift test` passes after deletion phase
