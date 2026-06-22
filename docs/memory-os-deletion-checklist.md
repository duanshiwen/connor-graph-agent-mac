# Memory OS Legacy Deletion Checklist

This checklist defines the legacy Graph Memory surface that must be removed after Memory OS production paths replace it.

## Delete or replace source files

### ConnorGraphCore

- `GraphExtractionDomain.swift`
- `GraphExtractionDecoder.swift`
- `GraphStructuredExtraction.swift`
- `GraphOptimisticWriteDomain.swift`
- `GraphSelfHealingDomain.swift`
- `GraphWriteCandidate.swift`

Keep only if a type is explicitly migrated into `MemoryOS*` domain files.

### ConnorGraphMemory

- `MemoryStaging*`
- `MemoryDistillation*`
- `LLMMemoryDistiller*`
- `GraphOptimisticWriteService*`
- `GraphConstraintValidator*` if still tied to old graph write semantics
- `GraphContradictionDetector*` if still tied to old graph write semantics

### ConnorGraphStore

- graph extraction worker
- graph extraction prompt/replay services
- graph write admission policy
- graph self-healing service/store
- graph entity resolver if tied to old graph schema rather than Memory OS L4
- old graph job queue if not reused as Memory OS queue

### ConnorGraphAppSupport

- `AppMemoryStagingBufferRepository.swift`
- `AppMemoryDistillationWorker.swift`
- `AppLLMMemoryDistiller.swift`
- `AppGraphExtractionTraceRepository.swift`
- `AppGraphAdmissionHoldQueueRepository.swift`
- `AppGraphMemoryChangeLogRepository.swift`
- `AppGraphWriteCandidateRepository.swift`

### ConnorGraphAgentMac

- `GraphExtractionDiagnosticsView.swift`
- `GraphWriteCandidateReviewView.swift`
- `MemoryChangeLogView.swift`
- old memory panels in `AppGraphMemoryDashboardBuilder.swift`

## Remove old schema creation from normal migration

- `memory_staging_buffers`
- `graph_extraction_traces`
- `graph_extraction_trace_payloads`
- `graph_admission_hold_queue`
- `graph_memory_change_log`
- `graph_write_candidates`

Legacy tables may be read only by one-time import code. They must not be recreated for fresh Memory OS databases.

## Delete or rewrite tests

- `MemoryStagingTests`
- `MemoryIngestionServiceTests` for legacy staging
- `MemoryDistillationTests`
- `MemoryDistillationServiceTests`
- `LLMMemoryDistillerTests`
- `GraphExtractionWorkerTests`
- `GraphWriteAdmissionPolicyTests`
- `GraphSelfHealingServiceTests`
- `GraphAdmissionHoldQueueActionTests`
- `GraphWriteCandidateReviewTests`
- `MemoryStagingBufferStoreTests`

Rewrite coverage under `MemoryOS*Tests`.

## Final grep gate

Before final merge, this command must show no production dependency on legacy pipeline names:

```bash
rg "MemoryStaging|MemoryDistillation|GraphExtractionWorker|GraphWriteAdmissionPolicy|GraphAdmissionHoldQueue|GraphWriteCandidateReview|GraphSelfHealing" Sources Tests README.md
```

Remaining matches are allowed only inside migration/import documentation or this checklist.
