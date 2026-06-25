# Memory OS Local Embedded Graph-first Search Kernel

Updated: 2026-06-25 08:20 GMT+8

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

## Layer Semantics

- **L0 Evidence Layer**: durable provenance objects and spans. L0 is the evidence endpoint for tracing and direct provenance reading, not a standalone Graph Retrieval Kernel tool surface.
- **L1 Capture/Event Layer**: capture events, time blocks, processing queue links, and background pipeline state. L1 is primarily operational/pipeline context, not a standalone Graph Retrieval Kernel tool surface.
- **L2 Statement Graph**: nodes, edges, statements, evidence refs, and projections.
- **L3 Belief Graph**: beliefs, belief evidence, belief relations, and promotion paths.
- **L4 Entity/Ontology Graph**: entities, aliases, statements, class/property/ontology relations.

The product-facing Graph Retrieval Kernel is intentionally centered on **L2/L3/L4**. L0 is reached through evidence tracing or direct provenance read by known id; L1 remains a background ingestion/processing layer.

## Required Tool Semantics

`memory_os_search` returns candidate records and entry points only. Search hits are not graph-complete answers.

Graph/list/evidence/cross-layer questions must use graph retrieval tools. Implemented tools now include:

- `memory_os_query_graph`: orchestrates layered graph retrieval across L2/L3/L4 and optional L0 evidence tracing.
- `memory_os_trace_evidence`: traces L3 beliefs or L2 statements to L0 provenance spans/objects.
- `memory_os_l2_find_statements`: queries the L2 statement graph by text, subject, and predicate.
- `memory_os_l3_expand_belief`: expands L3 beliefs into supporting L2 statements.
- `memory_os_l4_find_entity`: resolves L4 entities/classes/properties by id, name, stable key, or alias.
- `memory_os_l4_instances`: enumerates class membership, especially P31 instance-of questions.
- `memory_os_l4_neighbors`: traverses L4 outgoing/incoming/both-direction relationship neighborhoods.
- `memory_os_expand_l4`: legacy/baseline stable entity context expansion.

Standalone L0/L1 Graph Retrieval Kernel tools are intentionally out of scope. Future work should deepen L2/L3/L4 orchestration and evidence tracing rather than exposing L1 event/time or L0 provenance as graph-query tools.

## CLI and Release Operations

Search index lifecycle commands:

```bash
connor memory search-index stats
connor memory search-index verify
connor memory search-index rebuild
```

`search-index verify` checks:

- embedded dylib exists and can be used;
- source SQLite database exists;
- Tantivy index directory exists;
- Connor `connor-meta.json` exists;
- index schema version is current;
- document count is positive;
- source database fingerprint is current enough by key table counts and file sizes;
- smoke queries for Chinese, Wikidata ids, class terms, and properties return hits.

Unified L2/L3/L4 graph query CLI:

```bash
connor memory query-graph <text> \
  [--intent auto|l2Statements|l3Beliefs|l4Entity|l4Neighbors|l4Instances|evidence] \
  [--entity wikidata:Q148] \
  [--class wikidata:Q6256,wikidata:Q3624078] \
  [--predicate P31,P17] \
  [--direction outgoing|incoming|both] \
  [--include-evidence] \
  [--limit N]
```

Release packaging and validation:

```bash
Scripts/package-search-kernel.sh --app-bundle /path/to/Connor.app
Scripts/package-search-kernel.sh --output-dir .build/search-kernel-release
Scripts/verify-memory-os-release.sh
```

The release gate packages the Rust/Tantivy dylib, runs SearchKernel FFI/search quality/graph CLI/tool registry/prompt contract tests, and performs live `search-index verify` unless `--skip-live-verify` is supplied.

## Acceptance Examples

- `中国` ranks `wikidata:Q148` near the top.
- `中國`, `China`, and `PRC` resolve to `wikidata:Q148` through aliases/normalization.
- `国家` returns country-related classes/properties such as `wikidata:Q6256`, `wikidata:Q3624078`, `wikidata:Q7275`, and `wikidata:P17`.
- `有哪些国家` resolves the country class first, then uses L4 instance graph query over `P31`.
- L3 belief evidence traces through L2 statements to L0 provenance spans.
