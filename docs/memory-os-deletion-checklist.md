# Memory OS Legacy Deletion Checklist

This checklist records the H-2 physical deletion of the old Graph Memory workflow after Memory OS production paths replaced it.

Updated: 2026-06-22 17:06 GMT+8

## H-2 status

Completed:

- App shell primary route points `graphMemory` to `memoryOS`.
- Chat controller production memory writes route through `AppMemoryOSFacade`.
- Native session manager production memory writes route through `AppMemoryOSFacade`.
- Browser web-page evidence ingestion routes through Memory OS L0/L1 instead of the old graph extraction queue.
- App background jobs run Memory OS health/recovery only; the old graph memory background runner has been removed from the app path.
- Agent memory tools use Memory OS tools; candidate-based graph write tools were removed.
- Legacy staging/distillation services and AppSupport adapters were removed.
- Legacy GraphExtraction / admission hold / self-healing / memory change log / graph write candidate workflow source files were removed.
- Fresh `SQLiteGraphKernelStore` migration no longer creates the old workflow tables.
- Fresh `SQLiteMemoryOSStore` migration has a negative gate proving old workflow tables are not created.

## Removed old source surfaces

### ConnorGraphCore

Removed:

- `GraphExtractionDomain.swift`
- `GraphExtractionDecoder.swift`
- `GraphWriteCandidate.swift`

Retained as reusable schema DTO only:

- `GraphStructuredExtraction.swift` — now validates structured extraction output but no longer converts into the deleted GraphExtraction draft workflow.

### ConnorGraphMemory

Removed:

- `MemoryStaging.swift`
- `MemoryIngestionService.swift`
- `MemoryDistillation.swift`
- `MemoryDistillationService.swift`
- `LLMMemoryDistiller.swift`

Retained graph validators are no longer production memory entrypoints.

### ConnorGraphStore

Removed:

- `AnyGraphExtractorProvider.swift`
- `GraphBackgroundJobRunner.swift`
- `GraphEntityResolutionPlan.swift`
- `GraphExtractionConflictPreview.swift`
- `GraphExtractionPromptBuilder.swift`
- `GraphExtractionReplayService.swift`
- `GraphExtractionTrace.swift`
- `GraphExtractionTracePayload.swift`
- `GraphExtractionWorker.swift`
- `GraphAdmissionHoldQueue.swift`
- `GraphMemoryChangeLog.swift`
- `GraphSelfHealingService.swift`
- `GraphWriteAdmissionPolicy.swift`
- `LLMGraphExtractor.swift`
- `UnavailableGraphExtractor.swift`

Retained:

- `SQLiteGraphKernelStore.swift` as temporal graph/session/kernel storage, with old workflow schema and CRUD removed.

### ConnorGraphAppSupport / ConnorGraphAgentMac

Removed:

- old staging/distillation adapters
- old graph extraction/admission/candidate/changelog repositories
- old graph memory background runner
- old candidate review / diagnostics / changelog views
- old candidate-based agent graph write tools

## Removed old schema creation from normal migration

Fresh stores must not create:

- `memory_staging_buffers`
- `graph_extraction_traces`
- `graph_extraction_trace_payloads`
- `graph_admission_hold_queue`
- `graph_memory_change_log`
- `graph_write_candidates`

Covered by:

- `SQLiteGraphStoreV2Tests.graphKernelStoreMigratesV3CoreTables`
- `SQLiteMemoryOSStoreTests`
- `MemoryOSLegacyDeletionGateTests`

## Deleted or rewritten tests

Deleted old workflow tests for staging, distillation, extraction worker, LLM graph extractor, admission, self-healing, candidate review, and trace store.

Rewritten coverage now lives under:

- `MemoryOS*Tests`
- `AppMemoryOSFacadeTests`
- `AgentLoopChatControllerMemoryOSTests`
- `NativeSessionManagerMemoryOSTests`
- `MemoryOSLegacyDeletionGateTests`

## Final grep gate

Production sources should have no dependency on old workflow names:

```bash
rg "GraphExtraction|GraphWriteCandidate|GraphSelfHealing|AdmissionHold|MemoryChangeLog|graph_write_candidates|graph_extraction|graph_admission|graph_memory_change_log|memory_staging_buffers" Sources Tests -g '*.swift'
```

Allowed matches are only negative assertions inside deletion/schema gate tests.
