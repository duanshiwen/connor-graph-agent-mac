# Memory OS Local Embedded Graph-first Search Kernel

Updated: 2026-06-24 22:39 GMT+8

## Decision

Connor Memory OS retrieval will use one local in-process architecture:

- **Embedded Search Kernel**: Rust/Tantivy-based local library for Chinese/full-text candidate retrieval.
- **Graph Retrieval Kernel**: Swift/SQLite graph query layer for L0-L4 graph-complete retrieval.

No external search server, no HTTP sidecar, no daemon lifecycle, and no multi-backend fallback architecture.

## Boundary

```text
Search Kernel: find candidate entry points.
Graph Retrieval Kernel: produce graph-complete answers.
Prompt Contract: force agents to use the right tool for the task.
```

SQLite Memory OS remains the source of truth. The Tantivy index is a derived local index stored next to the Memory OS database under:

```text
~/Library/Application Support/Connor/graph/search-index/memory-os-tantivy/
```

## Layer Graph Semantics

- **L0 Evidence Graph**: provenance objects and spans.
- **L1 Event/Time Graph**: capture events, time blocks, processing queue links.
- **L2 Statement Graph**: nodes, edges, statements, evidence, projections.
- **L3 Belief Graph**: beliefs, belief evidence, belief relations, promotion paths.
- **L4 Entity/Ontology Graph**: entities, aliases, statements, class/property/ontology relations.

## Required Tool Semantics

`memory_os_search` returns candidate records and entry points only. Search hits are not graph-complete answers.

Graph/list/evidence/timeline/cross-layer questions must use graph retrieval tools, including:

- `memory_os_query_graph`
- `memory_os_trace_evidence`
- `memory_os_expand_record_graph`
- `memory_os_l1_query_events`
- `memory_os_l2_find_statements`
- `memory_os_l2_neighbors`
- `memory_os_l3_expand_belief`
- `memory_os_l4_find_entity`
- `memory_os_l4_instances`
- `memory_os_l4_neighbors`

## Acceptance Examples

- `中国` ranks `wikidata:Q148` near the top.
- `中國`, `China`, and `PRC` resolve to `wikidata:Q148` through aliases/normalization.
- `国家` returns country-related classes/properties such as `wikidata:Q6256`, `wikidata:Q3624078`, `wikidata:Q7275`, and `wikidata:P17`.
- `有哪些国家` resolves the country class first, then uses L4 instance graph query over `P31`.
- L3 belief evidence traces through L2 statements to L0 provenance spans.
