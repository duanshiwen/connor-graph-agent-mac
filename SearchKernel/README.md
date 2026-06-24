# Connor Memory Search Kernel

This is the local embedded Memory OS search kernel.

It is designed to be compiled and packaged with Connor. It is not a server, daemon, HTTP sidecar, or external search service.

Responsibilities:

- Chinese/full-text candidate retrieval.
- Tantivy index schema and query execution.
- Jieba/CJK tokenization.
- C ABI for Swift in-process calls.

Non-responsibilities:

- L1/L2/L3/L4 graph traversal.
- Evidence trace.
- Instance enumeration.
- Timeline aggregation.

Those are owned by the Swift/SQLite Graph Retrieval Kernel.
