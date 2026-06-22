# Memory OS Background Pipeline Audit

Updated: 2026-06-22 21:07 GMT+8
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
| Mail | Not yet connected to Memory OS L0/L1 | Mail runtime exists, but no `memoryOSFacade` ingestion calls in mail paths |
| Calendar | Not yet connected to Memory OS L0/L1 | Calendar runtime exists, but no `memoryOSFacade` ingestion calls in calendar paths |
| RSS | Not yet connected to Memory OS L0/L1 | RSS refresh/materializer exists, but no `memoryOSFacade` ingestion calls in RSS paths |
| Browser history | Not yet connected to Memory OS L0/L1 | Browser history store exists separately |
| Attachments / extracted text | Not directly connected to Memory OS L0/L1 | Attachment store/search/evidence candidate path exists separately |
| Media transcription | Stored as session attachment/background output; not directly Memory OS L0/L1 | Media transcription task path exists separately |

## 2. Current L1 threshold and queue mechanism

### What exists

- Durable L1 capture ledger.
- Durable processing queue with leasing, retry, dead-letter, attempts and queue health metrics.
- `MemoryOSTimeBlockBuilder` for token/time-based block construction.
- Dashboard counts pending L1 capture events and queue items.

### What is missing

Current implementation does **not** yet include a full automatic threshold worker that:

1. Reads pending L1 capture events.
2. Applies count / token / age thresholds.
3. Creates 20–30 item processing blocks.
4. Builds an LLM prompt.
5. Lets the LLM choose retrieval.
6. Receives a `GraphStructuredExtractionOutput`.
7. Projects into L2/L4.
8. Marks L1 capture events as processed by that artifact.

Today, `runProjectionQueueOnce` only leases queue items of kind `project_artifact`; those items already contain raw artifact JSON. It does not call an LLM to produce the artifact.

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

There is no dedicated L2 statement processing state table yet for:

- pending knowledge synthesis
- processing
- succeeded
- failed
- ignored
- processed-by artifact ID

There is also no current first-class refinement relation for:

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

There is no automatic worker that:

1. Selects unorganized L2 statements.
2. Blocks them by topic / entity / time / token budget.
3. Builds a knowledge synthesis prompt.
4. Lets the LLM retrieve L2/L3/L4 context.
5. Receives a `MemoryOSKnowledgeExtractionOutput`.
6. Projects accepted candidates into L3/L4.
7. Records which L2 statements were consumed or synthesized.

## 6. Current retrieval and depth mechanism

### What exists

- L0 has FTS.
- L2 nodes/statements have FTS.
- L3 knowledge/beliefs have FTS.
- L4 entities/statements have FTS.
- Legacy graph hybrid search supports FTS + graph expansion + reranking.
- `SQLiteGraphTraversalStore` supports depth-based graph traversal for legacy graph entities.

### What is missing

There is no first-class `MemoryOSUnifiedRetrievalService` yet that searches L1/L2/L3/L4 together and returns a unified hit type with:

- layer
- record ID
- title
- summary/snippet
- score
- evidence refs
- provenance refs
- full-record read capability
- L4 depth expansion capability

There is also no Memory OS-native L4 traversal service yet. The old traversal pattern can be reused, but it is not exposed as a Memory OS read surface.

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

The missing product mechanism is the orchestration layer:

1. L1 block planner and L1→L2 AI job type.
2. L2 statement processing state and L2→L3/L4 AI job type.
3. Unified Memory OS retrieval and L4 depth expansion.
4. Prompt contracts that let AI do the semantic judgment, while program code only validates structure/evidence/references.

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
