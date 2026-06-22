# Memory OS Background Pipeline Runbook

Updated: 2026-06-22 23:12 GMT+8

## Purpose

Connor Memory OS background pipeline turns raw app/source activity into structured memory through governed AI jobs:

```text
L0 provenance
→ L1 active memory buffer
→ L1→L2 AI job
→ GraphStructuredExtractionOutput artifact
→ L2 operational facts + L4 stable entities
→ L2→Knowledge AI job
→ MemoryOSKnowledgeExtractionOutput artifact
→ L3 reusable knowledge + L4 concepts/relations
```

LLMs do not directly write memory truth. They produce structured artifacts. Memory OS persists, validates, audits and projects those artifacts.

## Layer Semantics

| Layer | Role | Retention |
|---|---|---|
| L0 | Raw provenance objects/spans | Long-term retained |
| L1 | Active memory sequence / processing buffer | Physically deleted after successful L1→L2 projection |
| L2 | Operational facts / working memory | Append-only facts |
| L3 | Reusable knowledge records | Validated knowledge artifacts only |
| L4 | Stable entities, concepts and relations | Stable graph records |

Important: L1 is not the audit source of truth. L0 is. Therefore successful L1 processing physically clears the corresponding L1 capture events while preserving L0 material.

## Planning L1→L2 Jobs

Call:

```swift
try facade.enqueueL1ToL2BackgroundJobs()
```

Or schedule via Task Management target:

```text
targetKind: memory_os.pipeline
operationName: plan_l1_to_l2_jobs
```

This reads pending L1 capture events, applies threshold/token policy, builds `MemoryOSL1ToL2JobDraft`, and enqueues:

```text
memory.l1.process_block_to_l2
```

The model worker receives an ordered structured packet:

```json
{
  "l1_capture_events": [
    {
      "capture_event_id": "...",
      "event_type": "...",
      "source_kind": "...",
      "occurred_at": "...",
      "provenance_object_id": "...",
      "span_id": "...",
      "title": "...",
      "content_preview": "...",
      "token_estimate": 0,
      "metadata": {}
    }
  ]
}
```

The Stage 1 prompt policy is:

```text
Read L1 events in chronological order.
Extract candidate facts per event.
Drop noise and unsupported guesses.
Consolidate duplicate facts.
Every emitted fact cites capture_event_id and provenance/span refs.
Do not create L3 knowledge records.
```

The model worker must output:

```text
GraphStructuredExtractionOutput
```

## Running AI Background Queue

Call:

```swift
try facade.runBackgroundAIQueueOnce(executor: executor)
```

The executor conforms to:

```swift
MemoryOSBackgroundModelExecutor
```

Execution path:

```text
queue item
→ decode MemoryOSL1ToL2JobDraft / MemoryOSL2ToKnowledgeJobDraft
→ build MemoryOSBackgroundModelRequest
→ executor returns raw artifact JSON
→ projectAndRecordLLMArtifact(...)
→ validator + projection service
→ queue success/failure
```

## L1 Success Behavior

On accepted L1→L2 projection:

```text
DELETE FROM memory_l1_capture_events WHERE id IN (...)
```

L0 remains intact:

```text
memory_l0_provenance_objects
memory_l0_provenance_spans
```

On executor failure, artifact rejection, retry, or dead-letter:

```text
L1 capture events stay in place
```

## Planning L2→Knowledge Jobs

Call:

```swift
try facade.enqueueL2ToKnowledgeBackgroundJobs()
```

Or schedule via Task Management target:

```text
targetKind: memory_os.pipeline
operationName: plan_l2_to_knowledge_jobs
```

This reads:

```text
memory_l2_statement_processing_state
```

where:

```text
processing_kind = knowledge_synthesis
status = pending
```

It creates `MemoryOSL2ToKnowledgeJobDraft` and enqueues:

```text
memory.l2.synthesize_knowledge
```

The model worker receives an ordered structured packet:

```json
{
  "l2_statements": [
    {
      "statement_id": "...",
      "subject_id": "...",
      "predicate": "...",
      "text": "...",
      "confidence": 0.0,
      "committed_at": "...",
      "evidence_span_ids": [],
      "metadata": {}
    }
  ]
}
```

The Stage 2 prompt policy is conservative:

```text
Most L2 facts should not become L3 knowledge.
High confidence alone is insufficient.
All four knowledge filters must pass.
Accepted candidates must include signal_quality, reuse_scope, novelty and structurability judgment fields.
If existing L3 covers the idea, output no new L3 candidate.
If existing L4 has the concept, reuse it.
```

The model worker must output:

```text
MemoryOSKnowledgeExtractionOutput
```

## L2 Success / Failure Behavior

On accepted projection:

```text
memory_l2_statement_processing_state.status = succeeded
processed_by_artifact_id = artifactID
```

On rejected knowledge artifact:

```text
status = failed
metadata.error_code = projection_validation_failed
```

L2 statements are not overwritten.

## Retrieval Tools

Agent tools now expose Memory OS retrieval and read access:

```text
memory_os_search
memory_os_expand_l4
memory_os_read_record
memory_os_read_provenance
```

`memory_os_search` searches L0/L1/L2/L3/L4 and returns ranked summaries/refs.

`memory_os_expand_l4` expands one L4 entity/concept with depth-limited traversal.

`memory_os_read_record` reads a full Memory OS record from L0/L1/L2/L3/L4 after a search hit or known record id.

`memory_os_read_provenance` reads exact L0 provenance object/span content when raw evidence is required.

Search hits and tool results are context, not truth. Final memory truth still comes from accepted projected records and evidence refs.

Background `MemoryOSBackgroundModelRequest` also carries provider-agnostic `MemoryOSBackgroundToolDescriptor` values. Current executors may still be prompt-in / JSON-out. Future provider adapters can use those descriptors to run an internal tool-calling loop and return final artifact JSON plus tool trace metadata.

## Native Source Event Bridge

`AppMemoryOSNativeSourceEventBridge` provides a common adapter for native sources:

```swift
ingestMailMessage(...)
ingestCalendarEvent(...)
ingestRSSItem(...)
ingestBrowserHistoryEvent(...)
ingestAttachmentText(...)
ingestMediaTranscript(...)
```

Each writes a `source_event` into L0/L1 via `AppMemoryOSFacade.ingestSourceEvent(...)`.

## Failure and Dead Letter

Relevant audit events:

```text
memory_os.background_job.model_failed
memory_os.background_job.artifact_rejected
memory_os.background_job.projected
memory_os.background_job.dead_lettered
memory_os.queue.failure
memory_os.queue.succeeded
memory_os.projection.rejected
memory_os.projection.succeeded
```

Dead-letter queue:

```text
memory_l1_dead_letter_queue
```

Queue attempts:

```text
memory_l1_queue_attempts
```

## Diagnostics

Useful SQL checks:

```sql
SELECT COUNT(*) FROM memory_l0_provenance_objects;
SELECT COUNT(*) FROM memory_l1_capture_events;
SELECT kind, status, attempt_count FROM memory_l1_processing_queue;
SELECT status, COUNT(*) FROM memory_l2_statement_processing_state GROUP BY status;
SELECT event_type, COUNT(*) FROM memory_audit_events GROUP BY event_type;
SELECT COUNT(*) FROM memory_l1_dead_letter_queue;
```

## Production Boundary

Implemented now:

- L0/L1 ingest.
- L1 physical clear after accepted L1→L2 projection.
- L1→L2 and L2→Knowledge job planning.
- AI worker contract and mock/testable executor interface.
- App facade queue execution and artifact projection handoff.
- Failure/retry/dead-letter/audit handling.
- Unified retrieval/read tools and L4 depth expansion.
- Structured L1/L2 prompt packets.
- Background tool descriptors and tool trace boundary types.
- Native source event bridge.
- TaskTargetRunner scheduler target integration.

Still intentionally deferred:

- Real provider-backed `MemoryOSBackgroundModelExecutor` adapter.
- Deep runtime wiring at every source implementation site beyond the common bridge.
- Dedicated `memory_os_read_record` full-record tool.
