# Memory OS Background Pipeline Audit

Updated: 2026-06-22 21:58 GMT+8
Branch: `feature/memory-os-l0-l4-production-refactor`

This document audits the current Connor Memory OS implementation against the intended two-stage AI background memory pipeline:

1. L0/L1 raw activity capture → AI extraction → L2 operational facts.
2. Unorganized L2 facts → AI synthesis → L3 reusable knowledge + L4 concepts/relations + refined L2 facts.

## 1. Current L0/L1 capture mechanism

### What exists

Current domain and store support:

- `MemoryOSProvenanceObject`
- `MemoryOSProvenanceSpan`
- `MemoryOSCaptureEvent`
- `MemoryOSTimeBlock`
- `MemoryOSQueueItem`
- L0 FTS: `memory_l0_provenance_fts`
- L1 queue tables: `memory_l1_processing_queue`, attempts and dead-letter queue

Current service path:

```text
MemoryOSIngestionInput
→ MemoryOSIngestionService.ingest
→ MemoryOSProvenanceObject
→ MemoryOSProvenanceSpan
→ MemoryOSCaptureEvent
→ AppMemoryOSRepository.save
→ SQLiteMemoryOSStore
```

L1 capture events already contain:

- `provenanceObjectID`
- `eventType`
- `occurredAt`
- `tokenEstimate`
- `processingState`
- metadata, including `span_id`

`MemoryOSTimeBlockBuilder` already groups capture events by:

- chronological order
- day boundary
- time gap greater than three hours
- target token limit
- hard token limit

### Source coverage today

| Source | Current Memory OS L0/L1 status | Evidence |
|---|---|---|
| User chat messages | Connected | `NativeSessionManager.persistMemoryOSAfterUserMessage`, `AgentLoopChatController.persistMemoryOSAfterUserMessage` |
| Assistant chat messages | Connected | `NativeSessionManager.persistMemoryOSAfterAssistantMessage`, `AgentLoopChatController.persistMemoryOSAfterAssistantMessage` |
| Browser selection / webpage evidence | Connected for explicit save action | `AppViewModel.saveBrowserSelectionAsEpisode` → `ingestWebPageEvidence` |
| Mail | Adapter entry exists; runtime call sites still need wiring | `AppMemoryOSFacade.ingestSourceEvent(sourceKind: "mail", ...)` now writes source events into L0/L1 |
| Calendar | Adapter entry exists; runtime call sites still need wiring | `ingestSourceEvent(sourceKind: "calendar", ...)` can be used by calendar runtime |
| RSS | Adapter entry exists; runtime call sites still need wiring | `ingestSourceEvent(sourceKind: "rss", ...)` can be used by RSS refresh runtime |
| Browser history | Adapter entry exists; history call sites still need wiring | `ingestSourceEvent(sourceKind: "browser_history", ...)` can be used by browser history store |
| Attachments / extracted text | Adapter entry exists; attachment call sites still need wiring | `ingestSourceEvent(sourceKind: "attachment", ...)` can ingest extracted text summaries |
| Media transcription | Adapter entry exists; transcription call sites still need wiring | `ingestSourceEvent(sourceKind: "media_transcription", ...)` can ingest transcript summaries |

## 2. Current L1 threshold and queue mechanism

### What exists

- Durable L1 capture ledger.
- Durable processing queue with leasing, retry, dead-letter, attempts and queue health metrics.
- `MemoryOSTimeBlockBuilder` for token/time-based block construction.
- Dashboard counts pending L1 capture events and queue items.

### What is missing

Current implementation now includes the first orchestration layer:

1. `MemoryOSL1ProcessingTriggerPolicy` applies count / token / age thresholds.
2. `MemoryOSL1ToL2JobPlanner` creates 20–30 item style processing blocks.
3. `MemoryOSL1ToL2PromptBuilder` builds the prompt contract for L1→L2 fact extraction.
4. `AppMemoryOSFacade.enqueueL1ToL2BackgroundJobs(...)` writes queue items of kind `memory.l1.process_block_to_l2`.

Implemented now: `MemoryOSBackgroundJobWorker` builds model requests through `MemoryOSBackgroundModelExecutor`, and `AppMemoryOSFacade.runBackgroundAIQueueOnce(...)` leases `memory.l1.process_block_to_l2` jobs, receives `GraphStructuredExtractionOutput`, and hands it to `projectAndRecordLLMArtifact(...)`. On accepted projection, processed L1 capture events are physically deleted because L0 keeps the durable raw provenance.

Still deferred: a real provider-backed executor adapter. Tests use mock/static executors through the protocol boundary.

## 3. Current artifact validation and projection mechanism

### What exists

Current artifact path:

```text
raw structured JSON
→ MemoryOSLLMArtifactEnvelope
→ memory_l2_processing_artifacts
→ MemoryOSLLMArtifactValidator
→ MemoryOSProjectionService.projectionBatch
→ SQLiteMemoryOSStore.saveProjectionBatch
→ audit + metrics
```

Supported schemas:

- `GraphStructuredExtractionOutput`
- `MemoryOSKnowledgeExtractionOutput`

`GraphStructuredExtractionOutput` currently projects:

- L2 nodes
- L2 operational statements
- L4 stable entities
- L4 entity statements
- no L3 knowledge records

`MemoryOSKnowledgeExtractionOutput` currently projects:

- L3 knowledge records, currently persisted through compatible `memory_l3_beliefs` tables
- L4 concept entities
- L4 concept relations as entity statements
- no L2 statements

### Program vs AI boundary

Current validator is deterministic and contract-level only:

- schema can decode
- required entity references exist
- statement evidence is present
- knowledge candidate includes explicit four-dimension assessment
- accepted knowledge candidate has required structure
- concept relation references existing concept entities

It does **not** semantically decide whether a claim is truly knowledge. That judgment belongs in the prompt and LLM output.

## 4. Current L2 organization state

### What exists

L2 statements include:

- subject / predicate / object
- text
- assertion kind
- confidence
- valid time / committed time
- evidence span IDs
- source artifact ID
- metadata

L2 projections and projection items tables exist.

### What is missing

A dedicated L2 statement processing state table now exists:

- `memory_l2_statement_processing_state`
- `MemoryOSL2StatementProcessingState`
- `SQLiteMemoryOSStore.upsert(l2ProcessingState:)`
- `SQLiteMemoryOSStore.l2ProcessingStates(...)`

It supports pending / processing / succeeded / failed style statuses, processing kind, source artifact ID, processed-by artifact ID, last attempt time and metadata.

There is still no current first-class refinement relation for:

```text
old L2 statement → refined L2 statement
```

Current append-only principle should be preserved. “Update L2 description” should mean append a refined statement and link it to prior records, not overwrite historical facts.

## 5. Current L2 → L3/L4 synthesis mechanism

### What exists

The target schema and projection boundary now exist:

```text
MemoryOSKnowledgeExtractionOutput
→ MemoryOSLLMArtifactValidator
→ MemoryOSProjectionService
→ L3 knowledge + L4 concept graph
```

### What is missing

Current implementation now includes the first orchestration layer:

1. `MemoryOSL2KnowledgeSynthesisTriggerPolicy` selects pending L2 statements.
2. `MemoryOSL2ToKnowledgeJobPlanner` blocks them by count / token budget.
3. `MemoryOSL2ToKnowledgePromptBuilder` builds the knowledge synthesis prompt.
4. `AppMemoryOSFacade.enqueueL2ToKnowledgeBackgroundJobs(...)` writes queue items of kind `memory.l2.synthesize_knowledge`.

Implemented now: `AppMemoryOSFacade.runBackgroundAIQueueOnce(...)` leases `memory.l2.synthesize_knowledge` jobs, executes them through `MemoryOSBackgroundModelExecutor`, receives `MemoryOSKnowledgeExtractionOutput`, projects accepted candidates into L3/L4, and marks `memory_l2_statement_processing_state` succeeded or failed.

Still deferred: a real provider-backed executor adapter with live retrieval calls during the model turn. The retrieval tool surface exists and can be used by a future executor/agent loop.

## 6. Current retrieval and depth mechanism

### What exists

- L0 has FTS.
- L2 nodes/statements have FTS.
- L3 knowledge/beliefs have FTS.
- L4 entities/statements have FTS.
- Legacy graph hybrid search supports FTS + graph expansion + reranking.
- `SQLiteGraphTraversalStore` supports depth-based graph traversal for legacy graph entities.

### What is missing

A first-class SQLite retrieval surface now exists:

- `MemoryOSRetrievalLayer`
- `MemoryOSRetrievalQuery`
- `MemoryOSRetrievalHit`
- `SQLiteMemoryOSUnifiedRetrievalService.search(...)`
- `SQLiteMemoryOSUnifiedRetrievalService.expandL4(entityID:depth:limit:)`

It searches L0/L1/L2/L3/L4, returns layer-aware hits with evidence/provenance/entity refs, and supports L4 depth expansion over entity statements.

## 7. Recommendation

The user’s target architecture maps well onto the current Memory OS direction. The project already has the important lower-level pieces:

- L0 provenance
- L1 capture/queue
- artifact envelope
- validation
- projection
- L2 fact schema
- L3 knowledge schema
- L4 entity/concept schema
- FTS tables

The remaining missing product mechanism is now narrower:

1. Real provider-backed `MemoryOSBackgroundModelExecutor` adapter.
2. Deep call-site wiring from every Mail / Calendar / RSS / browser history / attachment extraction / media transcription runtime path into `AppMemoryOSNativeSourceEventBridge`; the common bridge exists and is tested.
3. Optional `memory_os_read_record` full-record read tool; search and L4 expansion already exist.
4. Product policy for cleanup/quarantine of dead-lettered L1 buffers. Successful L1 processing already physically clears L1; failure paths keep L1 for retry.

## 8. Implementation principle

Do not physically clear L1 after processing. Instead:

```text
mark processed / succeeded / archived from active queue
```

Do not overwrite L2 statements when improving them. Instead:

```text
append refined L2 statement
record derivation/projection metadata
current view chooses the best current statement
```

Do not let program code decide semantic knowledge value. Instead:

```text
Prompt + LLM decide semantic classification
Program validates artifact contract and evidence chain
```
