# Memory OS L2 Entity Memory Refactor Plan

Current date: 2026-06-27 22:58 GMT+8.

This document is the implementation anchor for the greenfield L2 refactor.
The system is not released and has no legacy data compatibility requirement.

## Goals

- Make L2 an entity-centered working memory layer.
- Keep L0 as the evidence/provenance layer.
- Expose the same L2 operations to LLM tools and CLI through one shared service.
- Remove old external artifact-projection entrypoints from the ordinary LLM-facing tool surface.
- Rewrite the L1-to-L2 prompt so it writes entity updates and statements, not internal artifacts.

## Final external L2 interface

LLM tools:

- `memory_os_l2_find_entities(names)`
- `memory_os_l2_update_entities(entities[])`

CLI commands:

- `connor memory l2 find-entities <names>`
- `connor memory l2 update-entities --json <json>`
- `connor memory l2 update-entities --file <file>`

## Non-goals

The new L2 interface must not expose or require:

- evidence, evidenceText, supportQuote, evidenceSpanIDs
- rawContent, modelID, schemaName, artifactType, processingRunID
- entityID, statementID, artifactID, localID, spanID

## Service boundary

Both LLM tools and CLI call `MemoryOSL2EntityMemoryService`.
The service owns:

- splitting `names` by comma, Chinese comma, dunhao, semicolon, Chinese semicolon, and newline;
- exact matching against L2 node name and aliases;
- upserting entities;
- appending statements;
- creating/reusing connected entities;
- defaulting an omitted relation to `RELATED_TO`;
- skipping duplicate statement text for the same subject.

## L1 prompt contract

L1-to-L2 extraction should:

- identify important entities, aliases, and entity types;
- query L2 by likely names/aliases;
- update L2 with `entities[]`;
- preserve original user phrasing for important negative decisions;
- use `polarity = exclude/reject/cancel/defer` when appropriate;
- avoid creating entities for every noun phrase;
- never ask the model to output evidence or internal artifact fields.

## Golden case

Input idea:

```text
马尼拉一个月，住康莱德，不去贫民窟。
```

Desired L2 statement:

```json
{
  "text": "《迟到的青春期》马尼拉一个月阶段的明确决策是：不去贫民窟。",
  "relation": "RELATED_TO",
  "connectedEntity": "《迟到的青春期》马尼拉一个月阶段",
  "connectedEntityType": "work_object",
  "factType": "decision",
  "polarity": "exclude",
  "originalPhrase": "不去贫民窟"
}
```
